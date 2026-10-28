param([hashtable]$P = @{})
$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -ne 1) { [pscustomobject]@{ 'שלב' = 'נקודת שחזור'; 'מצב' = 'נכשל'; 'פרטים' = 'זה שרת. נקודות שחזור קיימות רק ב-Windows 10/11.' }; return }
try {
    Checkpoint-Computer -Description "IT-Toolkit $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction Stop
    [pscustomobject]@{ 'שלב' = 'נקודת שחזור'; 'מצב' = 'בוצע'; 'פרטים' = 'נוצרה' }
} catch {
    $m = $_.Exception.Message
    if ($m -match '1440|24') { $m = 'כבר נוצרה נקודת שחזור ב-24 השעות האחרונות (מגבלה של Windows).' }
    elseif ($m -match 'disabled|מושבת|service') { $m = "הגנת המערכת כבויה בכונן C. להפעיל: Enable-ComputerRestore -Drive C:\ · $m" }
    [pscustomobject]@{ 'שלב' = 'נקודת שחזור'; 'מצב' = 'נכשל'; 'פרטים' = $m }
}
Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Select-Object -Last 5 | ForEach-Object {
    [pscustomobject]@{ 'שלב' = 'קיימת'; 'מצב' = ''; 'פרטים' = "$($_.Description) · $($_.ConvertToDateTime($_.CreationTime))" }
}
