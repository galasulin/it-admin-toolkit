import SpotlightCard from '../bits/SpotlightCard.jsx';
import CountUp from '../bits/CountUp.jsx';

const QUICK = ['srv-health', 'srv-sql-backups', 'ad-locked', 'ad-find', 'ws-sysinfo', 'fix-wu-reset', 'sens-bl-ad', 'm365-fwd'];
const dark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
const spot = { theme: dark ? 'dark' : 'light', spotlightColor: dark ? '#5b8cff' : '#2457d6', intensity: dark ? 0.12 : 0.06, borderGlow: 0.45, style: { '--spotlight-card-surface': 'var(--surface)', padding: 0, borderRadius: 16 } };

function greeting() {
  const h = new Date().getHours();
  if (h < 5) return 'לילה טוב';
  if (h < 12) return 'בוקר טוב';
  if (h < 17) return 'צהריים טובים';
  if (h < 21) return 'ערב טוב';
  return 'לילה טוב';
}

export default function Home({ boot, onSelect, onRunDaily, onOpenConfig, dailyRunning }) {
  const d = boot.daily;
  const name = (boot.user.split('\\')[1] || '').trim();
  const quick = QUICK.map(id => boot.tools.find(t => t.id === id)).filter(Boolean);
  return (
    <div>
      {boot.exampleConfig && (
        <div className="banner" role="status">
          <span><b>ההגדרות עדיין לדוגמה.</b> צריך למלא ב-config.json את ה-DC, השרתים וגיבויי ה-SQL, ואז לפתוח את הכלי מחדש.</span>
          <button className="btn" onClick={onOpenConfig}>פתח את config.json</button>
        </div>
      )}
      <div className="home-h" data-intro>
        <div>
          <h1>{name ? `${greeting()}, ${name}` : greeting()}</h1>
          <p>{boot.tools.length} כלים, {boot.servers.length} שרתים בהגדרות. מחובר כ-<span className="mono">{boot.user}</span></p>
        </div>
        <button className="btn primary lg" onClick={onRunDaily} disabled={dailyRunning}>{dailyRunning ? 'הצ\'קליסט רץ…' : 'הרץ צ\'קליסט בוקר'}</button>
      </div>

      <div className="home-grid">
        <SpotlightCard {...spot} data-intro>
          <div className="daily">
            <div className="daily-top">
              <h2>צ'קליסט אחרון</h2>
              <span className="when">{d ? d.when : 'עוד לא רץ'}</span>
            </div>
            <div className="nums">
              {[['crit', 'קריטי', d?.crit], ['warn', 'לבדוק', d?.warn], ['ok', 'תקין', d?.ok]].map(([c, l, v]) => (
                <div className="num" data-c={c} key={c}>
                  <span className="v">{d ? <CountUp to={v || 0} duration={0.9} /> : '–'}</span>
                  <span className="l">{l}</span>
                </div>
              ))}
            </div>
            {d && d.top && d.top.length > 0 ? (
              <ul className="issues">
                {d.top.map((x, i) => (
                  <li key={i}>
                    <span className="st" data-c={/קריטי|אין חיבור|שגיאה/.test(x.status) ? 'crit' : 'warn'}>{x.status}</span>
                    <span className="srv">{x.server}</span>
                    <span className="det" title={x.details}>{x.item} · {x.details}</span>
                  </li>
                ))}
              </ul>
            ) : (
              <p style={{ margin: 0, color: 'var(--muted)', fontSize: 13.5 }}>
                {d ? 'הכול תקין בבדיקה האחרונה.' : 'הצ\'קליסט עובר על כל השרתים: דיסקים, שירותים, גיבויי SQL, Jobs, תעודות ומשתמשים נעולים.'}
              </p>
            )}
          </div>
        </SpotlightCard>

        <SpotlightCard {...spot} data-intro>
          <div className="quick">
            <h2 className="card-h">בשימוש הכי הרבה</h2>
            <div className="quick-grid">
              {quick.map(t => (
                <button key={t.id} className="qbtn" onClick={() => onSelect(t.id)}>
                  <b>{t.title}</b>
                  <span>{t.category}</span>
                </button>
              ))}
            </div>
          </div>
        </SpotlightCard>
      </div>

      <section className="panel history" data-intro>
        <h2 className="card-h">הרצות אחרונות</h2>
        {boot.history.length ? (
          <table className="hist">
            <tbody>
              {boot.history.slice(0, 12).map((h, i) => (
                <tr key={i}>
                  <td className="t">{h.when}</td>
                  <td>{h.title}</td>
                  <td className="mono" style={{ textAlign: 'right', color: 'var(--ink-2)' }}>{h.target}</td>
                  <td><span className="st" data-c={h.status === 'OK' ? 'ok' : h.status === 'FAILED' ? 'crit' : ''}>{h.status === 'OK' ? 'הצליח' : h.status === 'FAILED' ? 'נכשל' : h.status === 'STOPPED' ? 'נעצר' : h.status}</span></td>
                  <td style={{ color: 'var(--muted)' }}>{h.rows} שורות</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : <p style={{ color: 'var(--muted)', margin: '8px 0 0' }}>עוד לא הורץ אף כלי. כל הרצה נרשמת כאן ובלוג.</p>}
      </section>
    </div>
  );
}
