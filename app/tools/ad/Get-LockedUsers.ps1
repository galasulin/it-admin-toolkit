param([hashtable]$P = @{})
Import-Module ActiveDirectory -ErrorAction Stop
$l = @(Search-ADAccount -LockedOut -UsersOnly)
if ($l.Count -eq 0) { [pscustomobject]@{ 'שם משתמש' = ''; 'שם' = 'אין משתמשים נעולים'; 'מצב' = 'תקין'; 'נעל ב' = ''; 'ניסיונות שגויים' = '' }; return }
foreach ($a in $l) {
    $u = Get-ADUser $a.SamAccountName -Properties DisplayName, AccountLockoutTime, badPwdCount, LastBadPasswordAttempt
    [pscustomobject]@{
        'שם משתמש' = $u.SamAccountName; 'שם' = $u.DisplayName; 'מצב' = 'אזהרה'
        'נעל ב' = $(if ($u.AccountLockoutTime) { $u.AccountLockoutTime.ToString('dd/MM HH:mm') } else { '' })
        'ניסיונות שגויים' = $u.badPwdCount
    }
}
