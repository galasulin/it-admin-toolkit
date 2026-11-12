param([hashtable]$P = @{})
$root = $P._Root; $cred = $P._Cred
$cfg = Get-Content (Join-Path $root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$src = "$($P.Computers)".Trim()
$names = @()
if (-not $src -or $src -eq 'AD') {
    $a = @{ ComputerName = $cfg.DomainController; ErrorAction = 'Stop'; ScriptBlock = {
        Import-Module ActiveDirectory
        Get-ADComputer -Filter 'Enabled -eq $true' -Properties LastLogonDate | Where-Object { $_.LastLogonDate -gt (Get-Date).AddDays(-30) } | ForEach-Object { $_.Name }
    } }
    if ($cred) { $a.Credential = $cred }
    $names = @(Invoke-Command @a)
} else { $names = @($src -split '[,; ]+' | Where-Object { $_ }) }
$sb = {
    $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem; $b = Get-CimInstance Win32_BIOS
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1; $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $ver = $cv.DisplayVersion; if (-not $ver) { $ver = $cv.ReleaseId }
    $disk = 'לא ידוע'; try { $pd = Get-PhysicalDisk -ErrorAction Stop | Select-Object -First 1; $disk = "$($pd.MediaType)" } catch {}
    [pscustomobject]@{
        'מחשב' = $env:COMPUTERNAME; 'משתמש' = $cs.UserName; 'יצרן' = $cs.Manufacturer; 'דגם' = $cs.Model; 'סריאלי' = $b.SerialNumber
        'מעבד' = "$($cpu.Name)".Trim(); 'זיכרון GB' = [math]::Round($cs.TotalPhysicalMemory / 1GB); 'סוג דיסק' = $disk
        'C: גודל GB' = [math]::Round($c.Size / 1GB); 'C: פנוי GB' = [math]::Round($c.FreeSpace / 1GB, 1)
        'מערכת' = $os.Caption -replace '[\u200e\u200f]', '' -replace 'Microsoft ', ''; 'גרסה' = $ver; 'Build' = "$($os.BuildNumber).$($cv.UBR)"
        'הפעלה אחרונה' = $os.LastBootUpTime.ToString('dd/MM/yyyy'); 'מצב' = 'תקין'
    }
}
$a = @{ ComputerName = $names; ScriptBlock = $sb; ThrottleLimit = 24; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'errs' }
if ($cred) { $a.Credential = $cred }
$res = @(Invoke-Command @a)
$res
$ok = @($res | ForEach-Object { "$($_.PSComputerName)".ToLower() })
foreach ($n in $names) {
    if ($ok -notcontains $n.ToLower()) {
        [pscustomobject]@{ 'מחשב' = $n; 'משתמש' = ''; 'יצרן' = ''; 'דגם' = ''; 'סריאלי' = ''; 'מעבד' = ''; 'זיכרון GB' = ''; 'סוג דיסק' = ''; 'C: גודל GB' = ''; 'C: פנוי GB' = ''; 'מערכת' = ''; 'גרסה' = ''; 'Build' = ''; 'הפעלה אחרונה' = ''; 'מצב' = 'אין חיבור' }
    }
}
