param([hashtable]$P = @{})
# מוסיף מדפסת משותפת מהשרת לכל המשתמשים במחשב (Global). מופיע אצל כל משתמש בכניסה הבאה.
$path = "$($P.PrinterPath)".Trim()
if ($path -notmatch '^\\\\[^\\]+\\.+') { throw 'נתיב לא תקין. דוגמה: \\PRINTSRV\Reception-HP' }
$item = Start-Process rundll32.exe -ArgumentList "printui.dll,PrintUIEntry /ga /n`"$path`"" -Wait -PassThru -WindowStyle Hidden
Restart-Service Spooler -Force -ErrorAction SilentlyContinue
[pscustomobject]@{ 'פעולה' = "הוספת $path לכל המשתמשים"; 'מצב' = $(if ($item.ExitCode -eq 0) { 'בוצע' } else { "נכשל ($($item.ExitCode))" }); 'פרטים' = 'המדפסת תופיע אצל המשתמשים אחרי כניסה מחדש. אם לא: לבדוק שהדרייבר בשרת מאושר (Point and Print).' }
