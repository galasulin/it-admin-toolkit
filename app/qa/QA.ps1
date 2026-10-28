#Requires -Version 5.1
# QA אוטומטי לארגז הכלים: מריץ כל כלי "קריאה בלבד" על המחשב הזה ושומר תוצאות ל-qa\qa-results.json
# לא מריץ אף כלי שמשנה משהו. תוכן של כלים רגישים לא נשמר (רק כמה שורות ואילו עמודות).
$ErrorActionPreference = 'Continue'
$QaDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root  = Split-Path -Parent $QaDir

$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return
}
$host.UI.RawUI.WindowTitle = 'IT-Toolkit QA'
Start-Transcript -Path (Join-Path $QaDir 'qa-transcript.txt') -Force | Out-Null
Get-ChildItem $Root -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

$env_ = [ordered]@{
    when = (Get-Date).ToString('s'); ps = "$($PSVersionTable.PSVersion)"; os = (Get-CimInstance Win32_OperatingSystem).Caption
    build = [Environment]::OSVersion.Version.ToString(); user = "$env:USERDOMAIN\$env:USERNAME"; computer = $env:COMPUTERNAME
    domain = (Get-CimInstance Win32_ComputerSystem).Domain; logonServer = $env:LOGONSERVER; culture = (Get-Culture).Name; uiCulture = (Get-UICulture).Name
    edge = [bool](Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") -or [bool](Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")
    winrm = "$((Get-Service WinRM -ErrorAction SilentlyContinue).Status)"; adModule = [bool](Get-Module -ListAvailable ActiveDirectory)
}
Write-Host "סביבה: $($env_ | ConvertTo-Json -Compress)" -ForegroundColor Cyan

try { Import-Module (Join-Path $Root 'modules\Toolkit.Core.psm1') -Force -ErrorAction Stop } catch { Write-Host "Import failed: $_" -ForegroundColor Red }
$Config = Get-TkConfig -Root $Root
$Catalog = Get-TkCatalog -Root $Root
$skip = @('sens-vt', 'net-scan')
$results = New-Object System.Collections.ArrayList
$tools = @($Catalog.tools | Where-Object { $_.risk -in 'read', 'sensitive' -and $_.runOn -in 'target', 'local' -and $skip -notcontains $_.id })
$onlyFile = Join-Path $QaDir 'only.txt'
if (Test-Path $onlyFile) { $only = @(Get-Content $onlyFile | Where-Object { $_.Trim() }); $tools = @($tools | Where-Object { $only -contains $_.id }) }
$i = 0
foreach ($t in $tools) {
    $i++
    Write-Host ("[{0}/{1}] {2} ({3})" -f $i, $tools.Count, $t.title, $t.id) -ForegroundColor Yellow
    $p = @{}
    foreach ($par in @($t.params)) { if ($par) { $p[$par.name] = "$($par.default)" } }
    if ($t.id -eq 'net-test') { $p['Hosts'] = 'localhost' }
    if ($t.id -eq 'net-winrm') { $p['Target'] = 'localhost' }
    if ($Config.DefenderIgnoreThreats) { $p['IgnoreThreats'] = @($Config.DefenderIgnoreThreats) }
    $p['DiskWarn'] = [int]$Config.DiskWarnPercent; $p['DiskCrit'] = [int]$Config.DiskCriticalPercent; $p['SqlMaxHours'] = [int]$Config.SqlFullBackupMaxHours
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $job = Start-TkTool -Root $Root -Tool $t -Target 'localhost' -Params $p -Credential $null
    $done = Wait-Job $job -Timeout 300
    $state = "$($job.State)"
    if (-not $done) { Stop-Job $job; $state = 'TIMEOUT' }
    $out = Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable jerr
    $errs = @(); foreach ($cj in $job.ChildJobs) { foreach ($e in $cj.Error) { $errs += "$e" } }
    foreach ($e in @($jerr)) { if ($e -and $errs -notcontains "$e") { $errs += "$e" } }
    if ($state -eq 'Failed' -and $job.ChildJobs[0].JobStateInfo.Reason) { $errs += $job.ChildJobs[0].JobStateInfo.Reason.Message }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $rows = ConvertTo-TkRows $out
    $cols = @(); if ($rows.Count) { $cols = @($rows[0].PSObject.Properties | ForEach-Object Name) }
    $sample = @()
    if ($t.risk -ne 'sensitive') { $sample = @($rows | Select-Object -First 4 | ForEach-Object { $o = $_; ($cols | ForEach-Object { "$_=$($o.$_)" }) -join ' | ' }) }
    $statuses = @($rows | ForEach-Object { "$($_.'מצב')" } | Where-Object { $_ } | Group-Object | ForEach-Object { "$($_.Name):$($_.Count)" })
    [void]$results.Add([ordered]@{ id = $t.id; title = $t.title; state = $state; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); rows = $rows.Count; columns = $cols; statuses = $statuses; errors = @($errs | Select-Object -First 5); sample = $sample })
    $c = 'Green'; if ($errs.Count -or $rows.Count -eq 0 -or $state -ne 'Completed') { $c = 'Red' }
    Write-Host ("    {0} · {1} שורות · {2}s · {3}" -f $state, $rows.Count, [math]::Round($sw.Elapsed.TotalSeconds), ($errs | Select-Object -First 1)) -ForegroundColor $c
}

# בדיקת ייצוא HTML וכתיבת לוג
try { $h = Export-TkHtml -Rows (ConvertTo-TkRows @([pscustomobject]@{ 'בדיקה' = 'א'; 'מצב' = 'תקין' })) -Title 'QA' -Path (Join-Path $QaDir 'qa-export.html'); $exportOk = Test-Path $h } catch { $exportOk = "$_" }

$report = [ordered]@{ env = $env_; exportOk = $exportOk; tools = $results }
[IO.File]::WriteAllText((Join-Path $QaDir ('qa-results' + $(if (Test-Path $onlyFile) { '-2' } else { '' }) + '.json')), ($report | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
Write-Host ''
Write-Host 'הסתיים. מפעיל שרת QA ברקע לבדיקת הממשק (נסגר לבד אחרי 3 דקות בלי חלון).' -ForegroundColor Cyan
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Root 'Start-Toolkit.ps1')`" -Serve -Port 8799 -Token qatest"
Set-Content -Path (Join-Path $QaDir 'qa-done.txt') -Value (Get-Date).ToString('s')
Stop-Transcript | Out-Null
Start-Sleep -Seconds 4
