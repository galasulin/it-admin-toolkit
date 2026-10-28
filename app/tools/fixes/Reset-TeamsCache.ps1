param([hashtable]$P = @{})
# משנה שם לתיקיות ה-Cache של Teams (הקלאסי והחדש). לא נמחק כלום. מדלג על משתמש ש-Teams פתוח אצלו.
$user = "$($P.User)".Trim()
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$running = @{}
foreach ($pr in Get-CimInstance Win32_Process -Filter "Name='ms-teams.exe' OR Name='Teams.exe'" -ErrorAction SilentlyContinue) {
    $o = Invoke-CimMethod -InputObject $pr -MethodName GetOwner -ErrorAction SilentlyContinue
    if ($o.User) { $running[$o.User.ToLower()] = 1 }
}
foreach ($u in Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue) {
    if ($user -and $u.Name -ne $user) { continue }
    $paths = @(
        (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Teams'),
        (Join-Path $u.FullName 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams')
    ) | Where-Object { Test-Path $_ }
    if (-not $paths) { continue }
    if ($running[$u.Name.ToLower()]) {
        [pscustomobject]@{ 'משתמש' = $u.Name; 'תיקייה' = ''; 'מצב' = 'דולג'; 'פרטים' = 'Teams פתוח אצל המשתמש. לסגור אותו ולהריץ שוב.' }
        continue
    }
    foreach ($item in $paths) {
        try { Rename-Item $item "$(Split-Path $item -Leaf).old_$stamp" -ErrorAction Stop; [pscustomobject]@{ 'משתמש' = $u.Name; 'תיקייה' = $item; 'מצב' = 'בוצע'; 'פרטים' = 'Teams ייבנה מחדש בפתיחה הבאה' } }
        catch { [pscustomobject]@{ 'משתמש' = $u.Name; 'תיקייה' = $item; 'מצב' = 'נכשל'; 'פרטים' = $_.Exception.Message } }
    }
}
