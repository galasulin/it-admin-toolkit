<#
.SYNOPSIS
    Runs a .sql file against SQL Server with Windows authentication and keeps a full evidence log.
    No sqlcmd / SqlServer module needed.

.DESCRIPTION
    - Splits the file on lines that contain only "GO" and runs the batches in order on ONE connection.
    - Prints every PRINT / RAISERROR message and every result set as a simple table.
    - Stops at the first error and reports which batch failed.
    - Appends everything to the -Out log file as well as the screen, so the output can be kept
      as evidence instead of being copied by hand.
    It never asks for or stores credentials - it uses Integrated Security only. The connection is always
    encrypted; by default the server certificate must be trusted by this machine.

.PARAMETER File
    The .sql file to run (UTF-8).

.PARAMETER Out
    Log file to append to (created if missing).

.PARAMETER Server
    SQL Server instance, e.g. SQL01 or SQL01\INSTANCE.

.PARAMETER Database
    Database to connect to. Default: master.

.PARAMETER Title
    Optional free text written on the header line of the log.

.PARAMETER CommandTimeoutSeconds
    Timeout per batch. Default: 600.

.PARAMETER TrustServerCertificate
    Keep the connection encrypted but do NOT validate the server certificate. Use only for an
    internal server you know presents a self-signed certificate, and connect to it by name.

.EXAMPLE
    .\Invoke-SqlFile.ps1 -File .\check-jobs.sql -Out .\logs\check-jobs.txt -Server SQL01

.EXAMPLE
    .\Invoke-SqlFile.ps1 -File .\report.sql -Out .\report.txt -Server 'SQL01\INSTANCE2' -Database Reports -TrustServerCertificate

.NOTES
    Requirements : Windows PowerShell 5.1 (System.Data.SqlClient). Rights in SQL Server as needed by the file.
    Safety       : the script runs WHATEVER is in the file - read it first. Use -WhatIf to see the batches
                   that would run without connecting. Exit codes: 0 = OK, 1 = a batch failed, 2 = no connection.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$File,
    [Parameter(Mandatory = $true)][string]$Out,
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$Database = 'master',
    [string]$Title = '',
    [int]$CommandTimeoutSeconds = 600,
    [switch]$TrustServerCertificate
)
$ErrorActionPreference = 'Stop'

function Write-Both([string]$Line) {
    Write-Host $Line
    [IO.File]::AppendAllText($Out, $Line + "`r`n", (New-Object Text.UTF8Encoding $false))
}

$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$sql = [IO.File]::ReadAllText((Resolve-Path $File), [Text.Encoding]::UTF8)
$batches = @([regex]::Split($sql, '(?im)^\s*GO\s*;?\s*$') | Where-Object { $_.Trim() -ne '' })

if (-not $PSCmdlet.ShouldProcess("$Server / $Database", ("run {0} batch(es) from {1}" -f $batches.Count, (Split-Path $File -Leaf)))) {
    $i = 0
    foreach ($b in $batches) { $i++; Write-Host ("--- batch {0} ---`n{1}" -f $i, $b.Trim()) }
    return
}

Write-Both ("=== {0} | {1} | {2} batch(es) | {3} | as {4}\{5} | {6}" -f $Title, (Split-Path $File -Leaf), $batches.Count, $Server, $env:USERDOMAIN, $env:USERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if ($TrustServerCertificate) {
    Write-Both ("  note: -TrustServerCertificate was given - the connection to {0} is encrypted, but the certificate was NOT validated" -f $Server)
}

$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$csb['Data Source'] = $Server
$csb['Initial Catalog'] = $Database
$csb['Integrated Security'] = $true
$csb['Encrypt'] = $true
$csb['TrustServerCertificate'] = [bool]$TrustServerCertificate
$csb['Application Name'] = 'Invoke-SqlFile'

$cn = New-Object System.Data.SqlClient.SqlConnection $csb.ConnectionString
$cn.FireInfoMessageEventOnUserErrors = $false
$handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] { param($s, $e) foreach ($m in $e.Errors) { Write-Both ("  msg: " + $m.Message) } }
$cn.add_InfoMessage($handler)

try { $cn.Open() }
catch {
    Write-Both ("=== NOT CONNECTED to {0}: {1}" -f $Server, $_.Exception.Message)
    if (-not $TrustServerCertificate -and $_.Exception.Message -match 'certificate') {
        Write-Both '    The server presented a certificate this machine does not trust. If it is an internal server'
        Write-Both '    known to use a self-signed certificate, run again with -TrustServerCertificate.'
    }
    exit 2
}

$n = 0
try {
    foreach ($b in $batches) {
        $n++
        $cmd = $cn.CreateCommand(); $cmd.CommandText = $b; $cmd.CommandTimeout = $CommandTimeoutSeconds
        $rd = $cmd.ExecuteReader()
        do {
            if ($rd.FieldCount -gt 0) {
                $cols = 0..($rd.FieldCount - 1) | ForEach-Object { $rd.GetName($_) }
                Write-Both ("  | " + ($cols -join ' | '))
                $rows = 0
                while ($rd.Read()) {
                    $vals = 0..($rd.FieldCount - 1) | ForEach-Object { if ($rd.IsDBNull($_)) { 'NULL' } else { ([string]$rd.GetValue($_)) -replace "[`r`n]+", ' ' } }
                    Write-Both ("  | " + ($vals -join ' | ')); $rows++
                }
                Write-Both ("  ({0} row(s))" -f $rows)
            }
        } while ($rd.NextResult())
        $rd.Close()
    }
    Write-Both ("=== OK - {0} batch(es) ran" -f $n)
    exit 0
} catch {
    Write-Both ("=== STOPPED at batch {0}: {1}" -f $n, $_.Exception.Message)
    exit 1
} finally { $cn.Close() }
