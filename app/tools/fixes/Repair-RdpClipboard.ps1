param([hashtable]$P = @{})
function Emit($n, $st, $d) { [pscustomobject]@{ 'שלב' = $n; 'מצב' = $st; 'פרטים' = "$d" } }
$k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
try {
    $old = (Get-ItemProperty $k -Name fDisableClip -ErrorAction SilentlyContinue).fDisableClip
    Set-ItemProperty -Path $k -Name fDisableClip -Value 0 -Type DWord -Force
    Emit 'fDisableClip ב-RDP-Tcp' 'בוצע' "היה: $old · עכשיו: 0"
} catch { Emit 'fDisableClip ב-RDP-Tcp' 'נכשל' $_.Exception.Message }
$pk = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
$pv = (Get-ItemProperty $pk -Name fDisableClip -ErrorAction SilentlyContinue).fDisableClip
if ($pv -eq 1) { Emit 'מדיניות GPO' 'קריטי' 'יש GPO שחוסם העתקה (fDisableClip=1). צריך לתקן ב-Group Policy, אחרת השינוי יחזור.' }
elseif ($null -ne $pv) { Emit 'מדיניות GPO' 'תקין' "fDisableClip=$pv" }
else { Emit 'מדיניות GPO' 'תקין' 'אין מדיניות שחוסמת' }
$rc = @(Get-Process rdpclip -ErrorAction SilentlyContinue)
Emit 'rdpclip' '' "$($rc.Count) תהליכים פעילים"
Emit 'הבא בתור' '' 'המשתמש מבצע Sign Out מלא (לא Disconnect) ומתחבר מחדש.'
