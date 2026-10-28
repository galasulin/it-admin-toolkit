param([hashtable]$P = @{})
# קבצי PST/OST במקומות ש-Outlook שומר בהם בפועל, בכל פרופיל משתמש.
# לא סורק את כל C:\Users, כי זה לוקח דקות ארוכות במחשבים עם תיקיות פיתוח וגיבויים.
$found = @()
foreach ($u in Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue) {
    $deep = @(
        (Join-Path $u.FullName 'AppData\Local\Microsoft\Outlook'),
        (Join-Path $u.FullName 'Documents\Outlook Files'),
        (Join-Path $u.FullName 'OneDrive\Documents\Outlook Files')
    )
    foreach ($d in $deep) { if (Test-Path $d) { $found += Get-ChildItem $d -Include *.pst, *.ost -Recurse -File -Force -ErrorAction SilentlyContinue } }
    # שכבה אחת בלבד בשולחן העבודה ובמסמכים (שם אנשים שומרים ארכיונים ידנית)
    foreach ($d in 'Desktop', 'Documents', 'OneDrive\Desktop', 'OneDrive\Documents') {
        $x = Join-Path $u.FullName $d
        if (Test-Path $x) { $found += Get-ChildItem -Path (Join-Path $x '*') -Include *.pst, *.ost -File -Force -ErrorAction SilentlyContinue }
    }
}
# כוננים נוספים (לא C:): רק בשורש ובתיקיות מהשכבה הראשונה
foreach ($dk in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
    if ($dk.DeviceID -eq 'C:') { continue }
    $found += Get-ChildItem "$($dk.DeviceID)\*" -Include *.pst, *.ost -File -Force -ErrorAction SilentlyContinue
    foreach ($sub in Get-ChildItem "$($dk.DeviceID)\" -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\$|System Volume' }) {
        $found += Get-ChildItem (Join-Path $sub.FullName '*') -Include *.pst, *.ost -File -Force -ErrorAction SilentlyContinue
    }
}
$found = @($found | Sort-Object FullName -Unique)
if ($found.Count -eq 0) { [pscustomobject]@{ 'קובץ' = 'לא נמצאו קבצי PST/OST במיקומים הרגילים'; 'סוג' = ''; 'גודל GB' = ''; 'שונה לאחרונה' = ''; 'מצב' = 'תקין' }; return }
foreach ($f in $found | Sort-Object Length -Descending) {
    $gb = [math]::Round($f.Length / 1GB, 2)
    $st = 'תקין'; if ($gb -ge 45) { $st = 'קריטי' } elseif ($gb -ge 20) { $st = 'אזהרה' }
    [pscustomobject]@{ 'קובץ' = $f.FullName; 'סוג' = $f.Extension.TrimStart('.').ToUpper(); 'גודל GB' = $gb; 'שונה לאחרונה' = $f.LastWriteTime.ToString('dd/MM/yyyy'); 'מצב' = $st }
}
