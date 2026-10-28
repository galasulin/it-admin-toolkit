<#
.SYNOPSIS
    Fixes the Remote Desktop client error "The remote computer disconnected the session because of an
    error in the licensing protocol" by letting standard users write to the RDP client license store.

.DESCRIPTION
    The Remote Desktop client keeps the license token it receives from the RD Licensing server under
    HKLM\SOFTWARE\Microsoft\MSLicensing (and the WOW6432Node copy). When a standard user connects for the
    first time the client cannot write there, and the connection fails with the licensing-protocol error.
    Microsoft's documented workaround is to delete the key and run mstsc once "as administrator"; on
    shared or kiosk PCs that is impractical, so this script grants the local Users group Full Control on
    those keys instead (inherited by sub-keys).

    It does not create, change or bypass any license - the token still comes from your RD Licensing
    server; the client just gets permission to store it.

    The current ACL (SDDL) of each key is printed and saved before the change, so it can be restored.

.PARAMETER BackupFolder
    Where the SDDL backup is saved. Default: %TEMP%.

.PARAMETER Restore
    Path of an SDDL backup file written by this script - puts the original ACLs back.

.EXAMPLE
    .\Repair-RdpClientLicenseStore.ps1 -WhatIf

.EXAMPLE
    .\Repair-RdpClientLicenseStore.ps1 -Restore "$env:TEMP\MSLicensing-acl-20260101_120000.txt"

.NOTES
    Requirements : run as Administrator.
    Safety       : changes registry permissions on the RDP client license keys only. Keep the SDDL backup.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$BackupFolder = $env:TEMP,
    [string]$Restore
)
$ErrorActionPreference = 'Stop'

$keys = @('HKLM:\SOFTWARE\Microsoft\MSLicensing', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSLicensing')

if ($Restore) {
    foreach ($line in Get-Content $Restore) {
        $path, $sddl = $line -split "`t", 2
        if (-not (Test-Path $path)) { continue }
        if ($PSCmdlet.ShouldProcess($path, 'Restore original ACL')) {
            $acl = Get-Acl $path
            $acl.SetSecurityDescriptorSddlForm($sddl)
            Set-Acl -Path $path -AclObject $acl
            Write-Host "restored: $path" -ForegroundColor Green
        }
    }
    return
}

$backup = Join-Path $BackupFolder ('MSLicensing-acl-{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
# Well-known SID of BUILTIN\Users - works on any Windows language.
$users = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')

foreach ($k in $keys) {
    if (-not (Test-Path $k)) { Write-Host "not present: $k" -ForegroundColor DarkGray; continue }
    $acl = Get-Acl $k
    if (-not $PSCmdlet.ShouldProcess($k, 'Grant BUILTIN\Users FullControl (inherited)')) { continue }
    Add-Content -Path $backup -Value ("{0}`t{1}" -f $k, $acl.Sddl) -Encoding UTF8
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule($users, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -Path $k -AclObject $acl
    Write-Host "updated: $k" -ForegroundColor Green
}
if (Test-Path $backup) { Write-Host "Original ACLs saved to $backup (use -Restore to undo)." }
