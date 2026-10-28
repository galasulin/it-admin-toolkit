<#
.SYNOPSIS
    Backs up the current user's Outlook data folders (signatures, roaming settings, local data files)
    to a backup folder, with a restore guide next to the copy.

.DESCRIPTION
    Copies three folders of the current user to <Destination>\<UserName>\ :
      Signatures   <- %APPDATA%\Microsoft\Signatures
      Outlook      <- %APPDATA%\Microsoft\Outlook           (NK2/streams, rules export, templates...)
      AppDataLocal <- %LOCALAPPDATA%\Microsoft\Outlook      (OST / PST data files)
    Writes _Readme.txt with the restore steps (where each folder goes back to).
    Outlook must be closed (the data files are locked while it runs); the script checks for it.
    Uses robocopy (restartable, keeps timestamps) and writes a robocopy log per folder.

    Typical use: before re-imaging or replacing a user's PC, or before rebuilding an Outlook profile.

.PARAMETER Destination
    Backup root, e.g. '\\<FILE_SERVER>\<SHARE>\OutlookBackup' or 'E:\OutlookBackup'.
    A sub-folder named after the user is created inside it.

.PARAMETER IncludeOst
    Also copy *.ost files. OST files are a cache that Exchange / Microsoft 365 rebuilds, and they can
    be very large, so they are skipped by default. PST files are always copied.

.PARAMETER Force
    Do not wait for Outlook to be closed (files in use will be reported as failed by robocopy).

.EXAMPLE
    .\Backup-OutlookData.ps1 -Destination '\\<FILE_SERVER>\<SHARE>\OutlookBackup'

.EXAMPLE
    .\Backup-OutlookData.ps1 -Destination 'E:\OutlookBackup' -IncludeOst -WhatIf

.NOTES
    Requirements : Windows PowerShell 5.1+, run as the user whose data is backed up (no admin needed),
                   write access to the destination.
    Safety       : read-only on the source; writes only under <Destination>\<UserName>. PST files may
                   contain sensitive mail - keep the destination access-controlled.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [switch]$IncludeOst,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

if (-not $Force) {
    while (Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue) {
        Write-Host 'Outlook is running. Please close Outlook, then press Enter (Ctrl+C to cancel)...' -ForegroundColor Yellow
        [void](Read-Host)
    }
}

$target = Join-Path $Destination $env:USERNAME
$sets = @(
    @{ Name = 'Signatures';   Source = Join-Path $env:APPDATA 'Microsoft\Signatures';    Restore = '%APPDATA%\Microsoft\Signatures' },
    @{ Name = 'Outlook';      Source = Join-Path $env:APPDATA 'Microsoft\Outlook';       Restore = '%APPDATA%\Microsoft\Outlook' },
    @{ Name = 'AppDataLocal'; Source = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook';  Restore = '%LOCALAPPDATA%\Microsoft\Outlook' }
)

if (-not $PSCmdlet.ShouldProcess($target, 'Copy Outlook data folders')) {
    foreach ($s in $sets) { Write-Host ("Would copy {0} -> {1}" -f $s.Source, (Join-Path $target $s.Name)) }
    return
}

New-Item -ItemType Directory -Path $target -Force | Out-Null
$failed = 0
foreach ($s in $sets) {
    if (-not (Test-Path -LiteralPath $s.Source)) { Write-Host ("skip (not found): {0}" -f $s.Source) -ForegroundColor DarkGray; continue }
    $dest = Join-Path $target $s.Name
    $log = Join-Path $target ("robocopy-{0}.log" -f $s.Name)
    $rcArgs = @($s.Source, $dest, '/E', '/COPY:DAT', '/R:1', '/W:2', '/NP', "/LOG:$log")
    if (-not $IncludeOst) { $rcArgs += @('/XF', '*.ost') }
    Write-Host ("Copying {0} ..." -f $s.Name) -ForegroundColor Cyan
    & robocopy.exe @rcArgs | Out-Null
    # robocopy: 0-7 = success (with or without copies), 8+ = at least one failure
    if ($LASTEXITCODE -ge 8) { $failed++; Write-Host ("  FAILED (robocopy exit {0}) - see {1}" -f $LASTEXITCODE, $log) -ForegroundColor Red }
    else { Write-Host ("  OK (robocopy exit {0})" -f $LASTEXITCODE) -ForegroundColor Green }
}

$readme = @(
    ('Outlook data backup of user "{0}" on computer "{1}" - {2}' -f $env:USERNAME, $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm')),
    ('-' * 79),
    'To restore, close Outlook and copy each folder back:'
)
foreach ($s in $sets) { $readme += ('  {0,-13} -> {1}' -f $s.Name, $s.Restore) }
if (-not $IncludeOst) { $readme += 'OST files were not copied (Outlook re-downloads them from the server).' }
$readme | Set-Content -Path (Join-Path $target '_Readme.txt') -Encoding UTF8

Write-Host ''
if ($failed) { Write-Host "Finished with $failed failed folder(s). Backup: $target" -ForegroundColor Yellow; exit 1 }
Write-Host "Outlook backup finished: $target" -ForegroundColor Green
