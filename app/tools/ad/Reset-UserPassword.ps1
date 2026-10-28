param([hashtable]$P = @{})
Import-Module ActiveDirectory -ErrorAction Stop
$sam = "$($P.User)".Trim()
$u = Get-ADUser -Identity $sam -Properties DisplayName -ErrorAction Stop
# סיסמה אקראית קריאה: אותיות בלי תווים מבלבלים (0/O, 1/l/I), ספרות וסימן
$up = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray(); $lo = 'abcdefghijkmnpqrstuvwxyz'.ToCharArray(); $dg = '23456789'.ToCharArray(); $sy = '!@#$%*?'.ToCharArray()
$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
function Pick($set) { $b = New-Object byte[] 4; $rng.GetBytes($b); $set[[BitConverter]::ToUInt32($b, 0) % $set.Length] }
$chars = @((Pick $up), (Pick $up), (Pick $lo), (Pick $lo), (Pick $lo), (Pick $lo), (Pick $dg), (Pick $dg), (Pick $dg), (Pick $dg), (Pick $sy), (Pick $lo))
$newPw = -join $chars
Set-ADAccountPassword -Identity $sam -Reset -NewPassword (ConvertTo-SecureString $newPw -AsPlainText -Force) -ErrorAction Stop
Set-ADUser -Identity $sam -ChangePasswordAtLogon $true -ErrorAction Stop
Unlock-ADAccount -Identity $sam -ErrorAction SilentlyContinue
[pscustomobject]@{ 'משתמש' = "$sam ($($u.DisplayName))"; 'מצב' = 'בוצע'; 'סיסמה זמנית' = $newPw; 'פרטים' = 'המשתמש יחויב להחליף בכניסה הבאה. הסיסמה לא נשמרת בלוג.' }
