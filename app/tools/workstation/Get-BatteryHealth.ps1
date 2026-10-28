param([hashtable]$P = @{})
$b = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
if ($b.Count -eq 0) { [pscustomobject]@{ 'סוללה' = 'אין סוללה (מחשב נייח או שרת)'; 'קיבולת מקורית mWh' = ''; 'קיבולת כיום mWh' = ''; 'בריאות %' = ''; 'מחזורי טעינה' = ''; 'מצב' = '' }; return }
$xml = Join-Path $env:TEMP ("battery-" + [guid]::NewGuid().ToString('N') + '.xml')
powercfg.exe /batteryreport /xml /output "$xml" | Out-Null
try {
    [xml]$r = Get-Content $xml -Raw
    foreach ($x in @($r.BatteryReport.Batteries.Battery)) {
        $des = [double]$x.DesignCapacity; $full = [double]$x.FullChargeCapacity
        $h = 0; if ($des -gt 0) { $h = [math]::Round($full / $des * 100) }
        $st = 'תקין'; if ($h -lt 50) { $st = 'קריטי' } elseif ($h -lt 70) { $st = 'אזהרה' }
        [pscustomobject]@{ 'סוללה' = "$($x.Manufacturer) $($x.Id)".Trim(); 'קיבולת מקורית mWh' = $des; 'קיבולת כיום mWh' = $full; 'בריאות %' = $h; 'מחזורי טעינה' = $x.CycleCount; 'מצב' = $st }
    }
} finally { Remove-Item $xml -ErrorAction SilentlyContinue }
