<#
.SYNOPSIS
    Clears stuck print jobs: stops the Print Spooler, empties the spool folder and starts it again.

.DESCRIPTION
    The standard fix for a print queue that will not clear ("Deleting - Printing" forever).
    Lists the files that will be removed, stops the Spooler service (and its dependants), deletes the
    *.SHD / *.SPL files from the spool folder, then starts the service again and shows its status.
    Works locally or on a remote computer (-ComputerName, via PowerShell remoting).

.PARAMETER ComputerName
    Computer(s) to fix. Default: the local computer.

.EXAMPLE
    .\Clear-PrintSpooler.ps1

.EXAMPLE
    .\Clear-PrintSpooler.ps1 -ComputerName PRINT01 -WhatIf

.NOTES
    Requirements : run as Administrator (local) or with admin rights + WinRM on the remote computer.
    Safety       : ALL queued print jobs on that computer are deleted, for every user. Printing stops
                   for a few seconds while the service restarts.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME)
)
$ErrorActionPreference = 'Stop'

$work = {
    param([bool]$DoIt)
    $spool = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
    $files = @(Get-ChildItem -Path $spool -File -ErrorAction SilentlyContinue)
    "{0}: {1} spool file(s) in {2}" -f $env:COMPUTERNAME, $files.Count, $spool
    if (-not $DoIt) { return }
    Stop-Service -Name Spooler -Force
    $files | Remove-Item -Force -ErrorAction SilentlyContinue
    Start-Service -Name Spooler
    $s = Get-Service -Name Spooler
    "{0}: spooler is {1}, {2} file(s) left" -f $env:COMPUTERNAME, $s.Status, @(Get-ChildItem -Path $spool -File -ErrorAction SilentlyContinue).Count
}

foreach ($c in $ComputerName) {
    $doIt = $PSCmdlet.ShouldProcess($c, 'Stop Spooler, delete all queued print jobs, start Spooler')
    if ($c -eq $env:COMPUTERNAME -or $c -eq 'localhost' -or $c -eq '.') {
        & $work $doIt
    } else {
        Invoke-Command -ComputerName $c -ScriptBlock $work -ArgumentList $doIt
    }
}
