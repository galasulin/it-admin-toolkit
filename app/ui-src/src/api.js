// תקשורת עם השרת המקומי (PowerShell). הטוקן מגיע ב-hash של הכתובת ונמחק ממנה מיד.
let token = '';
try {
  const m = location.hash.match(/t=([A-Za-z0-9]+)/);
  if (m) {
    token = m[1];
    sessionStorage.setItem('tk', token);
    history.replaceState(null, '', location.pathname);
  } else {
    token = sessionStorage.getItem('tk') || '';
  }
} catch {
  /* sessionStorage חסום: נשארים עם מה שיש */
}

export async function api(path, body) {
  const res = await fetch(path, {
    method: body ? 'POST' : 'GET',
    headers: { 'X-Tk-Token': token, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined
  });
  let data = null;
  try { data = await res.json(); } catch { /* ריק */ }
  if (!res.ok) {
    if (res.status === 401) throw new Error('החיבור לשרת המקומי פג. סגור את החלון ופתח מחדש את Run.cmd.');
    throw new Error((data && data.error) || `שגיאה ${res.status}`);
  }
  return data;
}

export const hasToken = () => !!token;

// אותו מיפוי מצבים כמו בשרת (Get-TkStatusClass)
export function statusClass(s) {
  const v = String(s ?? '');
  if (/קריטי|נכשל|שגיאה|אין חיבור/.test(v)) return 'crit';
  if (/אזהרה|לבדוק/.test(v)) return 'warn';
  if (/תקין|הצליח|בוצע/.test(v)) return 'ok';
  return '';
}

export const riskLabel = {
  read: 'קריאה בלבד',
  change: 'מבצע שינוי',
  sensitive: 'מידע רגיש'
};

export function runOnLabel(tool, target, dc) {
  switch (tool.runOn) {
    case 'dc': return `רץ על בקר הדומיין ${dc || ''}`.trim();
    case 'local': return 'רץ מהמחשב שלך';
    case 'console': return 'נפתח בחלון נפרד להתחברות ל-Office 365';
    default: return `רץ על ${target || 'localhost'}`;
  }
}
