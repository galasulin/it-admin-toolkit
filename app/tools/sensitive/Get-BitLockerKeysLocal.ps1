param([hashtable]$P = @{})
try { $vols = @(Get-BitLockerVolume -ErrorAction Stop) } catch { [pscustomobject]@{ 'כונן' = ''; 'Key ID' = ''; 'מפתח שחזור' = "BitLocker לא זמין: $($_.Exception.Message)"; 'גובה ל-AD?' = '' }; return }
foreach ($v in $vols) {
    $rp = @($v.KeyProtector | Where-Object { "$($_.KeyProtectorType)" -eq 'RecoveryPassword' })
    if ($rp.Count -eq 0) { [pscustomobject]@{ 'כונן' = $v.MountPoint; 'Key ID' = ''; 'מפתח שחזור' = 'אין Recovery Password לכונן הזה'; 'גובה ל-AD?' = '' }; continue }
    foreach ($k in $rp) {
        [pscustomobject]@{ 'כונן' = $v.MountPoint; 'Key ID' = "$($k.KeyProtectorId)".Trim('{}'); 'מפתח שחזור' = $k.RecoveryPassword; 'גובה ל-AD?' = 'לבדוק בכלי "מפתח BitLocker מה-AD"' }
    }
}
