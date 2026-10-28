<#
.SYNOPSIS
    Neutralises the Nahimic audio-processing chain and the secondary causes of audio stutter - reversibly.

.DESCRIPTION
    Three modes:
      .\Repair-AudioStutter.ps1             -> report only, changes nothing
      .\Repair-AudioStutter.ps1 -Apply      -> applies the fix
      .\Repair-AudioStutter.ps1 -Rollback   -> puts everything back

    What -Apply does (all of it reversible with -Rollback):
      1. NahimicService                         -> stopped + startup type Disabled
      2. Nahimic / Avolute devices (mirroring, VAD, Easy Surround, APO) -> Disable-PnpDevice
      3. Fast Startup                           -> off (stops a stuck driver state surviving "shutdown")
      4. Minimum processor state on battery     -> raised (default 5% -> 20%) so the audio buffer
                                                   is not starved when the laptop is unplugged

    What it does NOT do: uninstall software, touch the Realtek driver, or delete anything.
    Turning off "Audio enhancements" itself must be done in Settings > System > Sound: the MMDevices
    registry keys are owned by SYSTEM and even administrators are denied.

    Section A also prints the real engine format of each active playback endpoint. The registry blob is
    wrapped in a PROPVARIANT header, so instead of a fixed offset the blob is scanned for a known
    sample rate and cross-checked against nAvgBytesPerSec.

.PARAMETER Apply
    Apply the changes.

.PARAMETER Rollback
    Revert the changes.

.PARAMETER DcMinProcessorPercent
    Minimum processor state on battery set by -Apply. Default: 20.

.PARAMETER DcMinProcessorRollbackPercent
    Value restored by -Rollback. Default: 5 (the Windows "Balanced" default).

.EXAMPLE
    .\Repair-AudioStutter.ps1

.EXAMPLE
    .\Repair-AudioStutter.ps1 -Apply -WhatIf

.EXAMPLE
    .\Repair-AudioStutter.ps1 -Rollback

.NOTES
    Requirements : Windows 10/11, run as Administrator. Restart after -Apply / -Rollback.
    Safety       : changes a service, PnP devices, Fast Startup and the active power plan. Use -Rollback to undo.
                   Verify afterwards with Test-AudioFix.ps1.
    Author       : Gal Asulin
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Apply,
    [switch]$Rollback,
    [ValidateRange(0, 100)][int]$DcMinProcessorPercent = 20,
    [ValidateRange(0, 100)][int]$DcMinProcessorRollbackPercent = 5
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

function OK   { param($m) Write-Host "  [OK]    $m" -ForegroundColor Green }
function INFO { param($m) Write-Host "  [INFO]  $m" -ForegroundColor Cyan }
function WARN { param($m) Write-Host "  [WARN]  $m" -ForegroundColor Yellow }
function FAIL { param($m) Write-Host "  [FAIL]  $m" -ForegroundColor Red }
function Head { param($m) Write-Host "" ; Write-Host ("=== $m ===") -ForegroundColor White }

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { FAIL 'Run this script as Administrator (Terminal (Admin)). Exiting.' ; return }

if ($Apply -and $Rollback) { FAIL '-Apply and -Rollback cannot be used together.' ; return }
$mode = if ($Apply) { 'APPLY' } elseif ($Rollback) { 'ROLLBACK' } else { 'REPORT ONLY' }
Write-Host ""
Write-Host "MODE: $mode" -ForegroundColor Magenta

# =====================================================================
Head 'A. Engine format of every active playback endpoint'
# =====================================================================
$knownRates = @(8000,11025,16000,22050,32000,44100,48000,88200,96000,176400,192000)

function Read-EngineFormat {
    param([byte[]]$Blob)
    if (-not $Blob -or $Blob.Length -lt 20) { return 'n/a' }
    for ($off = 0; $off -le $Blob.Length - 16; $off++) {
        $sr = [BitConverter]::ToUInt32($Blob, $off + 4)
        if ($knownRates -notcontains $sr) { continue }
        $ch = [BitConverter]::ToUInt16($Blob, $off + 2)
        $bd = [BitConverter]::ToUInt16($Blob, $off + 14)
        $ab = [BitConverter]::ToUInt32($Blob, $off + 8)
        # cross-check: nAvgBytesPerSec must equal sampleRate * channels * bits / 8
        if ($ch -ge 1 -and $ch -le 8 -and @(8,16,24,32) -contains $bd) {
            $expect = $sr * $ch * ($bd / 8)
            if ([math]::Abs([int64]$ab - [int64]$expect) -le 4) {
                return ("{0} Hz / {1}-bit / {2} ch   [header offset {3}]" -f $sr, $bd, $ch, $off)
            }
        }
    }
    return 'could not decode'
}

$stateMask = 0xFFFF   # the high bits of DeviceState are flags, not the state
$rootR = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
foreach ($ep in (Get-ChildItem $rootR -ErrorAction SilentlyContinue)) {
    $raw = (Get-ItemProperty -Path $ep.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
    if ($null -eq $raw) { continue }
    if (([int]$raw -band $stateMask) -ne 1) { continue }   # truly ACTIVE only
    $p = Get-ItemProperty -Path (Join-Path $ep.PSPath 'Properties') -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    $nm = $p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
    if (-not $nm) { $nm = $p.'{a45c254e-df1c-4efd-8020-67d146a850e0},2' }
    $fmt = 'n/a'
    try { $fmt = Read-EngineFormat ([byte[]]$p.'{f19f064d-082c-4e27-bc73-6882a1bb8e4c},0') } catch { }
    $sysfx = $p.'{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5'
    $enh   = if ($sysfx -eq 1) { 'Enhancements DISABLED' } else { 'Enhancements ENABLED  <-- turn off in Settings' }
    INFO ("{0}" -f $nm)
    INFO ("    format: {0}" -f $fmt)
    INFO ("    {0}" -f $enh)
}

# =====================================================================
Head 'B. Nahimic service'
# =====================================================================
$svc = Get-Service NahimicService -ErrorAction SilentlyContinue
if (-not $svc) {
    INFO 'NahimicService is not installed.'
} else {
    INFO ("Current: {0} / StartType {1}" -f $svc.Status, $svc.StartType)
    if ($Apply -and $PSCmdlet.ShouldProcess('NahimicService', 'Stop and set startup type Disabled')) {
        try {
            if ($svc.Status -eq 'Running') { Stop-Service NahimicService -Force -ErrorAction Stop }
            Set-Service NahimicService -StartupType Disabled -ErrorAction Stop
            OK 'NahimicService stopped and set to Disabled'
        } catch { FAIL ("NahimicService: {0}" -f $_.Exception.Message) }
    }
    if ($Rollback -and $PSCmdlet.ShouldProcess('NahimicService', 'Set startup type Automatic and start')) {
        try {
            Set-Service NahimicService -StartupType Automatic -ErrorAction Stop
            Start-Service NahimicService -ErrorAction Stop
            OK 'NahimicService back to Automatic and running'
        } catch { FAIL ("NahimicService: {0}" -f $_.Exception.Message) }
    }
}

# =====================================================================
Head 'C. Nahimic devices in Device Manager'
# =====================================================================
# Filter on InstanceId, not on the friendly name - the name changes between versions and languages.
$nahimicPatterns = @('*NAHIMIC*', '*AVOLUTE*')
$devs = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $id = $_.InstanceId
    ($nahimicPatterns | Where-Object { $id -like $_ }).Count -gt 0
}

if (-not $devs) {
    INFO 'No Nahimic devices found.'
} else {
    foreach ($d in $devs) {
        INFO ("{0,-10} {1,-22} {2}" -f $d.Status, $d.Class, $d.FriendlyName)
    }
    if ($Apply) {
        foreach ($d in $devs) {
            if ($d.Status -ne 'OK') { continue }
            if (-not $PSCmdlet.ShouldProcess($d.FriendlyName, 'Disable device')) { continue }
            try {
                Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
                OK ("disabled: {0}" -f $d.FriendlyName)
            } catch { FAIL ("{0}: {1}" -f $d.FriendlyName, $_.Exception.Message) }
        }
    }
    if ($Rollback) {
        foreach ($d in $devs) {
            if (-not $PSCmdlet.ShouldProcess($d.FriendlyName, 'Enable device')) { continue }
            try {
                Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
                OK ("enabled: {0}" -f $d.FriendlyName)
            } catch { FAIL ("{0}: {1}" -f $d.FriendlyName, $_.Exception.Message) }
        }
    }
}

# =====================================================================
Head 'D. Fast Startup'
# =====================================================================
$pwrKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
$hb = (Get-ItemProperty $pwrKey -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
INFO ("HiberbootEnabled = {0}  (1 = on)" -f $hb)
if ($Apply -and $PSCmdlet.ShouldProcess('Fast Startup', 'Turn off')) {
    try { Set-ItemProperty $pwrKey -Name HiberbootEnabled -Value 0 -Type DWord -ErrorAction Stop
          OK 'Fast Startup turned off' } catch { FAIL $_.Exception.Message }
}
if ($Rollback -and $PSCmdlet.ShouldProcess('Fast Startup', 'Turn on')) {
    try { Set-ItemProperty $pwrKey -Name HiberbootEnabled -Value 1 -Type DWord -ErrorAction Stop
          OK 'Fast Startup turned back on' } catch { FAIL $_.Exception.Message }
}

# =====================================================================
Head 'E. Minimum processor state on battery'
# =====================================================================
# Typical finding: AC = 100% but DC = 5%. Unplugged, the CPU drops so low that the audio buffer
# is not refilled in time - which explains "random" stutter on laptops.
function Get-DcMin {
    $raw = (powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN) 2>&1 | Out-String
    $hex = [regex]::Matches($raw, '0x[0-9a-fA-F]{2,}')
    if ($hex.Count -ge 2) { return [Convert]::ToInt64($hex[$hex.Count-1].Value, 16) }
    return $null
}
INFO ("DC minimum processor state = {0}%" -f (Get-DcMin))
if ($Apply -and $PSCmdlet.ShouldProcess('Active power plan', "Set DC minimum processor state to $DcMinProcessorPercent%")) {
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN $DcMinProcessorPercent | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    OK ("raised to {0}%" -f (Get-DcMin))
}
if ($Rollback -and $PSCmdlet.ShouldProcess('Active power plan', "Set DC minimum processor state to $DcMinProcessorRollbackPercent%")) {
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN $DcMinProcessorRollbackPercent | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    OK ("restored to {0}%" -f (Get-DcMin))
}

# =====================================================================
Head 'Summary'
# =====================================================================
if (-not $Apply -and -not $Rollback) {
    Write-Host "  Report only. To apply:" -ForegroundColor Yellow
    Write-Host "      .\Repair-AudioStutter.ps1 -Apply" -ForegroundColor Yellow
} elseif ($Apply) {
    Write-Host ""
    Write-Host "  Done. Next:" -ForegroundColor Green
    Write-Host "   1. Settings > System > Sound > (your speakers) >" -ForegroundColor Green
    Write-Host "      Audio enhancements = Off , Spatial audio = Off" -ForegroundColor Green
    Write-Host "   2. Restart the computer (important - Fast Startup was on)." -ForegroundColor Green
    Write-Host "   3. Use the PC normally for a day or two, then run Test-AudioFix.ps1." -ForegroundColor Green
    Write-Host ""
    Write-Host "  To undo: .\Repair-AudioStutter.ps1 -Rollback" -ForegroundColor Yellow
} else {
    Write-Host "  Restored to the original state. Restart the computer." -ForegroundColor Green
}
Write-Host ""
