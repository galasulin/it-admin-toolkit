param([hashtable]$P = @{})
# מוחק קבצים זמניים בלבד, שלא שונו 7 ימים ומעלה. לא נוגע במסמכים, בהורדות או בסל המיחזור.
$days = 7; if ($P.Days) { $days = [int]$P.Days }
$cut = (Get-Date).AddDays(-$days)
$dirs = @("$env:SystemRoot\Temp", "$env:SystemRoot\SoftwareDistribution\Download")
foreach ($u in Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue) {
    $dirs += Join-Path $u.FullName 'AppData\Local\Temp'
    $dirs += Join-Path $u.FullName 'AppData\Local\Microsoft\Windows\INetCache'
    $dirs += Join-Path $u.FullName 'AppData\Local\CrashDumps'
}
$before = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
$total = 0; $count = 0; $failed = 0
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { continue }
    $sz = 0; $n = 0
    foreach ($f in Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut }) {
        try { $len = $f.Length; Remove-Item $f.FullName -Force -ErrorAction Stop; $sz += $len; $n++ } catch { $failed++ }
    }
    if ($n -gt 0) { [pscustomobject]@{ 'תיקייה' = $d; 'קבצים שנמחקו' = $n; 'פונה MB' = [math]::Round($sz / 1MB, 1); 'מצב' = 'בוצע' } }
    $total += $sz; $count += $n
}
$after = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
[pscustomobject]@{ 'תיקייה' = 'סה"כ'; 'קבצים שנמחקו' = $count; 'פונה MB' = [math]::Round($total / 1MB, 1); 'מצב' = "פנוי ב-C: עכשיו $([math]::Round($after/1GB,1)) GB (היה $([math]::Round($before/1GB,1))) · $failed קבצים נעולים דולגו" }
