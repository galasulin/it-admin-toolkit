param([hashtable]$P = @{})
function Row($check, [bool]$found, $detail) {
    $st = 'תקין'; if ($found) { $st = 'אזהרה' }
    $f = 'לא'; if ($found) { $f = 'כן' }
    [pscustomobject]@{ 'בדיקה' = $check; 'נדרש אתחול' = $f; 'מצב' = $st; 'פרטים' = $detail }
}
Row 'Component Based Servicing' (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') 'התקנת עדכונים או רכיבים'
Row 'Windows Update' (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') 'עדכונים שהותקנו'
$pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
Row 'קבצים שממתינים להחלפה' ([bool]$pfro) ("{0} רשומות" -f @($pfro | Where-Object { $_ }).Count)
$a = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
$b = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
Row 'שינוי שם מחשב' ($a -ne $b) "נוכחי: $a · אחרי אתחול: $b"
try {
    $ccm = Invoke-CimMethod -Namespace root\ccm\ClientSDK -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -ErrorAction Stop
    Row 'SCCM' ([bool]$ccm.RebootPending) 'סוכן ConfigMgr'
} catch {}
$os = Get-CimInstance Win32_OperatingSystem
[pscustomobject]@{ 'בדיקה' = 'הפעלה אחרונה'; 'נדרש אתחול' = ''; 'מצב' = ''; 'פרטים' = $os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm') }
