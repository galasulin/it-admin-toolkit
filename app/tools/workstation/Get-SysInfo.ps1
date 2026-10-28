param([hashtable]$P = @{})
$os   = Get-CimInstance Win32_OperatingSystem
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$ver  = $cv.DisplayVersion; if (-not $ver) { $ver = $cv.ReleaseId }
$up   = (Get-Date) - $os.LastBootUpTime
$rows = [ordered]@{
    'שם מחשב'          = $env:COMPUTERNAME
    'מערכת הפעלה'      = ($os.Caption -replace '[\u200e\u200f]', '')
    'גרסה'             = $ver
    'Build'            = "$($os.BuildNumber).$($cv.UBR)"
    'ארכיטקטורה'       = $os.OSArchitecture
    'יצרן'             = $cs.Manufacturer
    'דגם'              = $cs.Model
    'מספר סריאלי'      = $bios.SerialNumber
    'BIOS'             = "$($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate))"
    'מעבד'             = "$($cpu.Name)".Trim()
    'ליבות / Threads'  = "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"
    'זיכרון (GB)'      = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    'זיכרון פנוי (GB)' = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    'דומיין'           = $cs.Domain
    'משתמש מחובר'      = $cs.UserName
    'הפעלה אחרונה'     = $os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm')
    'זמן פעילות'       = ('{0} ימים, {1} שעות' -f $up.Days, $up.Hours)
    'תאריך התקנה'      = $os.InstallDate.ToString('dd/MM/yyyy')
}
foreach ($k in $rows.Keys) { [pscustomobject]@{ 'שדה' = $k; 'ערך' = "$($rows[$k])" } }
