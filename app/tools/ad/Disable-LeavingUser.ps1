param([hashtable]$P = @{})
Import-Module ActiveDirectory -ErrorAction Stop
$sam = "$($P.User)".Trim()
$u = Get-ADUser -Identity $sam -Properties DisplayName, Description, MemberOf, Enabled -ErrorAction Stop
$by = "$env:USERDOMAIN\$env:USERNAME"
$desc = "הושבת $(Get-Date -Format 'dd/MM/yyyy') ע""י $by (IT-Toolkit)"
if ($u.Description) { $desc = "$desc · היה: $($u.Description)" }
if ($desc.Length -gt 1000) { $desc = $desc.Substring(0, 1000) }
if ($u.Enabled) { Disable-ADAccount -Identity $sam -ErrorAction Stop; $r1 = 'בוצע' } else { $r1 = 'כבר היה מושבת' }
Set-ADUser -Identity $sam -Description $desc -ErrorAction Stop
[pscustomobject]@{ 'פריט' = 'השבתת חשבון'; 'ערך' = "$sam ($($u.DisplayName))"; 'מצב' = $r1 }
[pscustomobject]@{ 'פריט' = 'תיאור'; 'ערך' = $desc; 'מצב' = 'בוצע' }
foreach ($g in @($u.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace '^CN=' }) | Sort-Object) {
    [pscustomobject]@{ 'פריט' = 'חבר בקבוצה (לא הוסר)'; 'ערך' = $g; 'מצב' = '' }
}
[pscustomobject]@{ 'פריט' = 'לא לשכוח'; 'ערך' = 'רישיון M365 · העברת מייל או Shared Mailbox · ציוד ומחשב · VPN · מערכות חיצוניות (CRM, מרכזייה)'; 'מצב' = 'לבדוק' }
