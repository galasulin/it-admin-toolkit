param([hashtable]$P = @{})
function Emit($n, $st, $d) { [pscustomobject]@{ 'שלב' = $n; 'מצב' = $st; 'פרטים' = "$d" } }
$t = Get-Date
$p1 = Start-Process dism.exe -ArgumentList '/Online /Cleanup-Image /RestoreHealth /NoRestart' -Wait -PassThru -WindowStyle Hidden
$m1 = [int]((Get-Date) - $t).TotalMinutes
if ($p1.ExitCode -eq 0) { Emit 'DISM RestoreHealth' 'הצליח' "$m1 דקות" } else { Emit 'DISM RestoreHealth' 'נכשל' "קוד $($p1.ExitCode) · לוג: C:\Windows\Logs\DISM\dism.log" }
$t = Get-Date
$p2 = Start-Process sfc.exe -ArgumentList '/scannow' -Wait -PassThru -WindowStyle Hidden
$m2 = [int]((Get-Date) - $t).TotalMinutes
$cbs = "$env:SystemRoot\Logs\CBS\CBS.log"
$summary = ''
try {
    $tail = Get-Content $cbs -Tail 4000 -ErrorAction Stop | Where-Object { $_ -match '\[SR\]' }
    if ($tail -match 'Repairing corrupted file|Repaired file') { $summary = 'נמצאו ותוקנו קבצים פגומים' }
    elseif ($tail -match 'Cannot repair') { $summary = 'נמצאו קבצים שלא ניתן לתקן' }
    else { $summary = 'לא נמצאו בעיות' }
} catch {}
$st = 'הצליח'; if ($p2.ExitCode -ne 0) { $st = 'אזהרה' }
if ($summary -match 'שלא ניתן') { $st = 'נכשל' }
Emit 'SFC /scannow' $st "$m2 דקות · $summary · קוד $($p2.ExitCode)"
Emit 'המלצה' '' 'אם תוקנו קבצים, מומלץ לאתחל את המחשב.'
