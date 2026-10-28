param([hashtable]$P = @{})
function Get-WingetPath {
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue; if ($c) { return $c.Source }
    $d = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($d -and (Test-Path (Join-Path $d.FullName 'winget.exe'))) { return (Join-Path $d.FullName 'winget.exe') }
}
$wg = Get-WingetPath
if (-not $wg) { throw 'winget לא מותקן במחשב' }
$lines = @(& $wg upgrade --include-unknown --accept-source-agreements --disable-interactivity 2>&1 | ForEach-Object { "$_" })
$hdr = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^-{10,}') { $hdr = $i; break } }
if ($hdr -lt 1) { [pscustomobject]@{ 'תוכנה' = 'אין עדכונים זמינים (או ש-winget לא החזיר רשימה)'; 'מזהה' = ''; 'גרסה נוכחית' = ''; 'גרסה זמינה' = ''; 'מצב' = 'תקין' }; return }
$head = $lines[$hdr - 1]
$cols = @([regex]::Matches($head, '\S+(?:\s\S+)*') | ForEach-Object { $_.Index })
foreach ($l in $lines[($hdr + 1)..($lines.Count - 1)]) {
    if ($l -match 'upgrades available|עדכונים זמינים|^\s*$' -or $l.Length -lt $cols[-1]) { continue }
    $f = @(); for ($c = 0; $c -lt $cols.Count; $c++) { $s = $cols[$c]; $e = $(if ($c + 1 -lt $cols.Count) { $cols[$c + 1] } else { $l.Length }); if ($s -lt $l.Length) { $f += $l.Substring($s, [math]::Min($e, $l.Length) - $s).Trim() } else { $f += '' } }
    [pscustomobject]@{ 'תוכנה' = $f[0]; 'מזהה' = $f[1]; 'גרסה נוכחית' = $f[2]; 'גרסה זמינה' = $f[3]; 'מצב' = 'אזהרה' }
}
