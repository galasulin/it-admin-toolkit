param([hashtable]$P = @{})
# רץ על ה-DC: ניסיונות כניסה שנכשלו (Kerberos 4771, NTLM 4776, נעילות 4740)
$hours = 24; if ($P.Hours) { $hours = [int]$P.Hours }
$since = (Get-Date).AddHours(-$hours)
$ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4771, 4776, 4740, 4625; StartTime = $since } -MaxEvents 5000 -ErrorAction SilentlyContinue)
$rows = foreach ($e in $ev) {
    $x = [xml]$e.ToXml(); $d = @{}
    foreach ($n in $x.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
    if ($e.Id -eq 4776 -and $d.Status -eq '0x0') { continue }
    $user = $d.TargetUserName; if (-not $user) { $user = $d.TargetUser }
    $src = $d.IpAddress; if (-not $src -or $src -eq '-') { $src = $d.Workstation }; if (-not $src) { $src = $d.TargetDomainName }
    [pscustomobject]@{ U = $user; S = ("$src" -replace '^::ffff:', ''); Id = $e.Id; T = $e.TimeCreated }
}
$kind = @{ 4771 = 'Kerberos'; 4776 = 'NTLM'; 4740 = 'נעילה'; 4625 = 'כניסה נכשלה' }
if (-not $rows) { [pscustomobject]@{ 'משתמש' = ''; 'מקור' = ''; 'סוג' = ''; 'כמות' = 0; 'אחרון' = ''; 'מצב' = 'תקין' }; return }
$rows | Group-Object U, S, Id | Sort-Object Count -Descending | Select-Object -First 60 | ForEach-Object {
    $f = $_.Group[0]
    $st = 'תקין'; if ($f.Id -eq 4740 -or $_.Count -ge 20) { $st = 'קריטי' } elseif ($_.Count -ge 5) { $st = 'אזהרה' }
    [pscustomobject]@{ 'משתמש' = $f.U; 'מקור' = $f.S; 'סוג' = $kind[[int]$f.Id]; 'כמות' = $_.Count; 'אחרון' = ($_.Group | Sort-Object T -Descending | Select-Object -First 1).T.ToString('dd/MM HH:mm'); 'מצב' = $st }
}
