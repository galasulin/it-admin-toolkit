param([hashtable]$P = @{})
$hosts = @("$($P.Hosts)" -split '[,; ]+' | Where-Object { $_ })
if ($hosts.Count -eq 0) { $hosts = @('localhost') }
$ports = @("$($P.Ports)" -split '[,; ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
$names = @{ 3389 = 'RDP'; 445 = 'SMB (שיתופים)'; 5985 = 'WinRM'; 5986 = 'WinRM HTTPS'; 1433 = 'SQL Server'; 80 = 'HTTP'; 443 = 'HTTPS'; 53 = 'DNS'; 389 = 'LDAP'; 636 = 'LDAPS'; 88 = 'Kerberos'; 135 = 'RPC'; 22 = 'SSH'; 21 = 'FTP'; 25 = 'SMTP'; 587 = 'SMTP Submission' }
function Emit($h, $c, $s, $d) { [pscustomobject]@{ 'יעד' = $h; 'בדיקה' = $c; 'מצב' = $s; 'פרטים' = "$d" } }
foreach ($h in $hosts) {
    try { $ips = @([System.Net.Dns]::GetHostAddresses($h) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.IPAddressToString }); Emit $h 'DNS' 'תקין' ($ips -join ', ') }
    catch { Emit $h 'DNS' 'קריטי' 'השם לא מתורגם לכתובת'; continue }
    $ping = New-Object System.Net.NetworkInformation.Ping
    $ok = 0; $ms = @()
    for ($i = 0; $i -lt 3; $i++) { try { $r = $ping.Send($h, 1000); if ($r.Status -eq 'Success') { $ok++; $ms += $r.RoundtripTime } } catch {} }
    if ($ok -gt 0) { Emit $h 'Ping' $(if ($ok -eq 3) { 'תקין' } else { 'אזהרה' }) ("{0}/3 · ממוצע {1} ms" -f $ok, [math]::Round(($ms | Measure-Object -Average).Average)) }
    else { Emit $h 'Ping' 'לבדוק' 'אין תשובה. ייתכן שחומת האש חוסמת ICMP, וזה לא בהכרח תקלה.' }
    foreach ($port in $ports) {
        $c = New-Object System.Net.Sockets.TcpClient
        $open = $false
        try { $a = $c.BeginConnect($h, $port, $null, $null); if ($a.AsyncWaitHandle.WaitOne(1500)) { $c.EndConnect($a); $open = $true } } catch {} finally { $c.Close() }
        $n = $names[$port]; if (-not $n) { $n = '' }
        Emit $h "פורט $port $n".Trim() $(if ($open) { 'תקין' } else { 'אזהרה' }) $(if ($open) { 'פתוח' } else { 'סגור / חסום' })
    }
}
