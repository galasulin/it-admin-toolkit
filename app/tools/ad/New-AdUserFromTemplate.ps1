param([hashtable]$P = @{})
Import-Module ActiveDirectory -ErrorAction Stop
$first = "$($P.First)".Trim(); $last = "$($P.Last)".Trim(); $sam = "$($P.Sam)".Trim(); $tpl = "$($P.Template)".Trim()
if (-not ($first -and $sam -and $tpl)) { throw 'חסרים פרטים: שם פרטי, שם משתמש ומשתמש תבנית' }
if (Get-ADUser -Filter "SamAccountName -eq '$($sam -replace "'", "''")'" -ErrorAction SilentlyContinue) { throw "כבר קיים משתמש בשם $sam" }
$t = Get-ADUser -Identity $tpl -Properties MemberOf, Department, Company, Office, StreetAddress, City, Title -ErrorAction Stop
$ou = ($t.DistinguishedName -split ',', 2)[1]
$upnSuffix = ($t.UserPrincipalName -split '@')[1]
if (-not $upnSuffix) { $upnSuffix = (Get-ADDomain).DNSRoot }
$name = ("$first $last").Trim()
$up = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray(); $lo = 'abcdefghijkmnpqrstuvwxyz'.ToCharArray(); $dg = '23456789'.ToCharArray()
$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
function Pick($set) { $b = New-Object byte[] 4; $rng.GetBytes($b); $set[[BitConverter]::ToUInt32($b, 0) % $set.Length] }
$newPw = -join @((Pick $up), (Pick $up), (Pick $lo), (Pick $lo), (Pick $lo), (Pick $lo), (Pick $dg), (Pick $dg), (Pick $dg), (Pick $dg), '!', (Pick $lo))
$args2 = @{
    Name = $name; GivenName = $first; SamAccountName = $sam; UserPrincipalName = "$sam@$upnSuffix"; DisplayName = $name
    Path = $ou; Enabled = $true; ChangePasswordAtLogon = $true
    AccountPassword = (ConvertTo-SecureString $newPw -AsPlainText -Force)
}
if ($last) { $args2.Surname = $last }
foreach ($f in 'Department', 'Company', 'Office', 'StreetAddress', 'City', 'Title') { if ($t.$f) { $args2[$f] = $t.$f } }
New-ADUser @args2 -ErrorAction Stop
[pscustomobject]@{ 'פריט' = 'משתמש חדש'; 'ערך' = "$sam · $name"; 'מצב' = 'בוצע' }
[pscustomobject]@{ 'פריט' = 'מיקום (OU)'; 'ערך' = $ou; 'מצב' = '' }
[pscustomobject]@{ 'פריט' = 'סיסמה זמנית'; 'ערך' = $newPw; 'מצב' = 'חובה להחליף בכניסה הראשונה' }
foreach ($g in @($t.MemberOf)) {
    try { Add-ADGroupMember -Identity $g -Members $sam -ErrorAction Stop; [pscustomobject]@{ 'פריט' = 'נוסף לקבוצה'; 'ערך' = (($g -split ',')[0] -replace '^CN='); 'מצב' = 'בוצע' } }
    catch { [pscustomobject]@{ 'פריט' = 'נוסף לקבוצה'; 'ערך' = (($g -split ',')[0] -replace '^CN='); 'מצב' = "נכשל: $($_.Exception.Message)" } }
}
[pscustomobject]@{ 'פריט' = 'לא לשכוח'; 'ערך' = 'רישיון M365 (אחרי סנכרון AD Connect) · משתמש במערכות החיצוניות · שלוחה במרכזייה'; 'מצב' = 'לבדוק' }
