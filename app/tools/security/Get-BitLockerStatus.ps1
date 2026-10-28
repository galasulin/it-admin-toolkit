param([hashtable]$P = @{})
try { $vols = @(Get-BitLockerVolume -ErrorAction Stop) } catch {
    [pscustomobject]@{ 'כונן' = ''; 'הצפנה' = ''; 'אחוז' = ''; 'הגנה' = ''; 'מפתחות' = ''; 'מצב' = 'לבדוק'; 'פרטים' = "BitLocker לא זמין במחשב הזה: $($_.Exception.Message)" }; return
}
foreach ($v in $vols) {
    $prot = @($v.KeyProtector | ForEach-Object { "$($_.KeyProtectorType)" }) -join ', '
    $st = 'תקין'; $note = ''
    if ("$($v.ProtectionStatus)" -ne 'On') { $st = 'אזהרה'; $note = 'הכונן לא מוגן' }
    if ($v.VolumeType -eq 'OperatingSystem' -and "$($v.ProtectionStatus)" -ne 'On') { $st = 'קריטי'; $note = 'כונן המערכת לא מוצפן או שההגנה מושהית' }
    if ("$($v.ProtectionStatus)" -eq 'On' -and $prot -notmatch 'RecoveryPassword') { $st = 'אזהרה'; $note = 'אין Recovery Password. אם יש תקלה, אין דרך לפתוח את הכונן.' }
    [pscustomobject]@{ 'כונן' = $v.MountPoint; 'הצפנה' = "$($v.VolumeStatus)"; 'אחוז' = $v.EncryptionPercentage; 'הגנה' = "$($v.ProtectionStatus)"; 'מפתחות' = $prot; 'מצב' = $st; 'פרטים' = $note }
}
