"""Build docs/index.html from app/catalog.json and the scripts folders (run: python docs/build_page.py)."""
import html, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cat = json.load(open(os.path.join(ROOT, "app", "catalog.json"), encoding="utf-8-sig"))
RISK = {"read": ("קריאה בלבד", "read-only", "r"), "change": ("משנה הגדרות", "changes settings", "c"),
        "sensitive": ("רגיש", "sensitive", "d")}

def synopsis(path):
    txt = open(path, encoding="utf-8-sig", errors="replace").read()
    m = re.search(r"\.SYNOPSIS\s*\n\s*(.+)", txt)
    ex = re.search(r"\.EXAMPLE\s*\n\s*(.+)", txt)
    return (m.group(1).strip() if m else ""), (ex.group(1).strip() if ex else "")

groups = []
for c in cat["categories"]:
    tools = [t for t in cat["tools"] if t["category"] == c]
    groups.append((c, tools))

scripts = []
for d in ["sql", "m365", "windows-update", "outlook", "network", "endpoint", "ad"]:
    p = os.path.join(ROOT, d)
    if not os.path.isdir(p):
        continue
    for dp, _, fns in sorted(os.walk(p)):
        for f in sorted(fns):
            if f.endswith((".ps1", ".sql")):
                s, e = synopsis(os.path.join(dp, f))
                scripts.append((os.path.relpath(dp, ROOT).replace("\\", "/"), f, s, e))

def esc(x):
    return html.escape(str(x or ""))

cards = []
for c, tools in groups:
    items = []
    for t in tools:
        he, en, cls = RISK.get(t.get("risk", "read"), (t.get("risk", ""), t.get("risk", ""), "r"))
        items.append(f'<li><b>{esc(t["title"])}</b><span class="risk {cls}">{he}</span><p>{esc(t.get("desc"))}</p></li>')
    cards.append(f'<section class="cat"><h3>{esc(c)} <small>{len(tools)}</small></h3><ul>{"".join(items)}</ul></section>')

rows = "".join(f'<tr><td><code>{esc(d)}/{esc(f)}</code></td><td>{esc(s)}</td><td><code>{esc(e)}</code></td></tr>' for d, f, s, e in scripts)

page = f"""<!doctype html>
<html lang="he" dir="rtl">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>IT Admin Toolkit · Gal Asulin</title>
<meta name="description" content="A Windows IT toolkit: a local web UI with {len(cat['tools'])} admin tools in {len(cat['categories'])} categories, plus {len(scripts)} standalone PowerShell scripts.">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Heebo:wght@400;600;800&display=swap" rel="stylesheet">
<style>
:root{{--bg:#f4f6fb;--surface:#fff;--text:#121a2b;--muted:#5a6478;--line:#dde2ec;--brand:#1f4fd1;--soft:#e6edff;--r:#15803d;--c:#b45309;--d:#b91c1c}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{--bg:#0d1220;--surface:#141b2d;--text:#e7ecf6;--muted:#9aa6bd;--line:#26314a;--brand:#7aa2ff;--soft:#1b2a52;--r:#4ade80;--c:#fbbf24;--d:#f87171}}}}
:root[data-theme="dark"]{{--bg:#0d1220;--surface:#141b2d;--text:#e7ecf6;--muted:#9aa6bd;--line:#26314a;--brand:#7aa2ff;--soft:#1b2a52;--r:#4ade80;--c:#fbbf24;--d:#f87171}}
*{{box-sizing:border-box}} body{{margin:0;background:var(--bg);color:var(--text);font-family:Heebo,"Segoe UI",Arial,sans-serif;line-height:1.6}}
.wrap{{max-width:1180px;margin:0 auto;padding:0 16px}} header{{padding:52px 0 10px}}
h1{{font-size:clamp(30px,4.4vw,46px);margin:0 0 8px;line-height:1.15}} .lead{{color:var(--muted);font-size:18px;max-width:820px;margin:0}}
.stats{{display:flex;flex-wrap:wrap;gap:12px;margin:22px 0}} .stat{{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:12px 18px}} .stat b{{display:block;font-size:26px;color:var(--brand)}}
.shots{{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin:10px 0 30px}} @media (max-width:820px){{.shots{{grid-template-columns:1fr}}}}
figure{{margin:0;background:var(--surface);border:1px solid var(--line);border-radius:12px;overflow:hidden}} figure img{{width:100%;display:block;border-bottom:1px solid var(--line)}} figcaption{{padding:10px 14px;color:var(--muted);font-size:15px}}
h2{{font-size:28px;margin:36px 0 6px}} .sub{{color:var(--muted);margin:0 0 16px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:14px}}
.cat{{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:14px 16px}} .cat h3{{margin:0 0 8px;font-size:18px}} .cat h3 small{{color:var(--muted);font-weight:400}}
.cat ul{{list-style:none;margin:0;padding:0;display:grid;gap:8px}} .cat li{{border-top:1px solid var(--line);padding-top:8px}} .cat li p{{margin:2px 0 0;color:var(--muted);font-size:14.5px}}
.risk{{font-size:12px;font-weight:700;border-radius:999px;padding:1px 8px;margin-inline-start:8px;border:1px solid currentColor}} .risk.r{{color:var(--r)}} .risk.c{{color:var(--c)}} .risk.d{{color:var(--d)}}
table{{width:100%;border-collapse:collapse;background:var(--surface);border:1px solid var(--line);border-radius:12px;overflow:hidden;font-size:15px}} td{{border-top:1px solid var(--line);padding:8px 10px;vertical-align:top}} td code{{direction:ltr;unicode-bidi:embed;font-size:13px}}
.tablewrap{{overflow-x:auto}} footer{{border-top:1px solid var(--line);margin-top:40px;padding:22px 0 40px;color:var(--muted)}} a{{color:var(--brand)}}
</style></head>
<body>
<header class="wrap">
<h1>IT Admin Toolkit · ארגז כלים IT</h1>
<p class="lead">ארגז כלים שבניתי לניהול IT ברשת מרפאות: ממשק מקומי בעברית שמריץ {len(cat['tools'])} כלי ניהול ב-{len(cat['categories'])} קטגוריות על המחשב הזה או על שרת יעד, ולצידו {len(scripts)} סקריפטים עצמאיים ב-PowerShell. <span dir="ltr">A local Hebrew web UI with {len(cat['tools'])} admin tools in {len(cat['categories'])} categories, plus {len(scripts)} standalone PowerShell scripts.</span></p>
<div class="stats"><div class="stat"><b>{len(cat['tools'])}</b>כלים בממשק</div><div class="stat"><b>{len(cat['categories'])}</b>קטגוריות</div><div class="stat"><b>{len(scripts)}</b>סקריפטים עצמאיים</div><div class="stat"><b>127.0.0.1</b>השרת מאזין רק למחשב המקומי, עם טוקן אקראי</div></div>
</header>
<main class="wrap">
<div class="shots">
<figure><img src="screenshots/app-home.png" alt="Toolkit home screen with demo identity and example servers" loading="lazy"><figcaption>מסך הבית: צ'קליסט בוקר, הכלים הנפוצים והיעדים. config של דמו (Demo Org · demo.local)</figcaption></figure>
<figure><img src="screenshots/app-tool-result.png" alt="A read-only tool after a local run, Disk status" loading="lazy"><figcaption>כלי לקריאה בלבד ("מצב דיסקים") אחרי הרצה על המחשב המקומי</figcaption></figure>
</div>
<h2>הכלים בממשק</h2><p class="sub">כל כלי מסומן לפי רמת הסיכון. כלים שמשנים הגדרות מבקשים אישור, וכל הרצה נרשמת ביומן.</p>
<div class="grid">{''.join(cards)}</div>
<h2>הסקריפטים העצמאיים</h2><p class="sub">כל סקריפט עם עזרה מובנית (Get-Help), פרמטרים במקום שמות קשיחים, ו-<code>-WhatIf</code> כשהוא משנה משהו.</p>
<div class="tablewrap"><table><tbody>{rows}</tbody></table></div>
</main>
<footer class="wrap">Built by <a href="https://github.com/galasulin">Gal Asulin</a>, IT Manager · <a href="https://github.com/galasulin/it-admin-toolkit">it-admin-toolkit</a></footer>
</body></html>
"""
open(os.path.join(ROOT, "docs", "index.html"), "w", encoding="utf-8").write(page)
print("tools", len(cat["tools"]), "categories", len(cat["categories"]), "scripts", len(scripts))
