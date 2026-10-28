param([hashtable]$P = @{})
function Emit($n, $st, $d) { [pscustomobject]@{ 'שלב' = $n; 'מצב' = $st; 'פרטים' = "$d" } }
try { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0 -Type DWord; Emit 'הפעלת RDP' 'בוצע' '' } catch { Emit 'הפעלת RDP' 'נכשל' $_.Exception.Message }
try {
    # שם הקבוצה בעברית משתנה, לכן משתמשים במזהה הקבוע שלה
    Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction Stop
    Emit 'חומת אש' 'בוצע' 'קבוצת Remote Desktop הופעלה'
} catch { Emit 'חומת אש' 'נכשל' $_.Exception.Message }
$nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
if ($nla -eq 1) { Emit 'NLA' 'תקין' 'פעיל' } else { Emit 'NLA' 'אזהרה' 'כבוי. מומלץ להפעיל (UserAuthentication=1)' }
