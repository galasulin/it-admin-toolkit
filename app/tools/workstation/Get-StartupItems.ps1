param([hashtable]$P = @{})
$seen = @{}
foreach ($s in Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Where-Object { $_.Location -notmatch 'S-1-5-(18|19|20)\\' }) {
    $k = "$($s.Name)|$($s.Command)|$($s.User)"; if ($seen[$k]) { continue }; $seen[$k] = 1
    [pscustomobject]@{ 'שם' = $s.Name; 'פקודה' = $s.Command; 'מיקום' = $s.Location; 'משתמש' = $s.User }
}
# משימות מתוזמנות שרצות בכניסה או בהפעלה (לא של Microsoft)
try {
    foreach ($t in Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' }) {
        $trig = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName })
        if ($trig -match 'Logon|Boot') {
            $act = @($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join ' ; '
            [pscustomobject]@{ 'שם' = $t.TaskName; 'פקודה' = $act; 'מיקום' = "משימה מתוזמנת $($t.TaskPath)"; 'משתמש' = $t.Principal.UserId }
        }
    }
} catch {}
