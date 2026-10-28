import { useMemo, useState } from 'react';

const Chevron = () => (
  <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><path d="M2 3.5 5 6.5 8 3.5" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" /></svg>
);

export default function Sidebar({ boot, selected, onSelect, runningIds, onPalette }) {
  const [q, setQ] = useState('');
  const [closed, setClosed] = useState({});
  const groups = useMemo(() => {
    const s = q.trim();
    return boot.categories.map(c => ({
      cat: c,
      tools: boot.tools.filter(t => t.category === c && (!s || t.title.includes(s) || t.desc.includes(s) || t.id.includes(s.toLowerCase())))
    })).filter(g => g.tools.length);
  }, [boot, q]);

  return (
    <aside className="side" aria-label="כלים">
      <div className="side-search">
        <div className="search">
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="חיפוש כלי" aria-label="חיפוש כלי"
                 onKeyDown={e => { if (e.key === 'Escape') setQ(''); }} />
          <button className="kbd" onClick={onPalette} tabIndex={-1} aria-label="פלטת פקודות">Ctrl K</button>
        </div>
      </div>
      <nav className="side-scroll">
        <button className="home-link" data-intro-item aria-current={selected === null} onClick={() => onSelect(null)}>
          <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden="true"><path d="M2 7.5 8 2.5l6 5V14H10v-4H6v4H2z" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinejoin="round" /></svg>
          סקירה
        </button>
        {groups.map(g => {
          const open = q ? true : !closed[g.cat];
          return (
            <div className="cat" key={g.cat} data-intro-item>
              <button className="cat-h" aria-expanded={open} onClick={() => setClosed(c => ({ ...c, [g.cat]: open }))}>
                <span>{g.cat}</span>
                <span style={{ display: 'inline-flex', gap: 8, alignItems: 'center' }}><span className="n">{g.tools.length}</span><Chevron /></span>
              </button>
              {open && g.tools.map(t => (
                <button key={t.id} className="tool-btn" aria-current={selected === t.id} onClick={() => onSelect(t.id)}>
                  <span className="risk-dot" data-r={t.risk} aria-hidden="true" />
                  <span>{t.title}</span>
                  {runningIds.includes(t.id) && <span className="run-ind" aria-label="רץ" />}
                </button>
              ))}
            </div>
          );
        })}
        {groups.length === 0 && <div className="empty">לא נמצא כלי בשם הזה</div>}
      </nav>
      <div className="side-foot">
        <span><i className="risk-dot" data-r="read" />קריאה</span>
        <span><i className="risk-dot" data-r="change" />שינוי</span>
        <span><i className="risk-dot" data-r="sensitive" />רגיש</span>
      </div>
    </aside>
  );
}
