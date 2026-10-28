<#
.SYNOPSIS
    Uninstalls a problematic Windows update (by KB number or by DISM package name) and can pause
    Windows Update so it is not re-installed straight away.

.DESCRIPTION
    Some cumulative updates cannot be removed with "wusa /uninstall" (they are combined with the
    servicing stack). This script looks the update up in the DISM package list instead and removes the
    matching package(s) - the same approach as the classic "uninstall KB5000808" fix (the March 2021
    update that crashed Windows when printing to some printers).

      1. Finds installed packages whose name or description matches -KB, or whose name matches -PackageName.
      2. Lists them. With -WhatIf nothing else happens.
      3. Removes each package with Remove-WindowsPackage (DISM) -NoRestart.
         If no DISM package matches, falls back to  wusa.exe /uninstall /kb:<n> /quiet /norestart.
      4. Optionally pauses Windows Update until -PauseUntil.

.PARAMETER KB
    KB number(s), with or without the "KB" prefix, e.g. 5000808.

.PARAMETER PackageName
    Wildcard on the DISM package name, e.g. 'Package_for_RollupFix~31bf3856ad364e35~amd64~~18362.1440*'.

.PARAMETER PauseUntil
    Pause Windows Update until this date (max ~35 days ahead, Windows 10/11 Pro and above).

.PARAMETER Restart
    Restart the computer when done (otherwise a restart is required manually).

.EXAMPLE
    .\Remove-WindowsUpdatePackage.ps1 -KB 5000808 -WhatIf

.EXAMPLE
    .\Remove-WindowsUpdatePackage.ps1 -KB 5000802,5000808 -PauseUntil (Get-Date).AddDays(14)

.EXAMPLE
    .\Remove-WindowsUpdatePackage.ps1 -PackageName 'Package_for_RollupFix*18362.1440*'

.NOTES
    Requirements : run as Administrator; Windows 10 / 11 / Server 2016+ (DISM PowerShell module).
    Safety       : removes an installed update (possibly a security update) and needs a restart.
                   Remove only what is proven to cause the problem, and hide / decline it in WSUS or
                   Intune until a fixed version is released. Use -WhatIf first.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$KB,
    [string]$PackageName,
    [datetime]$PauseUntil,
    [switch]$Restart
)
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this script as Administrator.' }
if (-not $KB -and -not $PackageName) { throw 'Pass -KB and/or -PackageName.' }

$kbNumbers = @($KB | ForEach-Object { ($_ -replace '^(?i)KB', '').Trim() } | Where-Object { $_ })

Write-Host 'Reading installed packages (DISM) ...'
$packages = Get-WindowsPackage -Online | Where-Object { $_.PackageState -eq 'Installed' }

$found = @()
if ($PackageName) { $found += $packages | Where-Object { $_.PackageName -like $PackageName } }
foreach ($n in $kbNumbers) {
    $hit = $packages | Where-Object { $_.PackageName -match "KB$n" }
    if (-not $hit) {
        # Cumulative updates are named "RollupFix" - match on the package description instead.
        $hit = $packages | ForEach-Object { Get-WindowsPackage -Online -PackageName $_.PackageName } |
            Where-Object { $_.Description -match "KB$n" -or $_.DisplayName -match "KB$n" }
    }
    if ($hit) { $found += $hit } else { Write-Host "KB$n : no DISM package found - will try wusa." -ForegroundColor Yellow }
}
$found = $found | Sort-Object PackageName -Unique

foreach ($p in $found) {
    Write-Host ("found: {0}" -f $p.PackageName)
    if ($PSCmdlet.ShouldProcess($p.PackageName, 'Remove-WindowsPackage')) {
        Remove-WindowsPackage -Online -PackageName $p.PackageName -NoRestart | Out-Null
        Write-Host '  removed (restart pending)' -ForegroundColor Green
    }
}

foreach ($n in $kbNumbers) {
    if ($found | Where-Object { $_.PackageName -match "KB$n" -or $_.Description -match "KB$n" }) { continue }
    if (-not (Get-HotFix -Id "KB$n" -ErrorAction SilentlyContinue)) { Write-Host "KB$n is not installed."; continue }
    if ($PSCmdlet.ShouldProcess("KB$n", 'wusa /uninstall')) {
        $wp = Start-Process -FilePath wusa.exe -ArgumentList "/uninstall /kb:$n /quiet /norestart" -Wait -PassThru
        Write-Host ("KB{0}: wusa exit code {1} (0 / 3010 = removed, 2359303 = not installed)" -f $n, $wp.ExitCode)
    }
}

if ($PauseUntil) {
    $key = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    $until = $PauseUntil.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    if ($PSCmdlet.ShouldProcess('Windows Update', "Pause until $until")) {
        foreach ($name in 'PauseUpdatesExpiryTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime') {
            Set-ItemProperty -Path $key -Name $name -Value $until
        }
        foreach ($name in 'PauseUpdatesStartTime', 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime') {
            Set-ItemProperty -Path $key -Name $name -Value $now
        }
        Write-Host "Windows Update paused until $until" -ForegroundColor Green
    }
}

if ($Restart -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Restart')) { Restart-Computer -Force }
else { Write-Host 'A restart is required to finish removing the update(s).' -ForegroundColor Yellow }
