<#
.SYNOPSIS
    Configures the OneDrive sync client on a PC through its policy registry keys: silent sign-in with the
    Windows account, Files On-Demand, and the large-library download prompt threshold.

.DESCRIPTION
    For PCs that are not managed by Intune / GPO (or to test a policy before rolling it out).
    Each setting is optional; only the selected ones are written:

      -SilentAccountConfig   HKLM\SOFTWARE\Policies\Microsoft\OneDrive\SilentAccountConfig = 1
                             (signs users in to OneDrive with their Windows / Entra credentials)
      -FilesOnDemand         HKLM\...\OneDrive\FilesOnDemandEnabled = 1
      -DiskSpaceCheckMB <n>  HKLM\...\OneDrive\DiskSpaceCheckThresholdMB\<TenantId> = n
                             (ask the user before downloading a library larger than n MB; needs -TenantId)
      -EnableAdal            HKCU\SOFTWARE\Microsoft\OneDrive\EnableADAL = 1
                             (modern authentication for older OneDrive clients)

    The current value of each setting is printed before it is changed.

.PARAMETER SilentAccountConfig
    Enable silent account configuration.

.PARAMETER FilesOnDemand
    Enable Files On-Demand.

.PARAMETER DiskSpaceCheckMB
    Download prompt threshold in MB (e.g. 102400 = 100 GB). Requires -TenantId.

.PARAMETER TenantId
    Your Microsoft 365 tenant ID (GUID) - Entra admin center > Overview.

.PARAMETER EnableAdal
    Enable ADAL / modern authentication for the current user (legacy clients only).

.EXAMPLE
    .\Set-OneDrivePolicies.ps1 -SilentAccountConfig -FilesOnDemand -WhatIf

.EXAMPLE
    .\Set-OneDrivePolicies.ps1 -SilentAccountConfig -DiskSpaceCheckMB 102400 -TenantId '<TENANT_ID_GUID>'

.NOTES
    Requirements : run as Administrator for the HKLM settings; restart OneDrive (or sign out / in) to apply.
    Safety       : writes OneDrive policy values in the registry. Undo: delete the values under
                   HKLM\SOFTWARE\Policies\Microsoft\OneDrive (and HKCU\SOFTWARE\Microsoft\OneDrive\EnableADAL).
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SilentAccountConfig,
    [switch]$FilesOnDemand,
    [ValidateRange(1, 10485760)][int]$DiskSpaceCheckMB,
    [guid]$TenantId,
    [switch]$EnableAdal
)
$ErrorActionPreference = 'Stop'

if ($DiskSpaceCheckMB -and -not $TenantId) { throw '-DiskSpaceCheckMB needs -TenantId.' }
if (-not ($SilentAccountConfig -or $FilesOnDemand -or $DiskSpaceCheckMB -or $EnableAdal)) {
    Write-Host 'Nothing selected - see Get-Help .\Set-OneDrivePolicies.ps1 -Full' -ForegroundColor Yellow
    return
}

$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive'

function Set-Dword([string]$Key, [string]$Name, [int]$Value) {
    $old = (Get-ItemProperty -Path $Key -Name $Name -ErrorAction SilentlyContinue).$Name
    Write-Host ("{0}\{1}: current = {2}" -f $Key, $Name, $(if ($null -eq $old) { '(not set)' } else { $old }))
    if ($PSCmdlet.ShouldProcess("$Key\$Name", "Set DWORD $Value")) {
        if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
        New-ItemProperty -Path $Key -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
        Write-Host ("  -> {0}" -f $Value) -ForegroundColor Green
    }
}

if ($SilentAccountConfig) { Set-Dword $policy 'SilentAccountConfig' 1 }
if ($FilesOnDemand)       { Set-Dword $policy 'FilesOnDemandEnabled' 1 }
if ($DiskSpaceCheckMB)    { Set-Dword (Join-Path $policy 'DiskSpaceCheckThresholdMB') $TenantId.Guid $DiskSpaceCheckMB }
if ($EnableAdal)          { Set-Dword 'HKCU:\SOFTWARE\Microsoft\OneDrive' 'EnableADAL' 1 }

Write-Host 'Done. Restart OneDrive to apply.'
