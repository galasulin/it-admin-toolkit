param([hashtable]$P = @{})
function Emit($prod, $key, $kind, $st) { [pscustomobject]@{ 'מוצר' = $prod; 'מפתח' = $key; 'מקור' = $kind; 'מצב רישוי' = $st } }
$oem = (Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue).OA3xOriginalProductKey
if ($oem) { Emit 'Windows (מפתח יצרן מוטמע ב-BIOS)' $oem 'BIOS / OA3' '' }

# פענוח DigitalProductId מהרישום. במחשבים עם רישיון דיגיטלי זה יהיה מפתח גנרי.
function Decode-Key([byte[]]$id) {
    if (-not $id -or $id.Length -lt 67) { return $null }
    $k = $id[52..66]; $chars = 'BCDFGHJKMPQRTVWXY2346789'; $isWin8 = ([math]::Floor($k[14] / 6)) -band 1
    $k[14] = ($k[14] -band 0xF7) -bor (($isWin8 -band 2) * 4)
    $out = ''
    for ($i = 24; $i -ge 0; $i--) {
        $cur = 0
        for ($j = 14; $j -ge 0; $j--) { $cur = $cur * 256 -bxor $k[$j]; $k[$j] = [math]::Floor($cur / 24); $cur = $cur % 24 }
        $out = $chars[$cur] + $out; $last = $cur
    }
    if ($isWin8 -eq 1) { $out = $out.Substring(1, $last) + 'N' + $out.Substring($last + 1) }
    return ($out -replace '(.{5})(?!$)', '$1-')
}
$dp = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DigitalProductId
$dec = Decode-Key $dp
if ($dec) { Emit 'Windows (מותקן)' $dec 'רישום (DigitalProductId)' 'אם המפתח מתחיל ב-VK7JG או ב-W269N זה רישיון דיגיטלי או KMS' }

$stat = @{ 0 = 'לא מורשה'; 1 = 'מורשה'; 2 = 'תקופת חסד'; 3 = 'חסד מורחב'; 4 = 'לא מקורי'; 5 = 'התראה'; 6 = 'חסד מורחב' }
foreach ($l in Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue) {
    Emit $l.Name "XXXXX-XXXXX-XXXXX-XXXXX-$($l.PartialProductKey)" 'חמש תווים אחרונים (Windows / Office)' $stat[[int]$l.LicenseStatus]
}
