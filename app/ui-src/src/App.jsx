import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import gsap from 'gsap';
import Lenis from 'lenis';
import { api } from './api.js';
import Hero from './components/Hero.jsx';
import Sidebar from './components/Sidebar.jsx';
import Home from './components/Home.jsx';
import ToolView from './components/ToolView.jsx';
import { ConfirmDialog, CredDialog, Palette, SimpleConfirm } from './components/Dialogs.jsx';

const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

export default function App() {
  const [boot, setBoot] = useState(null);
  const [bootErr, setBootErr] = useState('');
  const [sel, setSel] = useState(null);
  const [target, setTarget] = useState('localhost');
  const [conn, setConn] = useState('idle');
  const [runs, setRuns] = useState({});            // toolId -> { id, state, seconds, target, result }
  const [confirm, setConfirm] = useState(null);
  const [sensExport, setSensExport] = useState(null);
  const [palette, setPalette] = useState(false);
  const [credOpen, setCredOpen] = useState(false);
  const [toasts, setToasts] = useState([]);
  const mainRef = useRef(null);
  const innerRef = useRef(null);
  const appRef = useRef(null);

  const toast = useCallback((text, c = '') => {
    const id = Math.random();
    setToasts(t => [...t.slice(-3), { id, text, c }]);
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), c === 'crit' ? 7000 : 3800);
  }, []);

  const loadBoot = useCallback(() => api('/api/bootstrap').then(setBoot).catch(e => setBootErr(e.message)), []);
  useEffect(() => { loadBoot(); }, [loadBoot]);

  // דופק: כשהחלון נסגר, השרת נסגר לבד אחרי שלוש דקות
  useEffect(() => {
    const i = setInterval(() => api('/api/ping').catch(() => {}), 20000);
    api('/api/ping').catch(() => {});
    return () => clearInterval(i);
  }, []);

  // גלילה רכה באזור העבודה (Lenis), מסונכרנת לשעון של GSAP
  useEffect(() => {
    if (!boot || reduce || !mainRef.current) return;
    const lenis = new Lenis({ wrapper: mainRef.current, content: innerRef.current, duration: 0.9, smoothWheel: true });
    const tick = t => lenis.raf(t * 1000);
    gsap.ticker.add(tick);
    gsap.ticker.lagSmoothing(0);
    return () => { gsap.ticker.remove(tick); lenis.destroy(); };
  }, [boot]);

  // רגע פתיחה אחד: היעד והכלים נכנסים בסדר אחד מתוזמר. אחר כך אין אנימציות כניסה.
  useLayoutEffect(() => {
    if (!boot || reduce || !appRef.current) return;
    const ctx = gsap.context(() => {
      const tl = gsap.timeline({ defaults: { ease: 'power3.out' } });
      tl.from('.hero [data-intro]', { opacity: 0, y: -10, duration: 0.5, stagger: 0.07 })
        .from('.side [data-intro-item]', { opacity: 0, x: 12, duration: 0.35, stagger: 0.03 }, '-=0.3')
        .from('.main [data-intro]', { opacity: 0, y: 14, duration: 0.45, stagger: 0.06, clearProps: 'transform' }, '-=0.35');
    }, appRef);
    return () => ctx.revert();
  }, [boot]);

  // Ctrl+K: פלטת פקודות, בלי אנימציה
  useEffect(() => {
    const h = e => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); setPalette(p => !p); }
    };
    window.addEventListener('keydown', h);
    return () => window.removeEventListener('keydown', h);
  }, []);

  useEffect(() => { setConn('idle'); }, [target]);
  useEffect(() => { mainRef.current?.scrollTo({ top: 0 }); }, [sel]);

  // מעקב אחרי כלים שרצים
  useEffect(() => {
    const live = Object.entries(runs).filter(([, r]) => r.state === 'running');
    if (!live.length) return;
    const t = setTimeout(async () => {
      for (const [toolId, r] of live) {
        try {
          const j = await api(`/api/job?id=${r.id}`);
          if (j.state === 'running') { setRuns(x => ({ ...x, [toolId]: { ...x[toolId], seconds: j.seconds } })); continue; }
          setRuns(x => ({ ...x, [toolId]: { ...x[toolId], state: 'done', result: j } }));
          const tool = boot.tools.find(tt => tt.id === toolId);
          if (toolId === 'net-winrm') {
            const si = j.columns.indexOf('מצב');
            const bad = j.data.some(row => /קריטי/.test(row[si]));
            setConn(bad || j.status === 'FAILED' ? 'crit' : 'ok');
          }
          if (j.status === 'FAILED') toast(`${tool.title}: נכשל`, 'crit');
          else if (sel !== toolId) toast(`${tool.title} הסתיים · ${j.data.length} שורות`);
          if (toolId === 'rep-daily') loadBoot();
        } catch (e) {
          setRuns(x => ({ ...x, [toolId]: { ...x[toolId], state: 'done', result: { status: 'FAILED', seconds: 0, columns: [], data: [], errors: [e.message] } } }));
        }
      }
    }, 800);
    return () => clearTimeout(t);
  }, [runs, boot, sel, toast, loadBoot]);

  const start = async (tool, vals, confirmed = false) => {
    if (!confirmed && (tool.risk === 'change' || tool.risk === 'sensitive')) { setConfirm({ tool, vals }); return; }
    try {
      const r = await api('/api/run', { toolId: tool.id, target, params: vals, confirmed });
      setRuns(x => ({ ...x, [tool.id]: { id: r.id, state: 'running', seconds: 0, target: r.target, result: x[tool.id]?.result } }));
    } catch (e) { toast(e.message, 'crit'); }
  };

  const stop = async tool => { const r = runs[tool.id]; if (r) await api('/api/stop', { id: r.id }).catch(() => {}); };

  const doExport = async (tool, run, kind, confirmSensitive = false) => {
    const res = run.result;
    if (kind === 'copy') {
      const lines = [res.columns.join('\t'), ...res.data.map(r => r.join('\t'))].join('\n');
      await navigator.clipboard.writeText(lines).then(() => toast('הועתק. אפשר להדביק באקסל או במייל.')).catch(() => toast('ההעתקה נחסמה', 'crit'));
      return;
    }
    if (kind === 'open') { api('/api/open', { kind: 'file', path: res.saved }).catch(e => toast(e.message, 'crit')); return; }
    if (tool.risk === 'sensitive' && !confirmSensitive) { setSensExport({ tool, run, kind }); return; }
    try { const r = await api('/api/export', { id: run.id, format: kind, confirmSensitive }); toast(`נשמר ונפתח: ${r.path.split('\\').pop()}`); }
    catch (e) { toast(e.message, 'crit'); }
  };

  const runTool = id => {
    const t = boot.tools.find(x => x.id === id);
    if (t) start(t, {});
  };

  if (bootErr) return <div className="empty" style={{ paddingTop: '20vh' }}><h2>הכלי לא הצליח להתחבר לשרת המקומי</h2><p>{bootErr}</p></div>;
  if (!boot) return <div className="empty" style={{ paddingTop: '30vh' }}><div className="spinner" style={{ margin: '0 auto' }} /></div>;

  const tool = sel ? boot.tools.find(t => t.id === sel) : null;
  const runningIds = Object.entries(runs).filter(([, r]) => r.state === 'running').map(([k]) => k);

  return (
    <div className="app" ref={appRef}>
      <Hero boot={boot} target={target} setTarget={setTarget} conn={runs['net-winrm']?.state === 'running' ? 'run' : conn} cred={boot.cred}
            onTest={() => { setSel('net-winrm'); runTool('net-winrm'); }}
            onRdp={() => api('/api/open', { kind: 'rdp', target }).catch(e => toast(e.message, 'crit'))}
            onMgmt={() => api('/api/open', { kind: 'mgmt', target }).catch(e => toast(e.message, 'crit'))}
            onCred={() => setCredOpen(true)} />
      <Sidebar boot={boot} selected={sel} onSelect={setSel} runningIds={runningIds} onPalette={() => setPalette(true)} />
      <main className="main" ref={mainRef}>
        <div className="main-inner" ref={innerRef}>
          {tool ? (
            <ToolView key={tool.id} tool={tool} boot={boot} target={target} run={runs[tool.id]} onRun={start} onStop={stop} onExport={doExport} />
          ) : (
            <Home boot={boot} onSelect={setSel} dailyRunning={runs['rep-daily']?.state === 'running'}
                  onRunDaily={() => { setSel('rep-daily'); runTool('rep-daily'); }}
                  onOpenConfig={() => api('/api/open', { kind: 'config' })} />
          )}
        </div>
      </main>

      {confirm && (
        <ConfirmDialog tool={confirm.tool} params={confirm.vals}
                       target={confirm.tool.runOn === 'dc' ? boot.dc : confirm.tool.runOn === 'target' ? (target || 'localhost') : 'המחשב שלך'}
                       onNo={() => setConfirm(null)} onYes={() => { const c = confirm; setConfirm(null); start(c.tool, c.vals, true); }} />
      )}
      {sensExport && (
        <SimpleConfirm title="לשמור מידע רגיש בקובץ?" text="הקובץ יישמר בתיקיית reports על הדיסק, עם הסיסמאות או המפתחות. מומלץ למחוק אותו אחרי השימוש." yes="שמור"
                       onNo={() => setSensExport(null)} onYes={() => { const s = sensExport; setSensExport(null); doExport(s.tool, s.run, s.kind, true); }} />
      )}
      {credOpen && (
        <CredDialog current={boot.cred} onClose={() => setCredOpen(false)}
                    onSave={async (u, p) => { const r = await api('/api/cred', { user: u, password: p }); setBoot(b => ({ ...b, cred: r.cred })); setCredOpen(false); toast(`מריץ מעכשיו כ-${r.cred}`); }}
                    onClear={async () => { await api('/api/cred', { clear: true }); setBoot(b => ({ ...b, cred: null })); setCredOpen(false); toast('חזרה למשתמש הנוכחי'); }} />
      )}
      {palette && <Palette tools={boot.tools} onClose={() => setPalette(false)} onPick={id => { setSel(id); setPalette(false); }} />}

      <div className="toasts" aria-live="polite">
        {toasts.map(t => <div key={t.id} className="toast" data-c={t.c}>{t.text}</div>)}
      </div>
    </div>
  );
}
