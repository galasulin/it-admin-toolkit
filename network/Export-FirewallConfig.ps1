<#
.SYNOPSIS
    Exports the Windows Firewall policy (.wfw, re-importable) and a readable list of all rules,
    named <computer>_FW-..._<date>. Can also import or reset the policy.

.DESCRIPTION
    Default (export):
      <OutputFolder>\<COMPUTER>_FW-Settings_<yyyy-MM-dd_HH-mm>.wfw   - netsh advfirewall export (full policy)
      <OutputFolder>\<COMPUTER>_FW-Rules_<yyyy-MM-dd_HH-mm>.csv      - every rule with ports / addresses / program
    -Import <file.wfw> : restores a policy exported earlier (netsh advfirewall import).
    -Reset             : resets the firewall to Windows defaults (netsh advfirewall reset). Exports first.

    Useful before changing firewall rules, to compare two machines, or to copy a known-good policy.

.PARAMETER OutputFolder
    Where the export files are written. Default: the current folder.

.PARAMETER Import
    Path of a .wfw file to import (replaces the current policy).

.PARAMETER Reset
    Reset the firewall policy to the Windows defaults (a backup export is always taken first).

.EXAMPLE
    .\Export-FirewallConfig.ps1 -OutputFolder 'E:\FirewallBackup'

.EXAMPLE
    .\Export-FirewallConfig.ps1 -Import '.\PC01_FW-Settings_2026-01-01_10-00.wfw' -WhatIf

.NOTES
    Requirements : run as Administrator (export of the policy and every change need elevation).
    Safety       : -Import and -Reset REPLACE the whole firewall policy and can cut remote sessions (RDP).
                   Do not run them remotely without console access. Export is read-only.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Export')]
param(
    [string]$OutputFolder = (Get-Location).Path,
    [Parameter(ParameterSetName = 'Import', Mandatory = $true)]
    [string]$Import,
    [Parameter(ParameterSetName = 'Reset', Mandatory = $true)]
    [switch]$Reset
)
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this script as Administrator.' }

New-Item -ItemType Directory -Path $OutputFolder -Force -WhatIf:$false | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm'
$wfw = Join-Path $OutputFolder ('{0}_FW-Settings_{1}.wfw' -f $env:COMPUTERNAME, $stamp)
$csv = Join-Path $OutputFolder ('{0}_FW-Rules_{1}.csv' -f $env:COMPUTERNAME, $stamp)

# Always export first - it is the undo for -Import / -Reset.
& netsh.exe advfirewall export "$wfw" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "netsh export failed ($LASTEXITCODE)" }
Write-Host "policy exported: $wfw" -ForegroundColor Green

if ($PSCmdlet.ParameterSetName -eq 'Export') {
    Get-NetFirewallRule | ForEach-Object {
        $pf = $_ | Get-NetFirewallPortFilter
        $af = $_ | Get-NetFirewallAddressFilter
        $ap = $_ | Get-NetFirewallApplicationFilter
        [pscustomobject]@{
            DisplayName   = $_.DisplayName
            Group         = $_.DisplayGroup
            Enabled       = $_.Enabled
            Direction     = $_.Direction
            Action        = $_.Action
            Profile       = $_.Profile
            Protocol      = $pf.Protocol
            LocalPort     = ($pf.LocalPort -join ',')
            RemotePort    = ($pf.RemotePort -join ',')
            RemoteAddress = ($af.RemoteAddress -join ',')
            Program       = $ap.Program
        }
    } | Sort-Object Direction, DisplayName | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    Write-Host "rules exported : $csv" -ForegroundColor Green
    return
}

if ($PSCmdlet.ParameterSetName -eq 'Import') {
    $src = (Resolve-Path $Import).Path
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Import firewall policy from $src (replaces the current policy)")) {
        & netsh.exe advfirewall import "$src"
        Write-Host "imported. Undo: .\Export-FirewallConfig.ps1 -Import '$wfw'" -ForegroundColor Yellow
    }
    return
}

if ($Reset -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Reset the firewall policy to Windows defaults')) {
    & netsh.exe advfirewall reset
    Write-Host "reset done. Undo: .\Export-FirewallConfig.ps1 -Import '$wfw'" -ForegroundColor Yellow
}
