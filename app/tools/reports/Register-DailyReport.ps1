param([hashtable]$P = @{})
# יוצר משימה מתוזמנת במחשב הזה שמריצה את צ'קליסט הבוקר כל יום ושומרת דוח HTML בתיקיית reports
$root = $P._Root
$time = "$($P.Time)".Trim(); if ($time -notmatch '^\d{1,2}:\d{2}$') { $time = '07:30' }
$script = Join-Path $root 'Run-DailyReport.ps1'
$name = 'IT-Toolkit Daily Report'
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday, Monday, Tuesday, Wednesday, Thursday -At $time
$set = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$usr = "$env:USERDOMAIN\$env:USERNAME"
# רץ כמשתמש שלך רק כשאתה מחובר (Interactive), כך שהסיסמה שלך לא נשמרת במשימה
$pr = New-ScheduledTaskPrincipal -UserId $usr -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $name -Action $act -Trigger $trg -Settings $set -Principal $pr -Force | Out-Null
[pscustomobject]@{ 'פעולה' = 'משימה מתוזמנת'; 'מצב' = 'בוצע'; 'פרטים' = "$name · א'-ה' בשעה $time · כמשתמש $usr · הדוח נשמר ב-$root\reports\daily-YYYYMMDD.html ונפתח אוטומטית" }
