<#
.SYNOPSIS
    Repairs a stuck Windows Update: stops the update services, renames the SoftwareDistribution and
    catroot2 caches, restarts the services and optionally repairs the component store.

.DESCRIPTION
    The standard fix for updates that fail repeatedly, hang at "Downloading 0%" or report
    error codes such as 0x80070002 / 0x8024xxxx:

      1. stops wuauserv, bits, cryptsvc, msiserver (and UsoSvc / dosvc when present)
      2. renames  %windir%\SoftwareDistribution  -> SoftwareDistribution.old-<timestamp>
                  %windir%\System32\catroot2      -> catroot2.old-<timestamp>
         (renamed, not deleted - so it can be undone; -CleanOld removes older .old-* copies)
      3. starts the services again
      4. -RepairImage : DISM /Online /Cleanup-Image /RestoreHealth, then sfc /scannow
      5. -ScanNow     : asks Windows Update to scan again (UsoClient StartScan)
      -StopOnly       : just stops Windows Update (wuauserv + bits) and does nothing else,
                        e.g. to free bandwidth or before a manual install.

    Everything is logged to %windir%\Logs\Reset-WindowsUpdate_<timestamp>.log.

.PARAMETER RepairImage
    Also run DISM RestoreHealth and SFC (takes 10-30 minutes).

.PARAMETER ScanNow
    Start an update scan when finished.

.PARAMETER CleanOld
    Delete SoftwareDistribution.old-* / catroot2.old-* folders left by earlier runs.

.PARAMETER StopOnly
    Only stop the Windows Update and BITS services.

.EXAMPLE
    .\Reset-WindowsUpdate.ps1 -WhatIf

.EXAMPLE
    .\Reset-WindowsUpdate.ps1 -RepairImage -ScanNow

.EXAMPLE
    .\Reset-WindowsUpdate.ps1 -StopOnly

.NOTES
    Requirements : run as Administrator; Windows 10 / 11 / Server 2016+.
    Safety       : clears the update download cache and the update history shown in Settings (the
                   installed updates themselves are not touched). Renamed folders can be renamed back.
                   Do not run while an update is being installed.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$RepairImage,
    [switch]$ScanNow,
    [switch]$CleanOld,
    [switch]$StopOnly
)
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this script as Administrator.' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path $env:windir "Logs\Reset-WindowsUpdate_$stamp.log"
function Log([string]$m, [string]$color = 'Gray') {
    $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line -ForegroundColor $color
    if (-not $WhatIfPreference) { Add-Content -Path $log -Value $line -Encoding UTF8 }
}

$services = @('wuauserv', 'bits', 'cryptsvc', 'msiserver', 'UsoSvc', 'dosvc') |
    Where-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue }
if ($StopOnly) { $services = @('wuauserv', 'bits') }

# ---- 1. stop ----
foreach ($s in $services) {
    if ($PSCmdlet.ShouldProcess($s, 'Stop service')) {
        try { Stop-Service -Name $s -Force -ErrorAction Stop; Log "stopped  $s" }
        catch { Log ("could not stop {0}: {1}" -f $s, $_.Exception.Message) 'Yellow' }
    }
}
if ($StopOnly) { Log 'Windows Update and BITS are stopped (they start again on demand or after a restart).' 'Green'; return }

# ---- 2. rename caches ----
$folders = @((Join-Path $env:windir 'SoftwareDistribution'), (Join-Path $env:windir 'System32\catroot2'))
foreach ($f in $folders) {
    if (-not (Test-Path $f)) { Log "not found: $f"; continue }
    $newName = '{0}.old-{1}' -f (Split-Path $f -Leaf), $stamp
    if ($PSCmdlet.ShouldProcess($f, "Rename to $newName")) {
        try { Rename-Item -Path $f -NewName $newName -ErrorAction Stop; Log "renamed  $f -> $newName" 'Green' }
        catch { Log ("could not rename {0}: {1} (a service may still hold it - restart and run again)" -f $f, $_.Exception.Message) 'Red' }
    }
}

if ($CleanOld) {
    foreach ($parent in @($env:windir, (Join-Path $env:windir 'System32'))) {
        Get-ChildItem -Path $parent -Directory -Filter '*.old-*' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^(SoftwareDistribution|catroot2)\.old-\d{8}_\d{6}$' -and $_.Name -notlike "*$stamp" } |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.FullName, 'Delete old cache copy')) {
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    Log "deleted  $($_.FullName)"
                }
            }
    }
}

# ---- 3. start ----
foreach ($s in @('cryptsvc', 'bits', 'wuauserv') + ($services | Where-Object { $_ -in 'UsoSvc', 'dosvc' })) {
    if ($PSCmdlet.ShouldProcess($s, 'Start service')) {
        try { Start-Service -Name $s -ErrorAction Stop; Log "started  $s" }
        catch { Log ("could not start {0}: {1}" -f $s, $_.Exception.Message) 'Yellow' }
    }
}

# ---- 4. component store ----
if ($RepairImage -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'DISM RestoreHealth + SFC')) {
    Log 'DISM /Online /Cleanup-Image /RestoreHealth ...' 'Cyan'
    & dism.exe /Online /Cleanup-Image /RestoreHealth
    Log "DISM exit code $LASTEXITCODE"
    Log 'sfc /scannow ...' 'Cyan'
    & sfc.exe /scannow
    Log "SFC exit code $LASTEXITCODE"
}

# ---- 5. scan ----
if ($ScanNow -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Start Windows Update scan')) {
    $uso = Join-Path $env:windir 'System32\UsoClient.exe'
    if (Test-Path $uso) { & $uso StartScan; Log 'update scan requested' 'Green' }
}

Log "Done. Log: $log. A restart is recommended." 'Green'
