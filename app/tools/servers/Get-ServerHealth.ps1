param([hashtable]$P = @{})
$warn = 20; if ($P.DiskWarn) { $warn = [int]$P.DiskWarn }
$crit = 10; if ($P.DiskCrit) { $crit = [int]$P.DiskCrit }
function Emit($c, $i, $s, $d) { [pscustomobject]@{ 'קטגוריה' = $c; 'פריט' = $i; 'מצב' = $s; 'פרטים' = "$d" } }

$os = Get-CimInstance Win32_OperatingSystem
$up = (Get-Date) - $os.LastBootUpTime
$st = 'תקין'; if ($up.TotalDays -gt 60) { $st = 'אזהרה' }
Emit 'מערכת' 'זמן פעילות' $st ("{0} ימים (מאז {1})" -f [int]$up.TotalDays, $os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm'))
$memPct = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100)
$st = 'תקין'; if ($memPct -gt 95) { $st = 'קריטי' } elseif ($memPct -gt 85) { $st = 'אזהרה' }
Emit 'מערכת' 'ניצול זיכרון' $st "$memPct% מתוך $([math]::Round($os.TotalVisibleMemorySize/1MB)) GB"
$cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average)
$st = 'תקין'; if ($cpu -gt 90) { $st = 'אזהרה' }
Emit 'מערכת' 'ניצול מעבד (רגעי)' $st "$cpu%"

foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
    if (-not $d.Size) { continue }
    $pct = [math]::Round($d.FreeSpace / $d.Size * 100, 1)
    $st = 'תקין'; if ($pct -lt $crit) { $st = 'קריטי' } elseif ($pct -lt $warn) { $st = 'אזהרה' }
    Emit 'דיסק' "$($d.DeviceID) $($d.VolumeName)".Trim() $st ("{0}% פנוי · {1} מתוך {2} GB" -f $pct, [math]::Round($d.FreeSpace/1GB,1), [math]::Round($d.Size/1GB))
}

$ignore = 'gupdate|edgeupdate|MapsBroker|RemoteRegistry|sppsvc|tiledatamodelsvc|CDPSvc|WbioSrvc|ShellHWDetection|TrustedInstaller|BITS|wuauserv|UsoSvc|DoSvc|stisvc|GoogleUpdater|clr_optimization|MSDTC|SysMain|WaaSMedicSvc|camsvc|AGMService|AGSService'
$stopped = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" | Where-Object { $_.Name -notmatch $ignore })
if ($stopped.Count -eq 0) { Emit 'שירותים' 'שירותים אוטומטיים' 'תקין' 'כולם רצים' }
foreach ($s in $stopped) { Emit 'שירותים' $s.DisplayName 'אזהרה' "מוגדר אוטומטי אבל במצב $($s.State) · $($s.Name)" }

$pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($pend) { Emit 'מערכת' 'ממתין לאתחול' 'אזהרה' 'כן, עדכונים ממתינים לאתחול' } else { Emit 'מערכת' 'ממתין לאתחול' 'תקין' 'לא' }

$hf = Get-HotFix -ErrorAction SilentlyContinue | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
if ($hf) {
    $age = [int]((Get-Date) - $hf.InstalledOn).TotalDays
    $st = 'תקין'; if ($age -gt 60) { $st = 'קריטי' } elseif ($age -gt 35) { $st = 'אזהרה' }
    Emit 'עדכונים' 'עדכון אחרון' $st "$($hf.HotFixID) לפני $age ימים"
}

$ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = (Get-Date).AddHours(-24) } -MaxEvents 1000 -ErrorAction SilentlyContinue)
$crt = @($ev | Where-Object { $_.Level -eq 1 }).Count
$st = 'תקין'; if ($crt -gt 0) { $st = 'קריטי' } elseif ($ev.Count -gt 50) { $st = 'אזהרה' }
$top = ($ev | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', '
Emit 'יומנים' 'שגיאות ב-24 שעות' $st "$($ev.Count) שגיאות, $crt קריטיות · מובילים: $top"
