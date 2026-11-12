param([hashtable]$P = @{})
# צ'קליסט בוקר: עובר על כל השרתים ב-config ומחזיר טבלה אחת, כשמה שלא תקין מופיע ראשון
$root = $P._Root; $cred = $P._Cred
$cfg = Get-Content (Join-Path $root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$T = Join-Path $root 'tools'
$base = @{ DiskWarn = [int]$cfg.DiskWarnPercent; DiskCrit = [int]$cfg.DiskCriticalPercent; SqlMaxHours = [int]$cfg.SqlFullBackupMaxHours; Days = 30 }
if (-not $base.DiskWarn) { $base.DiskWarn = 20 }; if (-not $base.DiskCrit) { $base.DiskCrit = 10 }; if (-not $base.SqlMaxHours) { $base.SqlMaxHours = 26 }
$rows = New-Object System.Collections.ArrayList
function Add($srv, $cat, $item, $st, $det) { [void]$rows.Add([pscustomobject]@{ 'שרת' = $srv; 'קטגוריה' = $cat; 'פריט' = $item; 'מצב' = $st; 'פרטים' = "$det" }) }
function Run($srv, $file, $params) {
    $isLocal = @('.', 'localhost', [Environment]::MachineName.ToLower()) -contains $srv.ToLower()
    if ($isLocal) { return & $file $params }
    $a = @{ ComputerName = $srv; FilePath = $file; ArgumentList = @(, $params); ErrorAction = 'Stop' }
    if ($cred) { $a.Credential = $cred }
    return Invoke-Command @a
}
$servers = @($cfg.Servers | Where-Object { $_.Name })
if ($cfg.DomainController -and -not ($servers | Where-Object { $_.Name -eq $cfg.DomainController })) { $servers += [pscustomobject]@{ Name = $cfg.DomainController; Roles = @('DC') } }
foreach ($s in $servers) {
    $n = "$($s.Name)"
    $item = $base.Clone()
    if ($s.SqlInstances) { $item.Instances = @($s.SqlInstances) }
    if ($s.SqlDatabases) { $item.Databases = @($s.SqlDatabases) }
    if ($s.SqlIgnoreDatabases) { $item.IgnoreDatabases = @($s.SqlIgnoreDatabases) }
    try { $h = Run $n (Join-Path $T 'servers\Get-ServerHealth.ps1') $item } catch { Add $n 'חיבור' 'הגעה לשרת' 'אין חיבור' $_.Exception.Message; continue }
    foreach ($r in $h) { Add $n $r.'קטגוריה' $r.'פריט' $r.'מצב' $r.'פרטים' }
    try { foreach ($r in Run $n (Join-Path $T 'servers\Get-ExpiringCertificates.ps1') $item) { if ($r.'מצב' -ne 'תקין') { Add $n 'תעודות' $r.'תעודה' $r.'מצב' "פג ב-$($r.'פג תוקף') ($($r.'ימים שנותרו') ימים)" } } } catch {}
    if ($s.SqlInstances -or (@($s.Roles) -contains 'SQL')) {
        try {
            foreach ($r in Run $n (Join-Path $T 'servers\Get-SqlBackupStatus.ps1') $item) {
                if ($r.'מצב' -eq 'לא נדרש') { continue }
                Add $n 'גיבוי SQL' "$($r.Instance) · $($r.'מסד נתונים')" $r.'מצב' "מלא: $($r.'גיבוי מלא אחרון') · Diff: $($r.'Diff אחרון') · Checksum: $($r.Checksum) $($r.'פרטים')"
            }
        } catch { Add $n 'גיבוי SQL' 'בדיקה' 'שגיאה' $_.Exception.Message }
        try {
            foreach ($r in Run $n (Join-Path $T 'servers\Get-SqlAgentJobs.ps1') $item) {
                if ($r.'מצב' -in 'קריטי', 'אזהרה', 'שגיאה') { Add $n 'SQL Agent' $r.Job $r.'מצב' "$($r.'הרצה אחרונה') $($r.'פרטים')" }
            }
        } catch {}
    }
    if ($n -eq "$($cfg.DomainController)") {
        try { foreach ($r in Run $n (Join-Path $T 'ad\Get-LockedUsers.ps1') $item) { if ($r.'שם משתמש') { Add $n 'AD' "נעול: $($r.'שם משתמש')" 'אזהרה' "$($r.'שם') · $($r.'נעל ב')" } } } catch {}
    }
}
# קבצי גיבוי בתיקיות שיתוף (BackupFolders ב-config)
foreach ($b in @($cfg.BackupFolders)) {
    if (-not $b -or -not $b.Path) { continue }
    $maxH = 26; if ($b.MaxAgeHours) { $maxH = [int]$b.MaxAgeHours }
    try {
        $last = Get-ChildItem $b.Path -File -Recurse -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $last) { Add 'תיקיית גיבוי' 'קבצי גיבוי' $b.Path 'קריטי' 'התיקייה ריקה'; continue }
        $age = [int]((Get-Date) - $last.LastWriteTime).TotalHours
        Add 'תיקיית גיבוי' 'קבצי גיבוי' $b.Path $(if ($age -gt $maxH) { 'קריטי' } else { 'תקין' }) "אחרון: $($last.Name) · לפני $age שעות · $([math]::Round($last.Length/1GB,2)) GB"
    } catch { Add 'תיקיית גיבוי' 'קבצי גיבוי' $b.Path 'אין חיבור' $_.Exception.Message }
}
$order = @{ 'אין חיבור' = 0; 'קריטי' = 1; 'שגיאה' = 1; 'אזהרה' = 2; 'לבדוק' = 3; 'תקין' = 9 }
$rows | Sort-Object @{ e = { $o = $order["$($_.'מצב')"]; if ($null -eq $o) { 5 } else { $o } } }, 'שרת'
