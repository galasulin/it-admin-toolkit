param([hashtable]$P = @{})
# סריקת Ping מהירה לרשת /24 והצגת שם וכתובת MAC. ברירת מחדל: הרשת של המחשב הזה.
$net = "$($P.Subnet)".Trim()
if (-not $net) {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -notmatch '^169\.254|^127\.' } | Select-Object -First 1
    $net = ($ip.IPAddress -replace '\.\d+$', '')
}
$net = $net -replace '\.0/24$', '' -replace '\.$', ''
if ($net -notmatch '^\d+\.\d+\.\d+$') { throw "פורמט רשת לא תקין: $net (דוגמה: 192.168.1)" }
$pings = @{}
foreach ($i in 1..254) { $pg = New-Object System.Net.NetworkInformation.Ping; $pings["$net.$i"] = $pg.SendPingAsync("$net.$i", 700) }
try { [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($pings.Values)) } catch {}
$arp = @{}
foreach ($n in Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue) { $arp[$n.IPAddress] = $n.LinkLayerAddress }
foreach ($ip in $pings.Keys | Sort-Object { [version]$_ }) {
    $t = $pings[$ip]
    if ($t.Status -ne 'RanToCompletion' -or $t.Result.Status -ne 'Success') { continue }
    $name = ''; try { $name = [System.Net.Dns]::GetHostEntry($ip).HostName } catch {}
    [pscustomobject]@{ 'כתובת IP' = $ip; 'שם' = $name; 'MAC' = $arp[$ip]; 'זמן תגובה ms' = $t.Result.RoundtripTime }
}
