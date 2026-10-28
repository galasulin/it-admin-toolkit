<#
.SYNOPSIS
    Creates a Volume Shadow Copy ("Previous Versions" snapshot) of one or more volumes, and optionally
    sets the maximum shadow storage size.

.DESCRIPTION
    Uses the Win32_ShadowCopy WMI class (ClientAccessible context - the same type Windows creates for
    "Previous Versions"), so users can restore files from the Previous Versions tab.
    Run it before a risky change, or schedule it on a file server for extra restore points.
    Lists the existing shadow copies of each volume afterwards.

.PARAMETER Volume
    Drive letters, e.g. C, D. Default: every fixed NTFS volume with a drive letter.

.PARAMETER MaxStorageSize
    Optional shadow storage limit per volume, e.g. '10GB' or '15%' (vssadmin syntax).
    Older shadow copies are removed by Windows when the limit is reached.

.EXAMPLE
    .\New-ShadowCopy.ps1 -Volume C,D

.EXAMPLE
    .\New-ShadowCopy.ps1 -Volume D -MaxStorageSize 15% -WhatIf

.NOTES
    Requirements : run as Administrator; Windows Server or Windows client with VSS.
    Safety       : uses disk space on the volume; with -MaxStorageSize, lowering the limit can delete
                   existing (older) shadow copies.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidatePattern('^[A-Za-z]:?$')]
    [string[]]$Volume,
    [string]$MaxStorageSize
)
$ErrorActionPreference = 'Stop'

if (-not $Volume) {
    $Volume = Get-CimInstance Win32_Volume -Filter "DriveType=3 AND FileSystem='NTFS'" |
        Where-Object { $_.DriveLetter } | ForEach-Object { $_.DriveLetter }
}

foreach ($v in $Volume) {
    $root = $v.Substring(0, 1).ToUpper() + ':\'
    if ($MaxStorageSize -and $PSCmdlet.ShouldProcess($root, "Set shadow storage max size to $MaxStorageSize")) {
        & vssadmin.exe resize shadowstorage /For=$($root.TrimEnd('\')) /On=$($root.TrimEnd('\')) /MaxSize=$MaxStorageSize
        if ($LASTEXITCODE -ne 0) {
            & vssadmin.exe add shadowstorage /For=$($root.TrimEnd('\')) /On=$($root.TrimEnd('\')) /MaxSize=$MaxStorageSize
        }
    }
    if ($PSCmdlet.ShouldProcess($root, 'Create shadow copy')) {
        $r = Invoke-CimMethod -ClassName Win32_ShadowCopy -MethodName Create -Arguments @{ Volume = $root; Context = 'ClientAccessible' }
        if ($r.ReturnValue -eq 0) { Write-Host "$root shadow copy created ($($r.ShadowID))" -ForegroundColor Green }
        else { Write-Warning "$root shadow copy failed, return value $($r.ReturnValue)" }
    }
    $vol = Get-CimInstance Win32_Volume -Filter ("Name='{0}'" -f $root.Replace('\', '\\'))
    $copies = @(Get-CimInstance Win32_ShadowCopy | Where-Object { $_.VolumeName -eq $vol.DeviceID })
    Write-Host ("{0} now has {1} shadow copy(ies), newest: {2}" -f $root, $copies.Count, ($copies | Sort-Object InstallDate | Select-Object -Last 1).InstallDate)
}
