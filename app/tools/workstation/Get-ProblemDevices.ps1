param([hashtable]$P = @{})
$bad = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 })
$codes = @{ 1 = 'לא מוגדר נכון'; 10 = 'לא מצליח להתחיל'; 18 = 'צריך להתקין מחדש דרייבר'; 22 = 'מושבת'; 24 = 'לא קיים / לא מחובר'; 28 = 'דרייבר לא מותקן'; 31 = 'לא עובד כראוי'; 43 = 'Windows עצר את ההתקן'; 45 = 'לא מחובר כרגע' }
if ($bad.Count -eq 0) { [pscustomobject]@{ 'התקן' = 'כל ההתקנים תקינים'; 'קוד' = ''; 'מצב' = 'תקין'; 'משמעות' = ''; 'מזהה' = '' }; return }
foreach ($d in $bad) {
    $c = [int]$d.ConfigManagerErrorCode
    $st = 'אזהרה'; if ($c -in 22, 45, 24) { $st = 'לבדוק' }
    $m = $codes[$c]; if (-not $m) { $m = 'שגיאה' }
    [pscustomobject]@{ 'התקן' = "$($d.Name)"; 'קוד' = $c; 'מצב' = $st; 'משמעות' = $m; 'מזהה' = $d.PNPDeviceID }
}
