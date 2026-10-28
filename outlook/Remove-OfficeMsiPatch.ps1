<#
.SYNOPSIS
    Removes a single Office (MSI-based) update patch - the classic fix when an Office update breaks Outlook.

.DESCRIPTION
    Runs  msiexec /I {ProductCode} MSIPATCHREMOVE={PatchGuid} /qn  to uninstall one patch from an
    MSI-installed Office product (Office 2007/2010/2013/2016 MSI; NOT Click-to-Run / Microsoft 365).

    The defaults are the case this script was first written for: KB3114409 (December 2015), which made
    Outlook 2010 start in safe mode. To remove a different patch, pass its product code and patch GUID
    (find them in the KB article, or with:
        Get-CimInstance -Namespace root\cimv2 -ClassName Win32_PatchPackage ).

.PARAMETER ProductCode
    The Office product code. Default: Office 2010 Professional Plus 32-bit / Outlook 2010 component
    {90140000-0011-0000-0000-0000000FF1CE}.

.PARAMETER PatchGuid
    The patch GUID to remove. Default: {14CDCBF7-3CCC-42E2-A5BB-2D4926E16FAA} (KB3114409).

.PARAMETER LogPath
    Verbose MSI log. Default: %TEMP%\Remove-OfficeMsiPatch.log

.EXAMPLE
    .\Remove-OfficeMsiPatch.ps1 -WhatIf

.EXAMPLE
    .\Remove-OfficeMsiPatch.ps1 -ProductCode '{90150000-0011-0000-0000-0000000FF1CE}' -PatchGuid '{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}'

.NOTES
    Requirements : run as Administrator; Office must be MSI-installed.
    Safety       : uninstalls an update. Close Office applications first and restart the PC afterwards.
                   Re-hide the update in Windows Update / WSUS or it will be offered again.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidatePattern('^\{[0-9A-Fa-f-]{36}\}$')]
    [string]$ProductCode = '{90140000-0011-0000-0000-0000000FF1CE}',
    [ValidatePattern('^\{[0-9A-Fa-f-]{36}\}$')]
    [string]$PatchGuid = '{14CDCBF7-3CCC-42E2-A5BB-2D4926E16FAA}',
    [string]$LogPath = (Join-Path $env:TEMP 'Remove-OfficeMsiPatch.log')
)
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this script as Administrator.' }

$msiArgs = @('/I', $ProductCode, "MSIPATCHREMOVE=$PatchGuid", '/qn', '/norestart', '/L*v', "`"$LogPath`"")
if ($PSCmdlet.ShouldProcess("$ProductCode", "Remove patch $PatchGuid")) {
    $p = Start-Process -FilePath msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    switch ($p.ExitCode) {
        0       { Write-Host 'Patch removed. PLEASE RESTART THE COMPUTER.' -ForegroundColor Green }
        3010    { Write-Host 'Patch removed - a restart is required.' -ForegroundColor Green }
        1605    { Write-Host 'The product is not installed (1605).' -ForegroundColor Yellow }
        1642    { Write-Host 'The patch is not installed / not applicable (1642).' -ForegroundColor Yellow }
        default { Write-Host ("msiexec exit code {0} - see {1}" -f $p.ExitCode, $LogPath) -ForegroundColor Red }
    }
    exit $p.ExitCode
}
