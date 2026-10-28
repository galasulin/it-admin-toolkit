param([hashtable]$P = @{})
Import-Module ActiveDirectory -ErrorAction Stop
$q = ("$($P.User)".Trim()) -replace "'", "''"
if (-not $q) { throw 'לא הוזן שם משתמש' }
$props = 'DisplayName', 'Enabled', 'LockedOut', 'LastLogonDate', 'PasswordLastSet', 'PasswordExpired', 'PasswordNeverExpires', 'MemberOf', 'Title', 'Department', 'mail', 'Description', 'whenCreated', 'badPwdCount', 'AccountExpirationDate'
$users = @(Get-ADUser -Filter "SamAccountName -like '*$q*' -or Name -like '*$q*' -or DisplayName -like '*$q*' -or mail -like '*$q*'" -Properties $props -ResultSetSize 50)
if ($users.Count -eq 0) { [pscustomobject]@{ 'שם משתמש' = ''; 'שם' = "לא נמצא משתמש שמתאים ל-$q"; 'מצב' = '' }; return }
foreach ($u in $users) {
    $st = 'תקין'
    if (-not $u.Enabled) { $st = 'מושבת' } elseif ($u.LockedOut) { $st = 'אזהרה' } elseif ($u.PasswordExpired) { $st = 'אזהרה' }
    $grp = @($u.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace '^CN=' }) | Sort-Object
    $ou = ($u.DistinguishedName -split ',', 2)[1]
    [pscustomobject]@{
        'שם משתמש' = $u.SamAccountName; 'שם' = $u.DisplayName; 'מצב' = $st
        'פעיל' = $(if ($u.Enabled) { 'כן' } else { 'לא' }); 'נעול' = $(if ($u.LockedOut) { 'כן' } else { 'לא' })
        'כניסה אחרונה' = $(if ($u.LastLogonDate) { $u.LastLogonDate.ToString('dd/MM/yyyy HH:mm') } else { 'אף פעם' })
        'סיסמה שונתה' = $(if ($u.PasswordLastSet) { $u.PasswordLastSet.ToString('dd/MM/yyyy') } else { 'חייב להחליף' })
        'סיסמה לא פגה' = $(if ($u.PasswordNeverExpires) { 'כן' } else { 'לא' })
        'ניסיונות שגויים' = $u.badPwdCount
        'תפקיד / מחלקה' = ("$($u.Title) / $($u.Department)").Trim(' /')
        'מייל' = $u.mail; 'תיאור' = $u.Description; 'OU' = $ou
        'קבוצות' = ($grp -join ', ')
    }
}
