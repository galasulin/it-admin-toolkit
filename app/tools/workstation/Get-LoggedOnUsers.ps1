param([hashtable]$P = @{})
$lines = @(quser.exe 2>$null)
if ($lines.Count -le 1) {
    $u = (Get-CimInstance Win32_ComputerSystem).UserName
    [pscustomobject]@{ 'משתמש' = "$u"; 'סשן' = 'console'; 'ID' = ''; 'מצב' = ''; 'זמן סרק' = ''; 'כניסה' = ''; 'הערה' = 'quser לא החזיר נתונים' }
    return
}
foreach ($l in $lines | Select-Object -Skip 1) {
    $t = $l.TrimStart(' ', '>')
    $parts = $t -split '\s{2,}'
    if ($parts.Count -eq 6) {
        [pscustomobject]@{ 'משתמש' = $parts[0]; 'סשן' = $parts[1]; 'ID' = $parts[2]; 'מצב' = $parts[3]; 'זמן סרק' = $parts[4]; 'כניסה' = $parts[5]; 'הערה' = '' }
    } elseif ($parts.Count -eq 5) {
        [pscustomobject]@{ 'משתמש' = $parts[0]; 'סשן' = ''; 'ID' = $parts[1]; 'מצב' = $parts[2]; 'זמן סרק' = $parts[3]; 'כניסה' = $parts[4]; 'הערה' = 'מנותק (Disconnected)' }
    } else {
        [pscustomobject]@{ 'משתמש' = $t; 'סשן' = ''; 'ID' = ''; 'מצב' = ''; 'זמן סרק' = ''; 'כניסה' = ''; 'הערה' = '' }
    }
}
