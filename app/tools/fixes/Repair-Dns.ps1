param([hashtable]$P = @{})
function Step($n, [scriptblock]$b) {
    try { $o = & $b; [pscustomobject]@{ 'שלב' = $n; 'מצב' = 'בוצע'; 'פרטים' = "$o".Trim() } }
    catch { [pscustomobject]@{ 'שלב' = $n; 'מצב' = 'נכשל'; 'פרטים' = $_.Exception.Message } }
}
Step 'ניקוי DNS Cache' { Clear-DnsClientCache; 'OK' }
Step 'רישום מחדש ב-DNS' { ipconfig.exe /registerdns | Out-Null; 'נשלחה בקשת רישום. עשוי לקחת עד 15 דקות.' }
Step 'שרתי DNS מוגדרים' { (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | ForEach-Object { "$($_.InterfaceAlias): $($_.ServerAddresses -join ', ')" }) -join ' | ' }
