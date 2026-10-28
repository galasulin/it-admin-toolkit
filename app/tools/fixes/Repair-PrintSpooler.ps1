param([hashtable]$P = @{})
function Emit($n, $st, $d) { [pscustomobject]@{ 'שלב' = $n; 'מצב' = $st; 'פרטים' = "$d" } }
$q = "$env:SystemRoot\System32\spool\PRINTERS"
$bk = "C:\ProgramData\IT-Toolkit\spool-backup\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
try { Stop-Service Spooler -Force -ErrorAction Stop; Emit 'עצירת Spooler' 'בוצע' '' } catch { Emit 'עצירת Spooler' 'נכשל' $_.Exception.Message; return }
Start-Sleep -Seconds 2
$files = @(Get-ChildItem $q -File -ErrorAction SilentlyContinue)
if ($files.Count -gt 0) {
    New-Item -ItemType Directory -Path $bk -Force | Out-Null
    $moved = 0
    foreach ($f in $files) { try { Move-Item $f.FullName $bk -Force -ErrorAction Stop; $moved++ } catch {} }
    Emit 'ניקוי התור' 'בוצע' "$moved מתוך $($files.Count) קבצים הועברו ל-$bk"
} else { Emit 'ניקוי התור' 'בוצע' 'התור היה ריק' }
try { Start-Service Spooler -ErrorAction Stop; Emit 'הפעלת Spooler' 'בוצע' '' } catch { Emit 'הפעלת Spooler' 'נכשל' $_.Exception.Message }
$pr = @(Get-Printer -ErrorAction SilentlyContinue)
Emit 'מדפסות במחשב' '' "$($pr.Count): $((@($pr | ForEach-Object { $_.Name })) -join ', ')"
