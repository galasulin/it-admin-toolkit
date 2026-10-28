param([hashtable]$P = @{})
function Row($k, $v, $st = '') { [pscustomobject]@{ 'בדיקה' = $k; 'ערך' = "$v"; 'מצב' = $st } }
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$ver = $cv.DisplayVersion; if (-not $ver) { $ver = $cv.ReleaseId }
$cap = (Get-CimInstance Win32_OperatingSystem).Caption -replace '[\u200e\u200f]', '' -replace '^Microsoft ', ''
Row 'גרסה' "$cap $ver (Build $($cv.CurrentBuild).$($cv.UBR))"
$hf = Get-HotFix -ErrorAction SilentlyContinue | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
if ($hf) {
    $age = [int]((Get-Date) - $hf.InstalledOn).TotalDays
    $st = 'תקין'; if ($age -gt 60) { $st = 'קריטי' } elseif ($age -gt 35) { $st = 'אזהרה' }
    Row 'עדכון אחרון שהותקן' "$($hf.HotFixID) · $($hf.InstalledOn.ToString('dd/MM/yyyy')) · לפני $age ימים" $st
} else { Row 'עדכון אחרון שהותקן' 'לא נמצא' 'אזהרה' }
foreach ($s in 'wuauserv', 'bits', 'cryptsvc', 'UsoSvc') {
    $svc = Get-Service $s -ErrorAction SilentlyContinue
    if ($svc) {
        $st = 'תקין'; if ($svc.StartType -eq 'Disabled') { $st = 'קריטי' }
        Row "שירות $s" "$($svc.Status) · $($svc.StartType)" $st
    }
}
$pol = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
if ($pol.WUServer) { Row 'שרת WSUS' $pol.WUServer 'לבדוק' } else { Row 'שרת WSUS' 'אין (עדכונים ישירות מ-Microsoft)' }
$au = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
if ($au.NoAutoUpdate -eq 1) { Row 'מדיניות' 'עדכונים אוטומטיים כבויים ב-GPO' 'אזהרה' }
if ($pol.TargetReleaseVersionInfo) { Row 'גרסת יעד נעולה (GPO)' $pol.TargetReleaseVersionInfo 'לבדוק' }
try {
    $sess = New-Object -ComObject Microsoft.Update.Session
    $res = $sess.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    $n = $res.Updates.Count
    $st = 'תקין'; if ($n -gt 0) { $st = 'אזהרה' }
    $titles = @(); for ($i = 0; $i -lt [math]::Min($n, 8); $i++) { $titles += $res.Updates.Item($i).Title }
    Row 'עדכונים ממתינים' "$n · $($titles -join ' | ')" $st
} catch { Row 'עדכונים ממתינים' "החיפוש נכשל: $($_.Exception.Message)" 'אזהרה' }
