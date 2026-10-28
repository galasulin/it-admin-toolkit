<#
.SYNOPSIS
    Backs up SQL Server databases (FULL / DIFF / LOG), verifies every backup and applies a safe retention.

.DESCRIPTION
    For each selected database the script:
      1. runs BACKUP DATABASE (or BACKUP LOG) WITH CHECKSUM [, COMPRESSION] [, COPY_ONLY]
         to  <BackupPath>\<Database>\<Database>_<TYPE>_yyyyMMdd_HHmmss.<bak|trn>
      2. runs RESTORE VERIFYONLY ... WITH CHECKSUM on the new file
      3. ONLY when both steps succeeded, removes older files of the same database and type
         whose name matches that exact pattern and that are older than -RetentionDays.
         Nothing else in the folder is ever touched (other tools' backups, manual copies,
         files with a different naming scheme are left alone).
    Every step is written to a log file. A failure in one database does not stop the others;
    the script exits 1 if any database failed.

    Connection uses Windows authentication (Integrated Security) - no passwords are stored.

.PARAMETER SqlInstance
    SQL Server instance, e.g. SQL01 or SQL01\INSTANCE. Default: the local default instance.

.PARAMETER Database
    One or more database names. Use 'ALL_USER' (default) for every online user database,
    or 'ALL' to include master, model and msdb (tempdb is always skipped).

.PARAMETER ExcludeDatabase
    Database names to skip.

.PARAMETER BackupType
    Full (default), Diff or Log. Log backups are skipped for databases in SIMPLE recovery.

.PARAMETER BackupPath
    Root folder for the backup files AS SEEN BY THE SQL SERVER SERVICE, e.g. D:\SQLBackup or
    \\<FILE_SERVER>\<BACKUP_SHARE>. For retention to work the same path must also be reachable
    from the machine that runs this script (a UNC path is the simplest).

.PARAMETER RetentionDays
    Backup files of the same database and type older than this are removed after a successful,
    verified backup. 0 disables retention. Default: 14.

.PARAMETER CopyOnly
    Adds COPY_ONLY, so the backup does not break the differential base or the log chain of
    another backup product that already backs up this server.

.PARAMETER NoCompression
    Do not use backup compression (needed on editions that do not support it, e.g. Express).

.PARAMETER SkipVerify
    Skip RESTORE VERIFYONLY (not recommended).

.PARAMETER LogPath
    Log file. Default: .\logs\Backup-SqlDatabases_<yyyyMMdd>.log next to the script.

.PARAMETER CommandTimeoutSeconds
    Timeout for each BACKUP / RESTORE command. Default: 14400 (4 hours).

.EXAMPLE
    .\Backup-SqlDatabases.ps1 -SqlInstance SQL01 -BackupPath '\\<FILE_SERVER>\<BACKUP_SHARE>' -RetentionDays 14

    Full, compressed, verified backup of every user database on SQL01, keeps 14 days.

.EXAMPLE
    .\Backup-SqlDatabases.ps1 -SqlInstance SQL01 -Database Sales,HR -BackupType Diff -BackupPath 'E:\SQLBackup' -WhatIf

    Shows what would be backed up and removed, without doing anything.

.EXAMPLE
    # Nightly scheduled task (run as an account that is sysadmin or has db_backupoperator + CREATE ANY DATABASE for VERIFYONLY):
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Backup-SqlDatabases.ps1 -SqlInstance SQL01 -BackupPath '\\<FILE_SERVER>\<BACKUP_SHARE>' -CopyOnly

.NOTES
    Requirements : Windows PowerShell 5.1 or PowerShell 7; uses System.Data.SqlClient (no extra module needed).
    Permissions  : the running account needs BACKUP DATABASE / BACKUP LOG rights on each database and
                   CREATE ANY DATABASE (server level) for RESTORE VERIFYONLY. The SQL Server service account
                   needs write access to -BackupPath; the running account needs delete access for retention.
    Safety       : this script writes backup files and DELETES old backup files (only its own naming pattern,
                   only after a verified backup). Run once with -WhatIf first. A deleted backup cannot be undone.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SqlInstance = 'localhost',
    [string[]]$Database = @('ALL_USER'),
    [string[]]$ExcludeDatabase = @(),
    [ValidateSet('Full', 'Diff', 'Log')]
    [string]$BackupType = 'Full',
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,
    [ValidateRange(0, 3650)]
    [int]$RetentionDays = 14,
    [switch]$CopyOnly,
    [switch]$NoCompression,
    [switch]$SkipVerify,
    [string]$LogPath,
    [int]$CommandTimeoutSeconds = 14400
)

$ErrorActionPreference = 'Stop'

if (-not $LogPath) {
    $logDir = Join-Path $PSScriptRoot 'logs'
    $LogPath = Join-Path $logDir ('Backup-SqlDatabases_{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
}
$logParent = Split-Path -Parent $LogPath
if ($logParent -and -not (Test-Path $logParent)) { New-Item -ItemType Directory -Path $logParent -Force | Out-Null }

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    $color = @{ INFO = 'Gray'; OK = 'Green'; WARN = 'Yellow'; ERROR = 'Red' }[$Level]
    Write-Host $line -ForegroundColor $color
}

# Quote an identifier: [name] with ] doubled. Quote a string literal: N'text' with ' doubled.
function Get-QuotedName([string]$Name) { '[' + $Name.Replace(']', ']]') + ']' }
function Get-QuotedLiteral([string]$Text) { "N'" + $Text.Replace("'", "''") + "'" }

$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$csb['Data Source'] = $SqlInstance
$csb['Initial Catalog'] = 'master'
$csb['Integrated Security'] = $true
$csb['Application Name'] = 'Backup-SqlDatabases'
$connection = New-Object System.Data.SqlClient.SqlConnection $csb.ConnectionString

function Invoke-Sql {
    param([string]$Query, [int]$Timeout = 60)
    $cmd = $connection.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = $Timeout
    $table = New-Object System.Data.DataTable
    $reader = $cmd.ExecuteReader()
    try { $table.Load($reader) } finally { $reader.Close() }
    return , $table
}

Write-Log ('=== Start: instance={0} type={1} path={2} retention={3}d copyOnly={4} whatIf={5}' -f `
        $SqlInstance, $BackupType, $BackupPath, $RetentionDays, [bool]$CopyOnly, [bool]$WhatIfPreference)

try {
    $connection.Open()
} catch {
    Write-Log ("Cannot connect to {0}: {1}" -f $SqlInstance, $_.Exception.Message) 'ERROR'
    exit 2
}

$failed = 0
try {
    # ---- which databases ---------------------------------------------------------------------------
    $all = Invoke-Sql "SELECT name, recovery_model_desc, state_desc, is_read_only, database_id FROM sys.databases WHERE name <> 'tempdb'"
    $targets = foreach ($row in $all.Rows) {
        $name = [string]$row.name
        $isSystem = $name -in @('master', 'model', 'msdb')
        $wanted = $false
        if ($Database -contains 'ALL') { $wanted = $true }
        elseif ($Database -contains 'ALL_USER') { $wanted = -not $isSystem }
        else { $wanted = $Database -contains $name }
        if (-not $wanted -or $ExcludeDatabase -contains $name) { continue }
        if ($row.state_desc -ne 'ONLINE') { Write-Log "Skip $name - state is $($row.state_desc)" 'WARN'; continue }
        if ($BackupType -eq 'Log' -and $row.recovery_model_desc -eq 'SIMPLE') { Write-Log "Skip $name - SIMPLE recovery (no log backups)" 'WARN'; continue }
        if ($BackupType -ne 'Full' -and $name -eq 'master') { Write-Log "Skip master - only FULL backups are possible" 'WARN'; continue }
        $name
    }
    foreach ($n in $Database) {
        if ($n -notin @('ALL', 'ALL_USER') -and -not ($all.Rows | Where-Object { $_.name -eq $n })) {
            Write-Log "Database '$n' was not found on $SqlInstance" 'ERROR'; $failed++
        }
    }
    if (-not $targets) { Write-Log 'No database to back up.' 'WARN' }

    $typeTag = $BackupType.ToUpper()
    $ext = if ($BackupType -eq 'Log') { 'trn' } else { 'bak' }

    foreach ($db in $targets) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $dbFolder = Join-Path $BackupPath $db
        $file = Join-Path $dbFolder ('{0}_{1}_{2}.{3}' -f $db, $typeTag, $stamp, $ext)

        $with = @('CHECKSUM', 'INIT', 'STATS = 10', ('NAME = ' + (Get-QuotedLiteral "$db $typeTag backup $stamp")))
        if (-not $NoCompression) { $with += 'COMPRESSION' }
        if ($CopyOnly) { $with += 'COPY_ONLY' }
        if ($BackupType -eq 'Diff') { $with += 'DIFFERENTIAL' }
        $verb = if ($BackupType -eq 'Log') { 'BACKUP LOG' } else { 'BACKUP DATABASE' }
        $sqlBackup = '{0} {1} TO DISK = {2} WITH {3}' -f $verb, (Get-QuotedName $db), (Get-QuotedLiteral $file), ($with -join ', ')

        if (-not $PSCmdlet.ShouldProcess("$SqlInstance / $db", "$typeTag backup to $file")) { continue }

        try {
            # Let SQL Server create the folder (the service account is the one that writes there).
            [void](Invoke-Sql ("EXEC master.dbo.xp_create_subdir {0}" -f (Get-QuotedLiteral $dbFolder)))
            Write-Log "$db : $verb -> $file"
            $sw = [Diagnostics.Stopwatch]::StartNew()
            [void](Invoke-Sql $sqlBackup $CommandTimeoutSeconds)
            Write-Log ("$db : backup finished in {0:N0} s" -f $sw.Elapsed.TotalSeconds) 'OK'

            if (-not $SkipVerify) {
                [void](Invoke-Sql ("RESTORE VERIFYONLY FROM DISK = {0} WITH CHECKSUM" -f (Get-QuotedLiteral $file)) $CommandTimeoutSeconds)
                Write-Log "$db : RESTORE VERIFYONLY OK" 'OK'
            } else {
                Write-Log "$db : verify skipped (-SkipVerify)" 'WARN'
            }
        } catch {
            $failed++
            Write-Log ("$db : FAILED - {0}. Retention is skipped for this database." -f $_.Exception.Message) 'ERROR'
            continue
        }

        # ---- retention: only our own file pattern, only after a verified backup ------------------
        if ($RetentionDays -le 0) { continue }
        if (-not (Test-Path -LiteralPath $dbFolder)) {
            Write-Log "$db : retention skipped - '$dbFolder' is not reachable from this machine" 'WARN'
            continue
        }
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        $rx = '^' + [regex]::Escape($db) + '_' + $typeTag + '_\d{8}_\d{6}\.' + $ext + '$'
        $old = Get-ChildItem -LiteralPath $dbFolder -File |
            Where-Object { $_.Name -match $rx -and $_.LastWriteTime -lt $cutoff -and $_.FullName -ne $file }
        foreach ($f in $old) {
            if ($PSCmdlet.ShouldProcess($f.FullName, 'Remove old backup')) {
                try {
                    Remove-Item -LiteralPath $f.FullName -Force
                    Write-Log ("$db : removed old backup {0} ({1:yyyy-MM-dd})" -f $f.Name, $f.LastWriteTime)
                } catch {
                    Write-Log ("$db : could not remove {0}: {1}" -f $f.Name, $_.Exception.Message) 'WARN'
                }
            }
        }
    }
} finally {
    $connection.Close()
}

if ($failed -gt 0) {
    Write-Log "=== Finished with $failed failure(s). Log: $LogPath" 'ERROR'
    exit 1
}
Write-Log "=== Finished OK. Log: $LogPath" 'OK'
exit 0
