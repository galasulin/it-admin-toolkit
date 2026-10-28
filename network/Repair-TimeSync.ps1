<#
.SYNOPSIS
    Fixes Windows time synchronization: points the Windows Time service at the domain hierarchy or at
    manual NTP peers, restarts it and forces a resync.

.DESCRIPTION
    Two modes:
      -Source Domain (default) : the normal setting for a domain member - sync from the domain hierarchy
                                 (w32tm /config /syncfromflags:domhier).
      -Source Manual           : sync from the NTP servers given in -NtpServer (e.g. on the PDC emulator
                                 or a stand-alone machine). Add -Reliable on the PDC emulator.
    Before the change the current W32Time configuration is exported to a .reg file, and the status is
    printed before and after (w32tm /query /status).

.PARAMETER Source
    Domain or Manual.

.PARAMETER NtpServer
    NTP server names for -Source Manual, e.g. 'pool.ntp.org' or '<NTP_SERVER>'.

.PARAMETER Reliable
    Mark this computer as a reliable time source (only on the PDC emulator of the forest root domain).

.PARAMETER BackupFolder
    Where the registry export of the W32Time key is written. Default: %TEMP%.

.EXAMPLE
    .\Repair-TimeSync.ps1                       # domain member: back to domain hierarchy + resync

.EXAMPLE
    .\Repair-TimeSync.ps1 -Source Manual -NtpServer 'pool.ntp.org' -Reliable -WhatIf   # PDC emulator

.NOTES
    Requirements : run as Administrator.
    Safety       : changes the Windows Time service configuration and restarts it. Undo: import the
                   .reg backup (reg import <file>) and restart w32time.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Domain', 'Manual')]
    [string]$Source = 'Domain',
    [string[]]$NtpServer,
    [switch]$Reliable,
    [string]$BackupFolder = $env:TEMP
)
$ErrorActionPreference = 'Stop'

if ($Source -eq 'Manual' -and -not $NtpServer) { throw '-Source Manual needs -NtpServer.' }

Write-Host '--- before ---' -ForegroundColor Cyan
& w32tm.exe /query /status

$backup = Join-Path $BackupFolder ('{0}-W32Time-{1}.reg' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Reconfigure Windows Time ($Source) and resync")) { return }

& reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Services\W32Time' $backup /y | Out-Null
Write-Host "W32Time settings backed up to $backup"

if ($Source -eq 'Domain') {
    & w32tm.exe /config /syncfromflags:domhier /update
} else {
    $peers = ($NtpServer | ForEach-Object { "$_,0x8" }) -join ' '
    $rel = if ($Reliable) { 'yes' } else { 'no' }
    & w32tm.exe /config /manualpeerlist:"$peers" /syncfromflags:manual /reliable:$rel /update
}

Restart-Service w32time -Force
Start-Sleep -Seconds 2
& w32tm.exe /resync /force

Write-Host '--- after ---' -ForegroundColor Cyan
& w32tm.exe /query /status
& w32tm.exe /query /source
