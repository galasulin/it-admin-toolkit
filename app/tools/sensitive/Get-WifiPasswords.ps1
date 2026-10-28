param([hashtable]$P = @{})
# ייצוא הפרופילים ל-XML (לא תלוי בשפת Windows), קריאה ומחיקה מיידית של הקבצים הזמניים
$tmp = Join-Path $env:TEMP ("wlan-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    netsh.exe wlan export profile key=clear folder="$tmp" | Out-Null
    $files = @(Get-ChildItem $tmp -Filter *.xml -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { [pscustomobject]@{ 'רשת' = 'אין פרופילי WiFi שמורים (או שאין כרטיס אלחוטי)'; 'סיסמה' = ''; 'אבטחה' = ''; 'התחברות אוטומטית' = '' }; return }
    foreach ($f in $files) {
        [xml]$x = Get-Content $f.FullName -Raw
        $w = $x.WLANProfile
        [pscustomobject]@{
            'רשת' = $w.SSIDConfig.SSID.name
            'סיסמה' = "$($w.MSM.security.sharedKey.keyMaterial)"
            'אבטחה' = "$($w.MSM.security.authEncryption.authentication)"
            'התחברות אוטומטית' = "$($w.connectionMode)"
        }
    }
} finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
