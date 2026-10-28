param([hashtable]$P = @{})
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver'
function Emit($n, $st, $d) { [pscustomobject]@{ 'שלב' = $n; 'מצב' = $st; 'פרטים' = "$d" } }
foreach ($s in $svcs) {
    try { Stop-Service $s -Force -ErrorAction Stop; Emit "עצירת $s" 'בוצע' '' } catch { Emit "עצירת $s" 'אזהרה' $_.Exception.Message }
}
Start-Sleep -Seconds 2
foreach ($dir in "$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\System32\catroot2") {
    if (Test-Path $dir) {
        $new = "$(Split-Path $dir -Leaf).old_$stamp"
        try { Rename-Item $dir $new -ErrorAction Stop; Emit "שינוי שם $(Split-Path $dir -Leaf)" 'בוצע' "→ $new (אפשר למחוק ידנית אחרי שהעדכונים עובדים)" }
        catch { Emit "שינוי שם $(Split-Path $dir -Leaf)" 'נכשל' $_.Exception.Message }
    }
}
foreach ($s in $svcs) {
    try { Start-Service $s -ErrorAction Stop; Emit "הפעלת $s" 'בוצע' '' } catch { Emit "הפעלת $s" 'אזהרה' $_.Exception.Message }
}
Emit 'הבא בתור' '' 'להיכנס ל-Windows Update ולבדוק עדכונים. אם עדיין נכשל: להריץ "תיקון קבצי מערכת".'
