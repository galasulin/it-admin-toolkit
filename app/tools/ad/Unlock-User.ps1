param([hashtable]$P = @{})
Import-Module ActiveDirectory -ErrorAction Stop
$sam = "$($P.User)".Trim()
$u = Get-ADUser -Identity $sam -Properties LockedOut, DisplayName -ErrorAction Stop
if (-not $u.LockedOut) { [pscustomobject]@{ 'משתמש' = "$sam ($($u.DisplayName))"; 'מצב' = 'תקין'; 'פרטים' = 'החשבון לא היה נעול' }; return }
Unlock-ADAccount -Identity $sam -ErrorAction Stop
[pscustomobject]@{ 'משתמש' = "$sam ($($u.DisplayName))"; 'מצב' = 'בוצע'; 'פרטים' = 'הנעילה שוחררה. אם החשבון ננעל שוב, כנראה יש מכשיר עם סיסמה ישנה (טלפון, מיפוי כונן או משימה מתוזמנת).' }
