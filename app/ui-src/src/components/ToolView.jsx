import { useEffect, useState } from 'react';
import ShinyText from '../bits/ShinyText.jsx';
import ResultsTable from './ResultsTable.jsx';
import { riskLabel, runOnLabel } from '../api.js';

function hintFor(errors) {
  const e = errors.join(' ');
  if (/WinRM|WS-Management|cannot connect|לא ניתן להתחבר/i.test(e)) return 'היעד לא מקבל פקודות מרחוק. לחץ "בדוק חיבור" למעלה כדי לראות מה חוסם.';
  if (/Access is denied|הגישה נדחתה/i.test(e)) return 'אין הרשאה ביעד. לחץ "הרשאות" והזן משתמש Domain Admin.';
  if (/ActiveDirectory/i.test(e)) return 'מודול ActiveDirectory לא נמצא ב-DC. בדוק שה-DomainController ב-config.json הוא באמת בקר דומיין.';
  if (/SqlClient|SQL Server|network-related/i.test(e)) return 'אין חיבור ל-SQL. בדוק את SqlInstances של השרת ב-config.json (למשל .\\SQLEXPRESS).';
  return '';
}

export default function ToolView({ tool, boot, target, run, onRun, onStop, onExport }) {
  const [vals, setVals] = useState({});
  useEffect(() => {
    const v = {};
    (tool.params || []).forEach(p => { v[p.name] = p.type === 'credential' ? { user: '', password: '' } : String(p.default ?? ''); });
    setVals(v);
  }, [tool.id]);

  const running = run && run.state === 'running';
  const res = run && run.result;
  const missing = (tool.params || []).some(p => p.required && (p.type === 'credential' ? !vals[p.name]?.user : !String(vals[p.name] ?? '').trim()));
  const runText = tool.risk === 'change' ? 'הרץ…' : tool.risk === 'sensitive' ? 'הצג…' : 'הרץ';
  const effTarget = tool.runOn === 'dc' ? boot.dc : tool.runOn === 'local' || tool.runOn === 'console' ? 'localhost' : (target || 'localhost');

  return (
    <div>
      <div className="tool-head">
        <div className="crumb">{tool.category}</div>
        <h1 className="tool-title">{tool.title}</h1>
        <p className="tool-desc">{tool.desc}</p>
        <div className="badges">
          <span className="badge" data-r={tool.risk}>{riskLabel[tool.risk]}</span>
          <span className="badge">{runOnLabel(tool, target || 'localhost', boot.dc)}</span>
        </div>
      </div>

      <form className="panel run-panel" onSubmit={e => { e.preventDefault(); if (!running && !missing) onRun(tool, vals); }}>
        {(tool.params || []).length > 0 && (
          <div className="params">
            {tool.params.map(p => p.type === 'credential' ? (
              <div className="field" key={p.name} style={{ gridColumn: '1 / -1' }}>
                <label>{p.label}</label>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                  <input className="input ltr" placeholder="DOMAIN\user" autoComplete="off" value={vals[p.name]?.user || ''}
                         onChange={e => setVals(v => ({ ...v, [p.name]: { ...v[p.name], user: e.target.value } }))} />
                  <input className="input ltr" type="password" placeholder="סיסמה" autoComplete="off" value={vals[p.name]?.password || ''}
                         onChange={e => setVals(v => ({ ...v, [p.name]: { ...v[p.name], password: e.target.value } }))} />
                </div>
              </div>
            ) : (
              <div className="field" key={p.name}>
                <label htmlFor={`p-${p.name}`}>{p.label}</label>
                {/^(כן|לא)$/.test(String(p.default)) ? (
                  <div className="seg" role="group">
                    {['כן', 'לא'].map(o => <button type="button" key={o} aria-pressed={vals[p.name] === o} onClick={() => setVals(v => ({ ...v, [p.name]: o }))}>{o}</button>)}
                  </div>
                ) : (
                  <input id={`p-${p.name}`} className={`input ${/[A-Za-z\\\\]/.test(String(p.default)) || /נתיב|שם משתמש|Sam|מזהי|מזהים|כתובת|רשת|Key ID|פורטים|יעדים|דומיין|OU/.test(p.label) ? 'ltr' : ''}`}
                         value={vals[p.name] ?? ''} onChange={e => setVals(v => ({ ...v, [p.name]: e.target.value }))} required={p.required} />
                )}
              </div>
            ))}
          </div>
        )}
        <div className="run-row">
          {!running ? (
            <button type="submit" className={`btn lg ${tool.risk === 'change' ? 'warnb' : tool.risk === 'sensitive' ? 'sensb' : 'primary'}`} disabled={missing}>{runText}</button>
          ) : (
            <button type="button" className="btn lg" onClick={() => onStop(tool)}>עצור</button>
          )}
          <span className="run-meta">
            {running ? <ShinyText text={`רץ על ${run.target} · ${run.seconds || 0} שניות`} color="#667385" shineColor="#2457d6" speed={1.6} /> :
              res ? `הסתיים לפני רגע · ${res.seconds} שניות · ${res.data.length} שורות` : `יעד: ${effTarget}`}
          </span>
        </div>
      </form>

      {res && (
        <section className="panel results" aria-label="תוצאות">
          <div className="res-bar" style={{ borderBottom: 0, paddingBottom: 0 }}>
            <span className="res-title">תוצאות</span>
            <span className="res-sub mono">{run.target}</span>
            <span className="grow" />
            {res.saved && <button className="btn ghost" onClick={() => onExport(tool, run, 'open')}>פתח את הדוח שנשמר</button>}
            <button className="btn" disabled={!res.data.length} onClick={() => onExport(tool, run, 'html')}>דוח HTML</button>
            <button className="btn" disabled={!res.data.length} onClick={() => onExport(tool, run, 'csv')}>אקסל</button>
            <button className="btn" disabled={!res.data.length} onClick={() => onExport(tool, run, 'copy')}>העתק</button>
          </div>
          {res.errors.length > 0 && (
            <div className="errors" role="alert">
              {res.errors.slice(0, 4).map((e, i) => <div key={i}>{e}</div>)}
              {hintFor(res.errors) && <div className="tip">{hintFor(res.errors)}</div>}
            </div>
          )}
          {res.data.length > 0 ? <ResultsTable result={res} runKey={run.id} /> : !res.errors.length && <div className="empty">הכלי הסתיים בלי תוצאות</div>}
        </section>
      )}
    </div>
  );
}
