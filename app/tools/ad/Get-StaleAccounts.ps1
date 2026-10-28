param([hashtable]$P = @{})
Import-Module ActiveDirectory -ErrorAction Stop
$days = 90; if ($P.Days) { $days = [int]$P.Days }
$ts = New-TimeSpan -Days $days
foreach ($a in Search-ADAccount -AccountInactive -TimeSpan $ts -UsersOnly | Where-Object { $_.Enabled }) {
    [pscustomobject]@{ 'סוג' = 'משתמש'; 'שם' = $a.SamAccountName; 'כניסה אחרונה' = $(if ($a.LastLogonDate) { $a.LastLogonDate.ToString('dd/MM/yyyy') } else { 'אף פעם' }); 'מצב' = 'לבדוק'; 'OU' = ($a.DistinguishedName -split ',', 2)[1] }
}
foreach ($a in Search-ADAccount -AccountInactive -TimeSpan $ts -ComputersOnly | Where-Object { $_.Enabled }) {
    [pscustomobject]@{ 'סוג' = 'מחשב'; 'שם' = $a.Name; 'כניסה אחרונה' = $(if ($a.LastLogonDate) { $a.LastLogonDate.ToString('dd/MM/yyyy') } else { 'אף פעם' }); 'מצב' = 'לבדוק'; 'OU' = ($a.DistinguishedName -split ',', 2)[1] }
}
