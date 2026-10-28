param([hashtable]$P = @{})
$warn = 20; if ($P.DiskWarn) { $warn = [int]$P.DiskWarn }
$crit = 10; if ($P.DiskCrit) { $crit = [int]$P.DiskCrit }
foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
    if (-not $d.Size) { continue }
    $pct = [math]::Round($d.FreeSpace / $d.Size * 100, 1)
    $st = 'תקין'; if ($pct -lt $crit) { $st = 'קריטי' } elseif ($pct -lt $warn) { $st = 'אזהרה' }
    [pscustomobject]@{
        'סוג' = 'כונן'; 'שם' = "$($d.DeviceID) $($d.VolumeName)".Trim()
        'גודל GB' = [math]::Round($d.Size / 1GB, 1); 'פנוי GB' = [math]::Round($d.FreeSpace / 1GB, 1); 'פנוי %' = $pct
        'מצב' = $st; 'פרטים' = $d.FileSystem
    }
}
try {
    foreach ($pd in Get-PhysicalDisk -ErrorAction Stop) {
        $st = 'תקין'
        if ("$($pd.HealthStatus)" -eq 'Warning') { $st = 'אזהרה' } elseif ("$($pd.HealthStatus)" -ne 'Healthy') { $st = 'קריטי' }
        $extra = ''
        try {
            $rc = $pd | Get-StorageReliabilityCounter -ErrorAction Stop
            $extra = "טמפ' $($rc.Temperature)°C · שגיאות קריאה $($rc.ReadErrorsTotal) · בלאי $($rc.Wear)%"
        } catch {}
        [pscustomobject]@{
            'סוג' = 'דיסק פיזי'; 'שם' = $pd.FriendlyName
            'גודל GB' = [math]::Round($pd.Size / 1GB, 1); 'פנוי GB' = ''; 'פנוי %' = ''
            'מצב' = $st; 'פרטים' = ("$($pd.MediaType) · $($pd.BusType) · $($pd.HealthStatus) $extra").Trim()
        }
    }
} catch {}
