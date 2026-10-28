<#
.SYNOPSIS
    Applies (or reverts) common Outlook per-user registry fixes for every installed Outlook version.

.DESCRIPTION
    Detects the installed Office versions (12.0 = 2007, 14.0 = 2010, 15.0 = 2013, 16.0 = 2016/2019/2021/365)
    under HKCU and applies only the fixes you select:

      -DisableTnef        Outlook\Preferences\DisableTNEF = 1
                          Stops sending rich-text "winmail.dat" (TNEF) attachments to external recipients.
      -LegacyGalDialog    common\contactcard\TurnOnLegacyGALDialog = 1 and TurnOffHoverFunctionality = 0
                          (policy key) - double-clicking a contact opens the classic GAL properties
                          dialog (phone, office, manager...) instead of the modern contact card.
      -MaxExchangeAccounts <n>
                          Software\Microsoft\Exchange\MaxNumExchange (user + policy key) - raises the
                          number of Exchange accounts allowed in one Outlook profile (default 10 in 2013+).

    Every value written is first saved to a .reg backup file (reg export), and -Revert removes the
    values this script sets.

.PARAMETER DisableTnef
    Apply the DisableTNEF fix.

.PARAMETER LegacyGalDialog
    Apply the legacy GAL dialog fix.

.PARAMETER MaxExchangeAccounts
    Value for MaxNumExchange (1-99). 0 = do not change.

.PARAMETER Version
    Office versions to target, e.g. '16.0'. Default: every version found under HKCU\Software\Microsoft\Office.

.PARAMETER BackupFolder
    Where the .reg backups are written. Default: %TEMP%\OutlookRegistryBackup.

.PARAMETER Revert
    Remove the values for the selected fixes instead of setting them.

.EXAMPLE
    .\Set-OutlookRegistryFixes.ps1 -DisableTnef -LegacyGalDialog -WhatIf

.EXAMPLE
    .\Set-OutlookRegistryFixes.ps1 -MaxExchangeAccounts 15

.EXAMPLE
    .\Set-OutlookRegistryFixes.ps1 -DisableTnef -Revert

.NOTES
    Requirements : Windows PowerShell 5.1+, run as the target user (HKCU). No admin rights needed.
    Safety       : changes the current user's registry. Close Outlook first; changes apply on next start.
                   A .reg backup of each touched key is written before any change.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$DisableTnef,
    [switch]$LegacyGalDialog,
    [ValidateRange(0, 99)][int]$MaxExchangeAccounts = 0,
    [string[]]$Version,
    [string]$BackupFolder = (Join-Path $env:TEMP 'OutlookRegistryBackup'),
    [switch]$Revert
)
$ErrorActionPreference = 'Stop'

if (-not ($DisableTnef -or $LegacyGalDialog -or $MaxExchangeAccounts)) {
    Write-Host 'Nothing selected. Use -DisableTnef, -LegacyGalDialog and/or -MaxExchangeAccounts <n>. See Get-Help.' -ForegroundColor Yellow
    return
}

if (-not $Version) {
    $Version = Get-ChildItem 'HKCU:\Software\Microsoft\Office' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d+\.0$' -and (Test-Path (Join-Path $_.PSPath 'Outlook')) } |
        ForEach-Object { $_.PSChildName }
    if (-not $Version) { Write-Warning 'No Outlook version found under HKCU. Pass -Version 16.0 to force.'; return }
}
Write-Host ("Outlook versions: {0}" -f ($Version -join ', '))

New-Item -ItemType Directory -Path $BackupFolder -Force -WhatIf:$false | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

function Backup-Key([string]$Key) {
    $native = $Key -replace '^HKCU:', 'HKCU'
    if (Test-Path $Key) {
        $file = Join-Path $BackupFolder (('{0}_{1}.reg' -f ($native -replace '[\\: ]', '_'), $stamp))
        & reg.exe export $native $file /y | Out-Null
    }
}

function Set-Value([string]$Key, [string]$Name, [int]$Value) {
    if ($Revert) {
        if ((Test-Path $Key) -and (Get-ItemProperty -Path $Key -Name $Name -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess("$Key\$Name", 'Remove value')) {
                Backup-Key $Key
                Remove-ItemProperty -Path $Key -Name $Name
                Write-Host "  removed $Key\$Name" -ForegroundColor Green
            }
        }
        return
    }
    if ($PSCmdlet.ShouldProcess("$Key\$Name", "Set DWORD $Value")) {
        Backup-Key $Key
        if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
        New-ItemProperty -Path $Key -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
        Write-Host "  set $Key\$Name = $Value" -ForegroundColor Green
    }
}

foreach ($v in $Version) {
    Write-Host "Office $v"
    if ($DisableTnef) {
        Set-Value "HKCU:\Software\Microsoft\Office\$v\Outlook\Preferences" 'DisableTNEF' 1
    }
    if ($LegacyGalDialog) {
        $k = "HKCU:\Software\Policies\Microsoft\Office\$v\common\contactcard"
        Set-Value $k 'TurnOnLegacyGALDialog' 1
        Set-Value $k 'TurnOffHoverFunctionality' 0
    }
}
if ($MaxExchangeAccounts) {
    Set-Value 'HKCU:\Software\Microsoft\Exchange' 'MaxNumExchange' $MaxExchangeAccounts
    Set-Value 'HKCU:\Software\Policies\Microsoft\Exchange' 'MaxNumExchange' $MaxExchangeAccounts
}
Write-Host ("Done. Registry backups (if any): {0}. Restart Outlook to apply." -f $BackupFolder)
