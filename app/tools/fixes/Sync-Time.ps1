param([hashtable]$P = @{})
function Emit($n, $st, $d) { [pscustomobject]@{ 'שלב' = $n; 'מצב' = $st; 'פרטים' = "$d" } }
$tz = Get-TimeZone
$st = 'תקין'; if ($tz.Id -ne 'Israel Standard Time') { $st = 'אזהרה' }
Emit 'אזור זמן' $st $tz.DisplayName
if ($P.SetIsrael -eq 'כן' -and $tz.Id -ne 'Israel Standard Time') {
    try { Set-TimeZone -Id 'Israel Standard Time'; Emit 'שינוי אזור זמן' 'בוצע' 'Israel Standard Time' } catch { Emit 'שינוי אזור זמן' 'נכשל' $_.Exception.Message }
}
$w = Get-Service w32time -ErrorAction SilentlyContinue
if ($w.Status -ne 'Running') { try { Start-Service w32time; Emit 'שירות זמן' 'בוצע' 'הופעל' } catch { Emit 'שירות זמן' 'נכשל' $_.Exception.Message } }
$out = (w32tm.exe /resync /force 2>&1 | Out-String).Trim()
Emit 'סנכרון שעון' $(if ($LASTEXITCODE -eq 0) { 'בוצע' } else { 'נכשל' }) $out
Emit 'מקור הזמן' '' ((w32tm.exe /query /source 2>&1 | Out-String).Trim())
