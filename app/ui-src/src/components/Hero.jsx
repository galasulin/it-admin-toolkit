import DotGrid from '../bits/DotGrid.jsx';

const reduce = typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const connText = { idle: 'לא נבדק', run: 'בודק…', ok: 'אפשר להריץ מרחוק', crit: 'אין גישה מרחוק', local: 'המחשב הזה' };

export default function Hero({ boot, target, setTarget, conn, onTest, onRdp, onMgmt, onCred, cred }) {
  const isLocal = !target || target === 'localhost';
  const state = isLocal ? 'local' : conn;
  return (
    <header className="hero">
      <div className="hero-bg" aria-hidden="true">
        <DotGrid dotSize={3} gap={17} baseColor="#24406b" activeColor="#8fb3ff" proximity={130} glow={0.35} swell={0.6}
                 shockRadius={220} shockStrength={3} intro={!reduce} mouseInteraction={!reduce} paused={reduce} />
      </div>
      <div className="hero-row">
        <div className="brand" data-intro>
          <div className="brand-mark" aria-hidden="true">
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none"><path d="M3 5h12M3 9h7M3 13h10" stroke="#8fb3ff" strokeWidth="2" strokeLinecap="round" /></svg>
          </div>
          <div>
            <div className="brand-name">ארגז כלים IT</div>
            <div className="brand-org">{boot.org}</div>
          </div>
        </div>

        <div className="target" data-intro>
          <span className="target-label">עובדים על</span>
          <div className="target-field">
            <input className="target-input" value={target} spellCheck={false} aria-label="יעד"
                   onChange={e => setTarget(e.target.value.trim())} placeholder="localhost" />
          </div>
          <span className="conn" data-s={state} role="status">
            <i aria-hidden="true" />{connText[state]}
          </span>
          <div className="target-chips hero-chips-wrap">
            {boot.targets.slice(0, 7).map(t => (
              <button key={t} className="chip-t" aria-pressed={t === target} onClick={() => setTarget(t)}>{t}</button>
            ))}
          </div>
        </div>

        <div className="hero-actions" data-intro>
          <button className="hbtn" onClick={onTest} disabled={isLocal}>בדוק חיבור</button>
          <button className="hbtn" onClick={onRdp} disabled={isLocal}>RDP</button>
          <button className="hbtn" onClick={onMgmt}>ניהול מחשב</button>
          <button className={`hbtn ${cred ? 'on' : ''}`} onClick={onCred} title={cred ? `מריץ כ-${cred}` : 'מריץ כמשתמש הנוכחי'}>
            {cred ? cred : 'הרשאות'}
          </button>
        </div>
      </div>
    </header>
  );
}
