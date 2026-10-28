param([hashtable]$P = @{})
$jobs = @{}
foreach ($j in Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue) { $n = ($j.Name -split ',')[0]; $jobs[$n] = 1 + [int]$jobs[$n] }
$err = @{ 0 = ''; 1 = 'אחר'; 2 = 'לא ידוע'; 3 = 'נייר נתקע'; 4 = 'אין נייר'; 5 = 'טונר נמוך'; 6 = 'אין טונר'; 7 = 'דלת פתוחה'; 8 = 'נייר תקוע'; 9 = 'לא מחובר'; 10 = 'דרושה התערבות'; 11 = 'מגש פלט מלא' }
$printers = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Sort-Object Name)
if ($printers.Count -eq 0) { [pscustomobject]@{ 'מדפסת' = 'אין מדפסות מוגדרות'; 'מצב' = '' }; return }
foreach ($item in $printers) {
    $q = [int]$jobs[$item.Name]
    $st = 'תקין'; $d = $err[[int]$item.DetectedErrorState]
    if ($item.WorkOffline) { $st = 'אזהרה'; $d = 'במצב Offline' }
    elseif ([int]$item.DetectedErrorState -gt 2) { $st = 'אזהרה' }
    if ($q -gt 5) { $st = 'אזהרה'; $d = "$d · תור עמוס".Trim(' ·') }
    [pscustomobject]@{ 'מדפסת' = $item.Name; 'ברירת מחדל' = $(if ($item.Default) { 'כן' } else { '' }); 'פורט' = $item.PortName; 'דרייבר' = $item.DriverName; 'משותפת' = $(if ($item.Shared) { $item.ShareName } else { '' }); 'עבודות בתור' = $q; 'מצב' = $st; 'פרטים' = $d }
}
