param([hashtable]$P = @{})
$t = "$($P.Target)".Trim()
function Emit($c, $s, $d) { [pscustomobject]@{ 'בדיקה' = $c; 'מצב' = $s; 'פרטים' = "$d" } }
if (-not $t -or $t -in '.', 'localhost', '127.0.0.1', $env:COMPUTERNAME) { Emit 'יעד' 'תקין' 'זה המחשב הזה. אין צורך בגישה מרחוק.'; return }
$cred = $P._Cred
try { [void][System.Net.Dns]::GetHostAddresses($t); Emit 'DNS' 'תקין' "$t מתורגם" } catch { Emit 'DNS' 'קריטי' 'השם לא מתורגם. לבדוק שם או DNS.'; return }
$c = New-Object System.Net.Sockets.TcpClient; $open = $false
try { $a = $c.BeginConnect($t, 5985, $null, $null); if ($a.AsyncWaitHandle.WaitOne(2000)) { $c.EndConnect($a); $open = $true } } catch {} finally { $c.Close() }
if (-not $open) {
    Emit 'פורט 5985 (WinRM)' 'קריטי' 'סגור. אפשרויות: המחשב כבוי, חומת אש חוסמת, או ש-WinRM לא מופעל.'
    Emit 'פתרון' 'לבדוק' 'על המחשב עצמו כמנהל: Enable-PSRemoting -Force · או בכל הארגון דרך GPO: Computer Config > Policies > Admin Templates > Windows Components > WinRM Service > Allow remote server management'
    return
}
Emit 'פורט 5985 (WinRM)' 'תקין' 'פתוח'
try {
    $a = @{ ComputerName = $t; ScriptBlock = { "$env:COMPUTERNAME|$((Get-CimInstance Win32_OperatingSystem).Caption)|$($PSVersionTable.PSVersion)" }; ErrorAction = 'Stop' }
    if ($cred) { $a.Credential = $cred }
    $r = (Invoke-Command @a) -split '\|'
    Emit 'הרצה מרחוק' 'תקין' "עובד · $($r[0]) · $($r[1]) · PowerShell $($r[2])"
} catch {
    $m = $_.Exception.Message
    $hint = ''
    if ($m -match 'Access is denied|הגישה נדחתה') { $hint = 'אין הרשאה. ללחוץ "הרשאות..." ולהזין משתמש Domain Admin.' }
    elseif ($m -match 'Kerberos|TrustedHosts') { $hint = 'בעיית אימות. להשתמש בשם המלא (FQDN) של המחשב ולא ב-IP.' }
    Emit 'הרצה מרחוק' 'קריטי' "$hint $m".Trim()
}
