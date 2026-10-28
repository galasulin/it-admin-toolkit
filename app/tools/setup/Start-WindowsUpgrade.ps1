param([hashtable]$P = @{})
# מוריד את כלי השדרוג הרשמי של Microsoft, מוודא חתימה דיגיטלית, ומריץ אותו כמשימה מתוזמנת של SYSTEM
# (כדי שלא ייעצר כשהחיבור מרחוק נסגר). השדרוג שומר קבצים ותוכנות. המחשב יאותחל בסוף, בדרך כלל אחרי 1-2 שעות.
$target = "$($P.Target)".Trim()
$dir = 'C:\ProgramData\IT-Toolkit\upgrade'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
function Emit($n, $s, $d) { [pscustomobject]@{ 'שלב' = $n; 'מצב' = $s; 'פרטים' = "$d" } }
if ($target -eq '11') {
    $url = 'https://go.microsoft.com/fwlink/?linkid=2171764'; $exe = Join-Path $dir 'Windows11InstallationAssistant.exe'
    $args2 = '/QuietInstall /SkipEULA /Auto Upgrade /NoRestartUI /CopyLogs C:\ProgramData\IT-Toolkit\upgrade\logs'
} else {
    $url = 'https://go.microsoft.com/fwlink/?LinkID=799445'; $exe = Join-Path $dir 'Windows10UpdateAssistant.exe'
    $args2 = '/quietinstall /skipeula /auto upgrade /copylogs C:\ProgramData\IT-Toolkit\upgrade\logs'
}
$free = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 1)
if ($free -lt 20) { Emit 'מקום בדיסק' 'קריטי' "רק $free GB פנויים, וצריך לפחות 20. להריץ קודם ניקוי."; return }
Emit 'מקום בדיסק' 'תקין' "$free GB פנויים"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { (New-Object System.Net.WebClient).DownloadFile($url, $exe); Emit 'הורדה' 'בוצע' $exe } catch { Emit 'הורדה' 'נכשל' $_.Exception.Message; return }
$sig = Get-AuthenticodeSignature $exe
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { Emit 'חתימה דיגיטלית' 'קריטי' "החתימה לא של Microsoft ($($sig.Status)). הקובץ לא הורץ."; Remove-Item $exe -Force; return }
Emit 'חתימה דיגיטלית' 'תקין' 'Microsoft Corporation · תקינה'
$name = 'IT-Toolkit Windows Upgrade'
Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
$act = New-ScheduledTaskAction -Execute $exe -Argument $args2
$pr = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName $name -Action $act -Principal $pr -Force | Out-Null
Start-ScheduledTask -TaskName $name
Emit 'הפעלה' 'בוצע' "השדרוג רץ ברקע (משימה: $name). המחשב יאותחל לבד בסוף. לוגים: $dir\logs"
Emit 'מעקב' '' 'להריץ "מידע מערכת" אחרי שעתיים ולבדוק את ה-Build. ב-22H2: 19045.x. ב-Windows 11: 226xx/261xx.'
