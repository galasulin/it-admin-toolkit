param([hashtable]$P = @{})
function Emit($k, $v, $s) { [pscustomobject]@{ 'בדיקה' = $k; 'ערך' = "$v"; 'מצב' = $s } }
try { $m = Get-MpComputerStatus -ErrorAction Stop } catch {
    $av = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | ForEach-Object { $_.displayName })
    Emit 'Defender' "לא זמין. אנטי-וירוס רשום: $($av -join ', ')" 'לבדוק'; return
}
function OK([bool]$b) { if ($b) { 'תקין' } else { 'קריטי' } }
Emit 'אנטי-וירוס פעיל' $m.AntivirusEnabled (OK $m.AntivirusEnabled)
Emit 'הגנה בזמן אמת' $m.RealTimeProtectionEnabled (OK $m.RealTimeProtectionEnabled)
Emit 'Tamper Protection' $m.IsTamperProtected $(if ($m.IsTamperProtected) { 'תקין' } else { 'אזהרה' })
$age = $m.AntivirusSignatureAge
Emit 'גיל חתימות (ימים)' "$age · גרסה $($m.AntivirusSignatureVersion)" $(if ($age -le 2) { 'תקין' } elseif ($age -le 7) { 'אזהרה' } else { 'קריטי' })
$qs = $m.QuickScanEndTime
Emit 'סריקה מהירה אחרונה' $(if ($qs) { $qs.ToString('dd/MM/yyyy HH:mm') } else { 'אף פעם' }) $(if ($qs -and ((Get-Date) - $qs).TotalDays -le 7) { 'תקין' } else { 'אזהרה' })
Emit 'מצב מנוע' "$($m.AMRunningMode)" $(if ("$($m.AMRunningMode)" -match 'Normal') { 'תקין' } else { 'לבדוק' })
$th = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-30) })
if ($th.Count -eq 0) { Emit 'איומים ב-30 יום' 'אין' 'תקין' }
foreach ($t in $th) {
    $name = (Get-MpThreat -ThreatID $t.ThreatID -ErrorAction SilentlyContinue).ThreatName
    $txt = "$name · $($t.InitialDetectionTime.ToString('dd/MM HH:mm')) · $(@($t.Resources) -join ', ')"
    $ign = $false; foreach ($pat in @($P.IgnoreThreats)) { if ($pat -and $txt -like "*$pat*") { $ign = $true } }
    if ($ign) { Emit 'איום שזוהה (מוחרג ב-config)' $txt 'לא נדרש' } else { Emit 'איום שזוהה' $txt 'קריטי' }
}
