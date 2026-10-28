<#
.SYNOPSIS
    Lists the members of the local Administrators group on one or many computers and exports them to CSV.

.DESCRIPTION
    Audits who has local admin rights. Uses the group SID (S-1-5-32-544), so it works on any Windows
    language (the group is not always called "Administrators"). Remote computers are queried through
    PowerShell remoting; unreachable computers are listed with an error instead of stopping the run.

.PARAMETER ComputerName
    Computers to query. Default: the local computer.

.PARAMETER ComputerListPath
    Text file with one computer name per line (alternative to -ComputerName).

.PARAMETER OutputCsv
    CSV file to write. Default: .\LocalAdmins_<yyyyMMdd_HHmm>.csv

.EXAMPLE
    .\Get-LocalAdmins.ps1

.EXAMPLE
    .\Get-LocalAdmins.ps1 -ComputerListPath .\computers.txt -OutputCsv .\exports\local-admins.csv

.NOTES
    Requirements : Windows PowerShell 5.1 (Microsoft.PowerShell.LocalAccounts); admin rights and WinRM on
                   remote computers.
    Safety       : read-only.
    Author       : Gal Asulin
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [string]$ComputerListPath,
    [string]$OutputCsv = (Join-Path (Get-Location).Path ('LocalAdmins_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmm')))
)
$ErrorActionPreference = 'Stop'

if ($ComputerListPath) { $ComputerName = Get-Content $ComputerListPath | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() } }

$query = {
    Get-LocalGroupMember -SID 'S-1-5-32-544' | ForEach-Object {
        [pscustomobject]@{ Computer = $env:COMPUTERNAME; Member = $_.Name; ObjectClass = [string]$_.ObjectClass; Source = [string]$_.PrincipalSource; Error = '' }
    }
}

$rows = foreach ($c in $ComputerName) {
    try {
        if ($c -eq $env:COMPUTERNAME -or $c -eq 'localhost') { & $query }
        else { Invoke-Command -ComputerName $c -ScriptBlock $query | Select-Object Computer, Member, ObjectClass, Source, Error }
    } catch {
        [pscustomobject]@{ Computer = $c; Member = ''; ObjectClass = ''; Source = ''; Error = $_.Exception.Message }
    }
}

$outDir = Split-Path -Parent $OutputCsv
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$rows | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
$rows | Format-Table -AutoSize
Write-Host "Saved: $OutputCsv" -ForegroundColor Green
