<#
.SYNOPSIS
    Grandfather-father-son retention for SQL Server backup folders (default: 10 daily, 4 weekly, 3 monthly).
    Dry run by default - nothing is deleted without -Apply.

.DESCRIPTION
    Classifies the files in each backup root PER DATABASE and PER BACKUP TYPE instead of simply
    "keeping the newest N files in the folder":

      * LOG backups (*.trn or names containing _LOG_) are NEVER touched by any switch.
        A folder often holds many more log backups than full backups; a naive "keep newest N files"
        would delete the whole point-in-time recovery chain. Log retention belongs to the job that
        writes the logs.
      * DAILY tier  : full backups in the root folder, grouped per database, newest -KeepDaily kept.
      * WEEKLY tier : files in <root>\weekly, newest -KeepWeekly kept.
      * MONTHLY tier: files in <root>\monthly, newest -KeepMonthly kept.
      * A file whose name is not recognised is never a deletion candidate (it is listed instead).
      * "Newest" is LastWriteTimeUtc, never the date in the file name (a re-copied file keeps an old name).
      * A root that is missing is REPORTED, not silently skipped - "nothing to clean" and "wrong path"
        must not look the same.

    Recognised full-backup names:
      <db>_FULL_<digits>...       (e.g. Sales_FULL_20260101_010000.bak - see Backup-SqlDatabases.ps1)
      SYSTEM_<db>_<digits>...
      <db>_yyyyMMdd_HHmmss.bak

.PARAMETER Root
    One or more backup roots, e.g. '\\<FILE_SERVER>\<BACKUP_SHARE>\<APP>'. Mandatory.

.PARAMETER KeepDaily
    Daily full backups to keep per database. Default: 10.

.PARAMETER KeepWeekly
    Files to keep in <root>\weekly. Default: 4.

.PARAMETER KeepMonthly
    Files to keep in <root>\monthly. Default: 3.

.PARAMETER Apply
    Actually delete the surplus files. Requires -IAmSure as well. Supports -WhatIf / -Confirm.

.PARAMETER IAmSure
    Second switch required together with -Apply (a deleted backup has no undo).

.EXAMPLE
    .\Invoke-BackupRetention.ps1 -Root '\\<FILE_SERVER>\<BACKUP_SHARE>\Sales'

    Dry run: shows what would be kept and what would be removed.

.EXAMPLE
    .\Invoke-BackupRetention.ps1 -Root 'E:\SQLBackup\Sales' -KeepDaily 14 -Apply -IAmSure

.NOTES
    Requirements : Windows PowerShell 5.1+, delete rights on the backup folders when -Apply is used.
    Safety       : DELETES backup files when -Apply -IAmSure is given. Always run the dry run first;
                   the files listed as KEEPS are the undo for everything else.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Root,
    [int]$KeepDaily = 10,
    [int]$KeepWeekly = 4,
    [int]$KeepMonthly = 3,
    [switch]$Apply,
    [switch]$IAmSure
)
$ErrorActionPreference = 'Stop'

if ($Apply -and -not $IAmSure) {
    Write-Host 'REFUSED: -Apply needs -IAmSure as well. Run with neither to see the list first.'
    exit 2
}

function Test-IsLogBackup([string]$Name) { return ($Name -match '_LOG_') -or ($Name -like '*.trn') }

function Get-BackupSet([string]$Name) {
    if ($Name -match '^(?<db>.+?)_FULL_\d') { return $Matches['db'] }
    if ($Name -match '^SYSTEM_(?<db>[A-Za-z]+)_\d') { return 'SYSTEM_' + $Matches['db'] }
    if ($Name -match '^(?<db>.+?)_\d{8}_\d{6}\.bak$') { return $Matches['db'] }
    return $null   # unrecognised: never a deletion candidate
}

$script:grandSurplus = 0
$script:grandBytes = 0
$unrecognised = @()

function Show-Tier($Label, $Files, $Keep) {
    $sorted = @($Files | Sort-Object LastWriteTimeUtc -Descending)
    $surplus = @($sorted | Select-Object -Skip $Keep)
    $bytes = 0; if ($surplus.Count) { $bytes = ($surplus | Measure-Object Length -Sum).Sum }
    Write-Host ("    {0,-22} {1,4} present | keep {2,2} | SURPLUS {3,4} ({4:N1} MB)" -f $Label, $sorted.Count, $Keep, $surplus.Count, ($bytes / 1MB))
    if ($sorted.Count -gt 0) {
        $kept = @($sorted | Select-Object -First $Keep)
        if ($kept.Count) {
            Write-Host ("        KEEPS newest {0:yyyy-MM-dd HH:mm} .. oldest kept {1:yyyy-MM-dd HH:mm}" -f $kept[0].LastWriteTimeUtc, $kept[-1].LastWriteTimeUtc)
        }
    }
    foreach ($f in ($surplus | Select-Object -First 5)) {
        Write-Host ("        would remove: {0}  {1:yyyy-MM-dd HH:mm}  {2:N1} MB" -f $f.Name, $f.LastWriteTimeUtc, ($f.Length / 1MB))
    }
    if ($surplus.Count -gt 5) { Write-Host ("        ... and {0} more" -f ($surplus.Count - 5)) }
    if ($Apply -and $surplus.Count -gt 0) {
        $removed = 0
        foreach ($f in $surplus) {
            if ($PSCmdlet.ShouldProcess($f.FullName, 'Remove backup file')) { Remove-Item -LiteralPath $f.FullName -Force; $removed++ }
        }
        Write-Host ("        APPLIED: removed {0} file(s)" -f $removed)
    }
    $script:grandSurplus += $surplus.Count
    $script:grandBytes += $bytes
}

foreach ($r in $Root) {
    Write-Host ''
    Write-Host "ROOT $r"
    if (-not (Test-Path -LiteralPath $r)) { Write-Host '  MISSING - not reachable from here (reported, not skipped)'; continue }

    $all = @(Get-ChildItem -LiteralPath $r -File -ErrorAction SilentlyContinue)
    $logs = @($all | Where-Object { Test-IsLogBackup $_.Name })
    $fulls = @($all | Where-Object { -not (Test-IsLogBackup $_.Name) })

    Write-Host ("  LOG backups: {0} file(s) - NEVER touched by this script (point-in-time recovery)" -f $logs.Count)
    Write-Host '  DAILY tier (root), per database:'
    foreach ($g in ($fulls | Group-Object { Get-BackupSet $_.Name } | Sort-Object Name)) {
        if ([string]::IsNullOrEmpty($g.Name)) { $unrecognised += $g.Group; continue }
        Show-Tier $g.Name $g.Group $KeepDaily
    }

    foreach ($t in @(@('weekly', $KeepWeekly), @('monthly', $KeepMonthly))) {
        $dir = Join-Path $r $t[0]
        if (-not (Test-Path -LiteralPath $dir)) { Write-Host ("  {0,-8} no {0}\ folder under this root" -f $t[0]); continue }
        Write-Host ("  {0} tier:" -f $t[0].ToUpper())
        $tf = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { -not (Test-IsLogBackup $_.Name) })
        Show-Tier $t[0] $tf $t[1]
    }
}

Write-Host ''
if ($unrecognised.Count -gt 0) {
    Write-Host ("UNRECOGNISED (left alone, on purpose): {0} file(s)" -f $unrecognised.Count)
    foreach ($f in ($unrecognised | Select-Object -First 10)) { Write-Host ("    {0}  {1:yyyy-MM-dd}" -f $f.Name, $f.LastWriteTimeUtc) }
}
Write-Host ("TOTAL surplus: {0} file(s), {1:N1} MB" -f $script:grandSurplus, ($script:grandBytes / 1MB))
if (-not $Apply) {
    Write-Host 'DRY RUN - nothing was deleted.'
}
exit 0
