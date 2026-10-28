param([hashtable]$P = @{})
function Row($req, $found, [bool]$ok, $note = '') {
    $st = 'תקין'; if (-not $ok) { $st = 'קריטי' }
    [pscustomobject]@{ 'דרישה' = $req; 'נמצא' = "$found"; 'מצב' = $st; 'הערה' = $note }
}
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$ram = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
Row 'זיכרון 4GB ומעלה' "$ram GB" ($ram -ge 3.8)
$c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
$sz = [math]::Round($c.Size / 1GB)
Row 'דיסק מערכת 64GB ומעלה' "$sz GB" ($sz -ge 64)
Row 'מערכת 64 ביט' $os.OSArchitecture ($os.OSArchitecture -match '64')
$tpmTxt = 'לא נמצא'; $tpmOk = $false
try {
    $t = Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -ClassName Win32_Tpm -ErrorAction Stop
    if ($t) { $tpmTxt = "SpecVersion $($t.SpecVersion) · מופעל: $($t.IsEnabled_InitialValue)"; $tpmOk = ("$($t.SpecVersion)" -match '^2\.0') }
} catch {}
Row 'TPM 2.0' $tpmTxt $tpmOk 'אם לא נמצא, לבדוק ב-BIOS: PTT (Intel) או fTPM (AMD)'
$sb = 'לא נתמך (BIOS ישן / Legacy)'; $sbOk = $false; $uefi = $false
try { $v = Confirm-SecureBootUEFI -ErrorAction Stop; $uefi = $true; $sbOk = [bool]$v; if ($v) { $sb = 'פעיל' } else { $sb = 'כבוי' } } catch {
    if ("$_" -match 'not supported|אינו נתמך') { $sb = 'לא נתמך (Legacy BIOS)' } else { $uefi = $true; $sb = 'לא ידוע' }
}
Row 'UEFI' $(if ($uefi) { 'כן' } else { 'לא (Legacy)' }) $uefi 'מעבר מ-Legacy ל-UEFI: mbr2gpt'
Row 'Secure Boot' $sb $sbOk
[pscustomobject]@{ 'דרישה' = 'מעבר נתמך'; 'נמצא' = "$($cpu.Name)".Trim(); 'מצב' = 'לבדוק'; 'הערה' = 'Intel דור 8 ומעלה, AMD Ryzen 2000 ומעלה (לאמת ברשימת Microsoft)' }
