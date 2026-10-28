<#
.SYNOPSIS
    Daily tripwire that warns, loudly and early, before an Entra ID (Azure AD) app client secret expires.

.DESCRIPTION
    WHY: an Entra client secret has a hard maximum lifetime (24 months). On the day it expires, an
    unattended integration that uses it (a report mailer, a sync job...) usually stops SILENTLY:
    no error, no bounce, no alert - things simply stop arriving and nobody notices for weeks.

    WHY A DATE IN A FILE, NOT A GRAPH QUERY: a well-scoped app registration has NO Microsoft Graph
    permissions, so it cannot read its own expiry. Granting Application.Read.All just for that would
    re-open the org-wide access the scoping was meant to avoid. A local dated file is the right trade.

    The script records the expiry date in a text file next to itself, registers a daily scheduled task,
    and on each run compares today with that date. At the thresholds (60, 45, 30, 21, 14, 10, 7, 5, 3,
    2, 1, 0 days, and every day after expiry) it writes to a log file, to the Application event log
    (so monitoring can pick it up) and shows a pop-up when someone is logged on.

.PARAMETER ExpiryDate
    Expiry date of the current client secret (yyyy-MM-dd) - the "Expires" column in
    Entra > App registrations > <app> > Certificates & secrets.

.PARAMETER AppName
    Display name used in messages, the event source and the task name. Default: 'Entra app'.

.PARAMETER RenewalHint
    Free text added to the alert telling the reader how to renew (runbook name, where the secret is used).

.PARAMETER Register
    Write the date and create / refresh the daily scheduled task (09:00).

.PARAMETER TestAlert
    Fire an alert right now, to prove the plumbing works.

.PARAMETER Unregister
    Remove the scheduled task.

.EXAMPLE
    .\Watch-AppSecretExpiry.ps1 -AppName 'Report Mailer' -ExpiryDate 2028-08-09 -Register

.EXAMPLE
    .\Watch-AppSecretExpiry.ps1 -AppName 'Report Mailer' -TestAlert

.EXAMPLE
    .\Watch-AppSecretExpiry.ps1 -AppName 'Report Mailer' -Unregister

.NOTES
    Requirements : Windows PowerShell 5.1+, ScheduledTasks module. Administrator rights for -Register /
                   -Unregister and to create the event source (falls back to the 'Application' source).
    Safety       : -Register creates a scheduled task; the check itself is read-only. When you rotate the
                   secret, re-run with the new -ExpiryDate -Register.
    Exit codes   : 0 = fine, 1 = threshold warning, 2 = expired or unreadable date.
    Author       : Gal Asulin
#>

[CmdletBinding(DefaultParameterSetName = 'Check', SupportsShouldProcess = $true)]
param(
    [Parameter(ParameterSetName = 'Check')]
    [datetime] $ExpiryDate,

    [string] $AppName = 'Entra app',

    [string] $RenewalHint = 'Create a new client secret in Entra > App registrations > Certificates & secrets, update it where the app uses it, then re-run this script with the new -ExpiryDate -Register.',

    [Parameter(ParameterSetName = 'Check')]
    [switch] $Register,

    [Parameter(ParameterSetName = 'Check')]
    [switch] $TestAlert,

    [Parameter(ParameterSetName = 'Unregister', Mandatory = $true)]
    [switch] $Unregister
)

$ErrorActionPreference = 'Stop'

$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir  = Split-Path -Parent $ScriptPath
$SafeName   = ($AppName -replace '[^A-Za-z0-9-]', '-')
$DateFile   = Join-Path $ScriptDir ("secret-expiry-{0}.txt" -f $SafeName)
$LogFile    = Join-Path $ScriptDir ("secret-expiry-{0}.log" -f $SafeName)
$TaskName   = "$AppName - Secret Expiry Watch"
$EventSource = $AppName

# Days remaining at which we escalate.
$Thresholds = 60, 45, 30, 21, 14, 10, 7, 5, 3, 2, 1, 0

function Write-Log {
    param([string] $Message, [string] $Level = 'INFO')
    $line = '{0}  [{1}]  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
    $color = switch ($Level) {
        'ALERT' { 'Red' }
        'WARN'  { 'Yellow' }
        'OK'    { 'Green' }
        default { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color
}

function Write-EventLogSafe {
    param([string] $Message, [string] $EntryType = 'Warning')
    # Creating a new event source needs admin. If that fails, fall back to a source that always exists.
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName Application -Source $EventSource
        }
        Write-EventLog -LogName Application -Source $EventSource -EventId 9001 -EntryType $EntryType -Message $Message
    } catch {
        try {
            Write-EventLog -LogName Application -Source 'Application' -EventId 9001 -EntryType $EntryType -Message $Message
        } catch {
            Write-Log "Could not write to the Application event log: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Show-Popup {
    param([string] $Message)
    # Only works in an interactive session; harmless and silent when headless.
    try {
        $wsh = New-Object -ComObject WScript.Shell
        # 0x30 = exclamation icon, 0x1000 = keep on top. 0 = no auto-dismiss.
        $null = $wsh.Popup($Message, 0, $AppName, 0x30 -bor 0x1000)
    } catch { }
}

function Invoke-Alert {
    param([string] $Message, [string] $Level)
    Write-Log $Message $Level
    Write-EventLogSafe -Message $Message -EntryType $(if ($Level -eq 'ALERT') { 'Error' } else { 'Warning' })
    Show-Popup -Message $Message
}

# ------------------------------------------------------------------ UNREGISTER
if ($PSCmdlet.ParameterSetName -eq 'Unregister') {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Log "Scheduled task '$TaskName' removed." 'OK'
        }
    } else {
        Write-Log "Scheduled task '$TaskName' was not registered - nothing to do."
    }
    return
}

# ------------------------------------------------------------------ TEST ALERT
if ($TestAlert) {
    Invoke-Alert -Message "TEST ALERT - this is a drill. If you can see this, the $AppName secret expiry watchdog works." -Level 'WARN'
    return
}

# ------------------------------------------------------------- RECORD THE DATE
if ($PSBoundParameters.ContainsKey('ExpiryDate')) {
    if ($ExpiryDate -le (Get-Date)) {
        throw "ExpiryDate '$($ExpiryDate.ToString('yyyy-MM-dd'))' is in the past. Pass the date Entra shows in the secret's Expires column."
    }
    if ($PSCmdlet.ShouldProcess($DateFile, "Record expiry date $($ExpiryDate.ToString('yyyy-MM-dd'))")) {
        Set-Content -Path $DateFile -Value $ExpiryDate.ToString('yyyy-MM-dd') -Encoding UTF8
        Write-Log "Recorded secret expiry: $($ExpiryDate.ToString('yyyy-MM-dd'))" 'OK'
    }
}

# ---------------------------------------------------------------- REGISTER TASK
if ($Register) {
    if (-not (Test-Path $DateFile) -and -not $WhatIfPreference) {
        throw "No expiry date recorded yet. Run with -ExpiryDate yyyy-MM-dd -Register."
    }
    if ($PSCmdlet.ShouldProcess($TaskName, 'Register daily scheduled task at 09:00')) {
        $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -AppName "{1}"' -f $ScriptPath, $AppName
        $action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs
        $trigger  = New-ScheduledTaskTrigger -Daily -At '09:00'
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries

        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
            -Description "Warns before the $AppName client secret expires." -Force | Out-Null

        Write-Log "Scheduled task '$TaskName' registered - runs daily at 09:00." 'OK'
    }
}

# ------------------------------------------------------------------- THE CHECK
if (-not (Test-Path $DateFile)) {
    Write-Log "No expiry date on record. Run: .\Watch-AppSecretExpiry.ps1 -AppName '$AppName' -ExpiryDate yyyy-MM-dd -Register" 'WARN'
    return
}

$recorded = (Get-Content -Path $DateFile -Raw).Trim()
try {
    $expiry = [datetime]::ParseExact($recorded, 'yyyy-MM-dd', $null)
} catch {
    Invoke-Alert -Message "$DateFile contains '$recorded', which is not a yyyy-MM-dd date. The expiry watchdog is BLIND until this is fixed." -Level 'ALERT'
    exit 2
}

$daysLeft = [int][math]::Floor(($expiry.Date - (Get-Date).Date).TotalDays)

if ($daysLeft -lt 0) {
    $msg = ("The {0} client secret EXPIRED on {1} ({2} days ago). Anything that uses it has already stopped, silently. " -f $AppName, $expiry.ToString('yyyy-MM-dd'), [math]::Abs($daysLeft)) + $RenewalHint
    Invoke-Alert -Message $msg -Level 'ALERT'
    exit 2
}

if ($Thresholds -contains $daysLeft) {
    $level = if ($daysLeft -le 7) { 'ALERT' } else { 'WARN' }
    $msg = ("The {0} client secret expires in {1} day(s), on {2}. When it does, it stops with no error and no notification. " -f $AppName, $daysLeft, $expiry.ToString('yyyy-MM-dd')) + $RenewalHint
    Invoke-Alert -Message $msg -Level $level
    exit 1
}

Write-Log "$AppName secret expires $($expiry.ToString('yyyy-MM-dd')) - $daysLeft day(s) left. Nothing to do." 'OK'
exit 0
