<#
.SYNOPSIS
    Finds Active Directory computer accounts that have not logged on for N days, reports them, and
    optionally disables them and/or moves them to a "disabled computers" OU.

.DESCRIPTION
    Uses LastLogonDate (lastLogonTimestamp - replicated, accurate to about 14 days, so do not use a
    threshold below 30). Computers that never logged on are listed separately and are not touched
    unless -IncludeNeverLoggedOn is given (fresh pre-staged accounts look like that too).
    Always writes a CSV report first; nothing is changed without -Disable and/or -TargetOU, and every
    change supports -WhatIf / -Confirm. Each disabled account gets a description stamp
    ("Disabled by script <date>, last logon <date>") so it can be found and re-enabled later.

.PARAMETER SearchBase
    OU to search, e.g. 'OU=Workstations,DC=contoso,DC=local'. Default: the whole domain.

.PARAMETER DaysInactive
    Computers whose LastLogonDate is older than this many days. Default: 90.

.PARAMETER TargetOU
    Distinguished name of the OU to move stale computers to, e.g. 'OU=Disabled Computers,DC=contoso,DC=local'.

.PARAMETER Disable
    Disable the stale computer accounts.

.PARAMETER IncludeNeverLoggedOn
    Also act on accounts with no LastLogonDate that were created more than -DaysInactive days ago.

.PARAMETER ExcludeServers
    Skip computers whose OperatingSystem contains "Server" (default: on).

.PARAMETER ReportPath
    CSV report. Default: .\StaleComputers_<yyyyMMdd_HHmm>.csv

.EXAMPLE
    .\Move-StaleComputers.ps1 -SearchBase 'OU=Workstations,DC=contoso,DC=local' -DaysInactive 90

    Report only.

.EXAMPLE
    .\Move-StaleComputers.ps1 -DaysInactive 120 -Disable -TargetOU 'OU=Disabled Computers,DC=contoso,DC=local' -WhatIf

.NOTES
    Requirements : RSAT ActiveDirectory module; rights to disable / move computer objects in the OUs.
    Safety       : disabling a computer account breaks the trust of that machine with the domain until it
                   is re-enabled. Review the CSV and run with -WhatIf first. Nothing is deleted.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$SearchBase,
    [ValidateRange(30, 3650)]
    [int]$DaysInactive = 90,
    [string]$TargetOU,
    [switch]$Disable,
    [switch]$IncludeNeverLoggedOn,
    [bool]$ExcludeServers = $true,
    [string]$ReportPath = (Join-Path (Get-Location).Path ('StaleComputers_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmm')))
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$cutoff = (Get-Date).AddDays(-$DaysInactive)
$getParams = @{ Filter = '*'; Properties = 'LastLogonDate', 'OperatingSystem', 'whenCreated', 'Description', 'Enabled' }
if ($SearchBase) { $getParams.SearchBase = $SearchBase }

$computers = Get-ADComputer @getParams
if ($ExcludeServers) { $computers = $computers | Where-Object { $_.OperatingSystem -notmatch 'Server' } }

$stale = $computers | Where-Object {
    ($_.LastLogonDate -and $_.LastLogonDate -lt $cutoff) -or
    ($IncludeNeverLoggedOn -and -not $_.LastLogonDate -and $_.whenCreated -lt $cutoff)
}
$never = $computers | Where-Object { -not $_.LastLogonDate }

$report = $stale | Select-Object Name, Enabled, LastLogonDate, whenCreated, OperatingSystem, DistinguishedName
$report | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
Write-Host ("{0} stale computer(s) (no logon since {1:yyyy-MM-dd}). Report: {2}" -f @($stale).Count, $cutoff, $ReportPath)
Write-Host ("{0} computer(s) never logged on{1}." -f @($never).Count, $(if ($IncludeNeverLoggedOn) { ' (included)' } else { ' (listed in the report only if included)' }))

if (-not $Disable -and -not $TargetOU) {
    Write-Host 'Report only. Add -Disable and/or -TargetOU to act (try -WhatIf first).' -ForegroundColor Yellow
    return
}

foreach ($c in $stale) {
    $last = if ($c.LastLogonDate) { $c.LastLogonDate.ToString('yyyy-MM-dd') } else { 'never' }
    if ($Disable -and $c.Enabled -and $PSCmdlet.ShouldProcess($c.Name, 'Disable computer account')) {
        $desc = ('Disabled by script {0}, last logon {1}' -f (Get-Date -Format 'yyyy-MM-dd'), $last)
        Set-ADComputer -Identity $c -Enabled $false -Description $desc
        Write-Host "disabled: $($c.Name)" -ForegroundColor Green
    }
    if ($TargetOU -and $c.DistinguishedName -notlike "*,$TargetOU" -and $PSCmdlet.ShouldProcess($c.Name, "Move to $TargetOU")) {
        Move-ADObject -Identity $c.DistinguishedName -TargetPath $TargetOU
        Write-Host "moved   : $($c.Name)" -ForegroundColor Green
    }
}
