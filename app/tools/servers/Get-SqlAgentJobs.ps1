param([hashtable]$P = @{})
if (-not (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^MSSQLSERVER$|^MSSQL\$' })) { [pscustomobject]@{ 'Instance' = $env:COMPUTERNAME; 'מצב' = 'לא נדרש'; 'פרטים' = 'אין SQL Server במחשב הזה. בחר ביעד שרת SQL.' }; return }
$instances = @('.'); if ($P.Instances) { $instances = @($P.Instances) }
$q = @"
SELECT j.name, j.enabled, s.last_run_outcome AS o, s.last_run_date AS d, s.last_run_time AS t, s.last_run_duration AS dur,
 (SELECT TOP 1 h.message FROM msdb.dbo.sysjobhistory h WHERE h.job_id=j.job_id AND h.step_id=0 ORDER BY h.instance_id DESC) AS msg,
 (SELECT COUNT(*) FROM msdb.dbo.sysjobhistory h WHERE h.job_id=j.job_id AND h.step_id=0 AND h.run_status=0
   AND msdb.dbo.agent_datetime(h.run_date,h.run_time) > DATEADD(day,-7,GETDATE())) AS fails7
FROM msdb.dbo.sysjobs j LEFT JOIN msdb.dbo.sysjobservers s ON s.job_id=j.job_id ORDER BY j.name
"@
$outc = @{ 0 = 'נכשל'; 1 = 'הצליח'; 2 = 'ניסיון חוזר'; 3 = 'בוטל'; 5 = 'לא ידוע' }
foreach ($inst in $instances) {
    $cn = New-Object System.Data.SqlClient.SqlConnection "Server=$inst;Database=msdb;Integrated Security=True;Connect Timeout=10;Application Name=IT-Toolkit"
    try {
        $cn.Open(); $cmd = $cn.CreateCommand(); $cmd.CommandText = $q
        $dt = New-Object System.Data.DataTable; $dt.Load($cmd.ExecuteReader())
    } catch { [pscustomobject]@{ 'Instance' = $inst; 'Job' = ''; 'פעיל' = ''; 'מצב' = 'שגיאה'; 'הרצה אחרונה' = ''; 'כישלונות 7 ימים' = ''; 'פרטים' = $_.Exception.Message }; continue }
    finally { $cn.Close() }
    $iname = ($inst -split '\\')[1]
    $svcName = 'SQLSERVERAGENT'; if ($iname -and $iname -ne 'MSSQLSERVER') { $svcName = "SQLAgent`$$iname" }
    $agent = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($agent -and $agent.Status -ne 'Running') { [pscustomobject]@{ 'Instance' = $inst; 'Job' = 'שירות SQL Agent'; 'פעיל' = ''; 'מצב' = 'קריטי'; 'הרצה אחרונה' = ''; 'כישלונות 7 ימים' = ''; 'פרטים' = "השירות במצב $($agent.Status). אף Job לא ירוץ." } }
    foreach ($r in $dt.Rows) {
        $when = ''
        if (-not ($r.d -is [DBNull]) -and [int]$r.d -gt 0) {
            $ds = "$($r.d)"; $ts = ("{0:D6}" -f [int]$r.t)
            $when = "$($ds.Substring(6,2))/$($ds.Substring(4,2))/$($ds.Substring(0,4)) $($ts.Substring(0,2)):$($ts.Substring(2,2))"
        }
        $o = -1; if (-not ($r.o -is [DBNull])) { $o = [int]$r.o }
        $txt = $outc[$o]; if (-not $txt) { $txt = 'לא רץ' }
        $st = 'תקין'
        if ([int]$r.enabled -eq 0) { $st = 'לא נדרש'; $txt = "מושבת · $txt" }
        elseif ($o -eq 0) { $st = 'קריטי' }
        elseif ([int]$r.fails7 -gt 0) { $st = 'אזהרה' }
        $msg = "$($r.msg)"; if ($o -ne 0) { $msg = '' } elseif ($msg.Length -gt 200) { $msg = $msg.Substring(0, 200) + '…' }
        [pscustomobject]@{ 'Instance' = $inst; 'Job' = "$($r.name)"; 'פעיל' = $(if ([int]$r.enabled) { 'כן' } else { 'לא' }); 'מצב' = $st; 'הרצה אחרונה' = "$when · $txt"; 'כישלונות 7 ימים' = [int]$r.fails7; 'פרטים' = $msg }
    }
}
