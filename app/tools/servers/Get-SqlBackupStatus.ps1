param([hashtable]$P = @{})
if (-not (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^MSSQLSERVER$|^MSSQL\$' })) { [pscustomobject]@{ 'Instance' = $env:COMPUTERNAME; 'מצב' = 'לא נדרש'; 'פרטים' = 'אין SQL Server במחשב הזה. בחר ביעד שרת SQL.' }; return }
$maxH = 26; if ($P.SqlMaxHours) { $maxH = [int]$P.SqlMaxHours }
$instances = @('.'); if ($P.Instances) { $instances = @($P.Instances) }
$required = @(); if ($P.Databases) { $required = @($P.Databases | ForEach-Object { "$_".ToLower() }) }
$ignored = @(); if ($P.IgnoreDatabases) { $ignored = @($P.IgnoreDatabases | ForEach-Object { "$_".ToLower() }) }
$q = @"
SELECT d.name, d.recovery_model_desc AS rm, d.state_desc AS st,
 (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset b WHERE b.database_name=d.name AND b.type='D') AS lf,
 (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset b WHERE b.database_name=d.name AND b.type='I') AS ld,
 (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset b WHERE b.database_name=d.name AND b.type='L') AS ll,
 (SELECT TOP 1 CAST(has_backup_checksums AS int) FROM msdb.dbo.backupset b WHERE b.database_name=d.name AND b.type IN ('D','I') ORDER BY backup_finish_date DESC) AS chk,
 (SELECT TOP 1 CAST(compressed_backup_size/1048576.0 AS decimal(18,1)) FROM msdb.dbo.backupset b WHERE b.database_name=d.name AND b.type='D' ORDER BY backup_finish_date DESC) AS mb,
 (SELECT TOP 1 m.physical_device_name FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily m ON m.media_set_id=b.media_set_id WHERE b.database_name=d.name AND b.type='D' ORDER BY b.backup_finish_date DESC) AS dev
FROM sys.databases d WHERE d.name <> 'tempdb' ORDER BY d.name
"@
function Fmt($v) { if ($v -is [DBNull] -or $null -eq $v) { return 'אף פעם' }; return ([datetime]$v).ToString('dd/MM/yyyy HH:mm') }
foreach ($inst in $instances) {
    $cn = New-Object System.Data.SqlClient.SqlConnection "Server=$inst;Database=master;Integrated Security=True;Connect Timeout=10;Application Name=IT-Toolkit"
    try {
        $cn.Open()
        $cmd = $cn.CreateCommand(); $cmd.CommandText = $q; $cmd.CommandTimeout = 60
        $dt = New-Object System.Data.DataTable; $dt.Load($cmd.ExecuteReader())
    } catch {
        [pscustomobject]@{ 'Instance' = $inst; 'מסד נתונים' = ''; 'מצב' = 'שגיאה'; 'גיבוי מלא אחרון' = ''; 'Diff אחרון' = ''; 'Log אחרון' = ''; 'Checksum' = ''; 'Recovery' = ''; 'גודל MB' = ''; 'יעד' = ''; 'פרטים' = $_.Exception.Message }
        continue
    } finally { $cn.Close() }
    foreach ($r in $dt.Rows) {
        $name = "$($r.name)"
        $isReq = (($required.Count -eq 0) -or ($required -contains $name.ToLower())) -and -not ($ignored | Where-Object { $name -like $_ })
        $isSys = @('master', 'model', 'msdb') -contains $name.ToLower()
        $latest = $null
        foreach ($c in 'lf', 'ld') { if (-not ($r[$c] -is [DBNull])) { if (-not $latest -or [datetime]$r[$c] -gt $latest) { $latest = [datetime]$r[$c] } } }
        $note = ''
        if ("$($r.st)" -ne 'ONLINE') { $st = 'לבדוק'; $note = "המסד במצב $($r.st)" }
        elseif (-not $latest) { $st = 'קריטי'; $note = 'אין אף גיבוי' }
        elseif (((Get-Date) - $latest).TotalHours -gt $maxH) { $st = 'קריטי'; $note = "הגיבוי האחרון לפני $([int]((Get-Date)-$latest).TotalHours) שעות" }
        else { $st = 'תקין' }
        if (-not $isSys -and $st -eq 'תקין' -and "$($r.rm)" -eq 'FULL' -and ($r.ll -is [DBNull] -or ((Get-Date) - [datetime]$r.ll).TotalHours -gt 24)) { $st = 'אזהרה'; $note = 'Recovery FULL בלי גיבוי Log עדכני. קובץ ה-LDF יגדל.' }
        if (-not $isSys -and $st -eq 'תקין' -and "$($r.chk)" -ne '1') { $st = 'אזהרה'; $note = 'הגיבוי האחרון בלי CHECKSUM' }
        if (-not $isReq -and $st -ne 'תקין') { $st = 'לא נדרש'; $note = "לא נדרש גיבוי (לפי config) · $note" }
        if ($isSys -and $st -eq 'קריטי') { $st = 'אזהרה' }
        $chk = 'לא'; if ("$($r.chk)" -eq '1') { $chk = 'כן' }
        [pscustomobject]@{
            'Instance' = $inst; 'מסד נתונים' = $name; 'מצב' = $st
            'גיבוי מלא אחרון' = Fmt $r.lf; 'Diff אחרון' = Fmt $r.ld; 'Log אחרון' = Fmt $r.ll
            'Checksum' = $chk; 'Recovery' = "$($r.rm)"; 'גודל MB' = "$($r.mb)"; 'יעד' = "$($r.dev)"; 'פרטים' = $note
        }
    }
}
