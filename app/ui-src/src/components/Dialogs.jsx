import { Fragment, useEffect, useRef, useState } from 'react';

function useEscape(onClose) {
  useEffect(() => {
    const h = e => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', h);
    return () => window.removeEventListener('keydown', h);
  }, [onClose]);
}

export function ConfirmDialog({ tool, target, params, onYes, onNo }) {
  useEscape(onNo);
  const yes = useRef(null);
  useEffect(() => { yes.current?.focus(); }, []);
  const sens = tool.risk === 'sensitive';
  const shown = (tool.params || []).filter(p => p.type !== 'credential' && params[p.name]);
  return (
    <div className="overlay" onMouseDown={e => e.target === e.currentTarget && onNo()}>
      <div className="dialog" data-r={tool.risk} role="alertdialog" aria-modal="true" aria-labelledby="cf-t">
        <h3 id="cf-t">{sens ? 'להציג מידע רגיש?' : 'להריץ את הפעולה?'}</h3>
        <p>{sens ? 'התוצאה תופיע על המסך. כדאי לוודא שאף אחד לא רואה אותו.' : 'זו פעולה שמשנה משהו ביעד. כדאי לעבור על מה שיקרה לפני שממשיכים.'}</p>
        <dl className="kv">
          <dt>כלי</dt><dd>{tool.title}</dd>
          <dt>יעד</dt><dd className="mono" style={{ textAlign: 'right' }}>{target}</dd>
          {shown.map(p => (<Fragment key={p.name}><dt>{p.label}</dt><dd>{params[p.name]}</dd></Fragment>))}
        </dl>
        <pre className="actions-list">{tool.actions || tool.desc}</pre>
        <div className="row">
          <button className="btn ghost" onClick={onNo}>ביטול</button>
          <button ref={yes} className={`btn ${sens ? 'sensb' : 'warnb'}`} onClick={onYes}>{sens ? 'הצג' : 'הרץ'}</button>
        </div>
      </div>
    </div>
  );
}

export function CredDialog({ current, onSave, onClear, onClose }) {
  useEscape(onClose);
  const [u, setU] = useState('');
  const [p, setP] = useState('');
  return (
    <div className="overlay" onMouseDown={e => e.target === e.currentTarget && onClose()}>
      <form className="dialog" role="dialog" aria-modal="true" aria-labelledby="cr-t" onSubmit={e => { e.preventDefault(); if (u) onSave(u, p); }}>
        <h3 id="cr-t">הרצה מרחוק עם משתמש אחר</h3>
        <p>{current ? `כרגע מריץ כ-${current}.` : 'כרגע מריץ כמשתמש שפתח את הכלי.'} הסיסמה נשמרת רק בזיכרון של הכלי עד שהוא נסגר.</p>
        <div className="field"><label htmlFor="cu">משתמש</label><input id="cu" className="input ltr" autoFocus value={u} onChange={e => setU(e.target.value)} placeholder="DOMAIN\admin" autoComplete="off" /></div>
        <div className="field"><label htmlFor="cp">סיסמה</label><input id="cp" className="input ltr" type="password" value={p} onChange={e => setP(e.target.value)} autoComplete="off" /></div>
        <div className="row">
          {current && <button type="button" className="btn ghost" onClick={onClear}>חזרה למשתמש הנוכחי</button>}
          <button type="button" className="btn" onClick={onClose}>ביטול</button>
          <button type="submit" className="btn primary" disabled={!u}>שמור</button>
        </div>
      </form>
    </div>
  );
}

export function SimpleConfirm({ title, text, yes, onYes, onNo }) {
  useEscape(onNo);
  return (
    <div className="overlay" onMouseDown={e => e.target === e.currentTarget && onNo()}>
      <div className="dialog" data-r="sensitive" role="alertdialog" aria-modal="true">
        <h3>{title}</h3>
        <p>{text}</p>
        <div className="row">
          <button className="btn ghost" onClick={onNo}>ביטול</button>
          <button className="btn sensb" autoFocus onClick={onYes}>{yes}</button>
        </div>
      </div>
    </div>
  );
}

export function Palette({ tools, onPick, onClose }) {
  useEscape(onClose);
  const [q, setQ] = useState('');
  const [i, setI] = useState(0);
  const s = q.trim();
  const list = (s ? tools.filter(t => t.title.includes(s) || t.desc.includes(s) || t.category.includes(s) || t.id.includes(s.toLowerCase())) : tools).slice(0, 40);
  const key = e => {
    if (e.key === 'ArrowDown') { e.preventDefault(); setI(x => Math.min(list.length - 1, x + 1)); }
    if (e.key === 'ArrowUp') { e.preventDefault(); setI(x => Math.max(0, x - 1)); }
    if (e.key === 'Enter' && list[i]) onPick(list[i].id);
  };
  return (
    <div className="overlay top" onMouseDown={e => e.target === e.currentTarget && onClose()}>
      <div className="palette" role="dialog" aria-modal="true" aria-label="חיפוש כלי">
        <input autoFocus value={q} onChange={e => { setQ(e.target.value); setI(0); }} onKeyDown={key} placeholder="מה צריך לעשות? למשל: נעול, גיבוי, מדפסת" />
        <ul className="pal-list" role="listbox">
          {list.map((t, n) => (
            <li key={t.id} className="pal-item" role="option" aria-selected={n === i} onMouseEnter={() => setI(n)} onClick={() => onPick(t.id)}>
              <span className="risk-dot" data-r={t.risk} />
              <span>{t.title}<span className="d">{t.desc}</span></span>
              <span className="c">{t.category}</span>
            </li>
          ))}
          {list.length === 0 && <li className="empty">אין כלי שמתאים</li>}
        </ul>
      </div>
    </div>
  );
}
