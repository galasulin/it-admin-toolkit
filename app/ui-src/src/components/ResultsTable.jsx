import { useLayoutEffect, useMemo, useRef, useState } from 'react';
import gsap from 'gsap';
import { statusClass } from '../api.js';

const SECRET_COLS = /סיסמה|מפתח שחזור|^מפתח$/;
const MONO_COLS = /^(IP|כתובת IP|MAC|SHA256|Thumbprint|Key ID|Build|מזהה|UPN|מייל|כתובת|יעד|Instance)$/;
const num = v => (v !== '' && !isNaN(Number(String(v).replace(/,/g, ''))) ? Number(String(v).replace(/,/g, '')) : null);
const reduce = typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function Secret({ value }) {
  const [shown, setShown] = useState(false);
  if (!value) return null;
  return (
    <span className="secret" title={shown ? 'לחץ להסתרה · לחיצה כפולה להעתקה' : 'לחץ להצגה'}
          onClick={() => setShown(s => !s)}
          onDoubleClick={() => navigator.clipboard?.writeText(value)}>
      {shown ? value : '••••••••••'}
    </span>
  );
}

export default function ResultsTable({ result, runKey }) {
  const { columns, data } = result;
  const [sort, setSort] = useState({ i: -1, dir: 1 });
  const [q, setQ] = useState('');
  const [sf, setSf] = useState('');
  const bodyRef = useRef(null);
  const si = columns.indexOf('מצב');

  const counts = useMemo(() => {
    const c = { crit: 0, warn: 0, ok: 0 };
    if (si >= 0) data.forEach(r => { const k = statusClass(r[si]); if (k) c[k]++; });
    return c;
  }, [data, si]);

  const rows = useMemo(() => {
    let r = data;
    if (sf && si >= 0) r = r.filter(x => statusClass(x[si]) === sf);
    const s = q.trim().toLowerCase();
    if (s) r = r.filter(x => x.some(v => String(v).toLowerCase().includes(s)));
    if (sort.i >= 0) {
      const i = sort.i;
      r = [...r].sort((a, b) => {
        const na = num(a[i]), nb = num(b[i]);
        if (na !== null && nb !== null) return (na - nb) * sort.dir;
        return String(a[i]).localeCompare(String(b[i]), 'he') * sort.dir;
      });
    }
    return r;
  }, [data, q, sf, sort, si]);

  // הופעה מדורגת של השורות, רק כשמגיעה תוצאה חדשה (לא בכל מיון או סינון)
  useLayoutEffect(() => {
    if (reduce || !bodyRef.current) return;
    const tr = Array.from(bodyRef.current.children).slice(0, 18);
    const t = gsap.fromTo(tr, { opacity: 0, y: 6 }, { opacity: 1, y: 0, duration: 0.28, ease: 'power3.out', stagger: 0.025, clearProps: 'transform,opacity' });
    return () => t.kill();
  }, [runKey]);

  const toggle = i => setSort(s => (s.i === i ? (s.dir === 1 ? { i, dir: -1 } : { i: -1, dir: 1 }) : { i, dir: 1 }));

  return (
    <>
      <div className="res-bar">
        {si >= 0 && (
          <div className="sfilter" role="group" aria-label="סינון לפי מצב">
            {[['crit', 'קריטי'], ['warn', 'לבדוק'], ['ok', 'תקין']].map(([k, l]) => (
              <button key={k} className="sf" data-c={k} aria-pressed={sf === k} onClick={() => setSf(v => (v === k ? '' : k))}>
                {l}<b>{counts[k]}</b>
              </button>
            ))}
          </div>
        )}
        <span className="grow" />
        <input className="filter" value={q} onChange={e => setQ(e.target.value)} placeholder="סינון בתוצאות" aria-label="סינון בתוצאות" />
      </div>
      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>{columns.map((c, i) => (
              <th key={c} onClick={() => toggle(i)} aria-sort={sort.i === i ? (sort.dir === 1 ? 'ascending' : 'descending') : 'none'}>
                {c}{sort.i === i && <span className="arr">{sort.dir === 1 ? '↑' : '↓'}</span>}
              </th>
            ))}</tr>
          </thead>
          <tbody ref={bodyRef}>
            {rows.map((r, ri) => {
              const c = si >= 0 ? statusClass(r[si]) : '';
              return (
                <tr key={ri} data-c={c}>
                  {r.map((v, i) => {
                    const col = columns[i];
                    if (i === si) return <td key={i}>{v ? <span className="st" data-c={statusClass(v)}>{v}</span> : null}</td>;
                    if (SECRET_COLS.test(col) || (col === 'ערך' && r[0] === 'סיסמה זמנית')) return <td key={i}><Secret value={v} /></td>;
                    if (MONO_COLS.test(col) || /^[\\\/A-Za-z]:?[\\\/]/.test(v)) return <td key={i}><span className="cellmono">{v}</span></td>;
                    if (/^https?:\/\//.test(v)) return <td key={i}><span className="cellmono">{v}</span></td>;
                    return <td key={i}>{v}</td>;
                  })}
                </tr>
              );
            })}
          </tbody>
        </table>
        {rows.length === 0 && <div className="empty">אין שורות שמתאימות לסינון</div>}
      </div>
    </>
  );
}
