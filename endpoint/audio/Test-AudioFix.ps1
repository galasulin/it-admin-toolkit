<#
.SYNOPSIS
    Verifies what really changed after Repair-AudioStutter.ps1 -Apply, with a PASS / FAIL per check.

.DESCRIPTION
    Read-only. Checks: last boot time (was the PC restarted after the fix?), NahimicService state,
    Nahimic devices disabled, Fast Startup off, minimum processor state on battery, the engine format,
    Enhancements and remaining APO chain of each active playback endpoint, and audio / PnP errors in the
    System log since the last boot. Writes VerifyAudio_<date>.txt.

.PARAMETER OutputFolder
    Where the report is written. Default: the Desktop.

.PARAMETER ExpectedDcMinPercent
    Minimum processor state on battery that counts as PASS. Default: 20.

.EXAMPLE
    .\Test-AudioFix.ps1

.NOTES
    Requirements : Windows 10/11, Windows PowerShell 5.1; run as Administrator for complete results.
    Safety       : read-only.
    Author       : Gal Asulin
#>
[CmdletBinding()]
param(
    [string]$OutputFolder,
    [int]$ExpectedDcMinPercent = 20
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$stamp   = Get-Date -Format 'yyyy-MM-dd_HHmm'
$desktop = ''
try { $desktop = [Environment]::GetFolderPath('Desktop') } catch { }
foreach ($cand in @($OutputFolder, $desktop, $env:USERPROFILE, $env:TEMP, $PSScriptRoot, '.')) {
    if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand)) { $desktop = $cand ; break }
}
$OutFile = Join-Path $desktop ("VerifyAudio_{0}.txt" -f $stamp)

$SB = New-Object System.Text.StringBuilder
function W { param([string]$t='') ; [void]$SB.AppendLine($t) ; Write-Host $t }
function Sec { param($t) ; W '' ; W ('--- ' + $t + ' ---') }

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

W "VERIFY AUDIO FIX"
W ("Generated : {0}" -f (Get-Date))
W ("Elevated  : {0}" -f $isAdmin)

# ---------------------------------------------------------------
Sec '0. Was the computer restarted since the fix?'
try {
    $lb = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    W ("  Last boot : {0}   ({1:N1} hours ago)" -f $lb, ((Get-Date)-$lb).TotalHours)
    W "  >> if this is before the fix - restart before drawing conclusions."
} catch { W ("  ERROR: {0}" -f $_.Exception.Message) }

# ---------------------------------------------------------------
Sec '1. NahimicService   (expected: Stopped / Disabled)'
try {
    $svc = Get-Service NahimicService -ErrorAction Stop
    W ("  Status={0}   StartType={1}" -f $svc.Status, $svc.StartType)
    if ($svc.Status -eq 'Stopped' -and $svc.StartType -eq 'Disabled') { W '  >> PASS' }
    else { W '  >> FAIL - the service is still active' }
} catch { W '  service not present (removed completely) >> PASS' }

# ---------------------------------------------------------------
Sec '2. Nahimic devices   (expected: Error / CM_PROB_DISABLED)'
try {
    $devs = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like '*NAHIMIC*' -or $_.InstanceId -like '*AVOLUTE*' }
    if (-not $devs) { W '  no Nahimic devices found >> PASS' }
    else {
        $bad = 0
        foreach ($d in $devs) {
            W ("  {0,-9} {1,-24} {2,-45} {3}" -f $d.Status, $d.Class, $d.FriendlyName, $d.ConfigManagerErrorCode)
            if ($d.Status -eq 'OK') { $bad++ }
        }
        if ($bad -eq 0) { W '  >> PASS - all devices disabled' }
        else { W ("  >> FAIL - {0} device(s) still enabled" -f $bad) }
    }
} catch { W ("  ERROR: {0}" -f $_.Exception.Message) }

# ---------------------------------------------------------------
Sec '3. Fast Startup   (expected: 0)'
try {
    $hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
           -Name HiberbootEnabled -ErrorAction Stop).HiberbootEnabled
    W ("  HiberbootEnabled = {0}" -f $hb)
    W $(if ($hb -eq 0) { '  >> PASS' } else { '  >> FAIL' })
} catch { W ("  ERROR: {0}" -f $_.Exception.Message) }

# ---------------------------------------------------------------
Sec ("4. Minimum processor state   (expected: DC >= {0}%)" -f $ExpectedDcMinPercent)
try {
    $raw = (powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN) 2>&1 | Out-String
    $hex = [regex]::Matches($raw, '0x[0-9a-fA-F]{2,}')
    if ($hex.Count -ge 2) {
        $ac = [Convert]::ToInt64($hex[$hex.Count-2].Value,16)
        $dc = [Convert]::ToInt64($hex[$hex.Count-1].Value,16)
        W ("  AC={0}%   DC={1}%" -f $ac, $dc)
        W $(if ($dc -ge $ExpectedDcMinPercent) { '  >> PASS' } else { '  >> FAIL - DC is still low' })
    } else { W '  could not read the value' }
} catch { W ("  ERROR: {0}" -f $_.Exception.Message) }

# ---------------------------------------------------------------
Sec '5. Active endpoints - format + Enhancements + APO chain'
# Scan the blob for a known sample rate instead of assuming a fixed offset
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
        if ($ch -ge 1 -and $ch -le 8 -and @(8,16,24,32) -contains $bd) {
            if ([math]::Abs([int64]$ab - [int64]($sr*$ch*($bd/8))) -le 4) {
                return ("{0} Hz / {1}-bit / {2} ch" -f $sr, $bd, $ch)
            }
        }
    }
    return 'could not decode'
}
try {
    $rootR = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    $found = 0
    foreach ($ep in (Get-ChildItem $rootR -ErrorAction SilentlyContinue)) {
        $raw = (Get-ItemProperty -Path $ep.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
        if ($null -eq $raw) { continue }
        if (([int]$raw -band 0xFFFF) -ne 1) { continue }
        $p = Get-ItemProperty -Path (Join-Path $ep.PSPath 'Properties') -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        $found++
        $nm = $p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
        if (-not $nm) { $nm = $p.'{a45c254e-df1c-4efd-8020-67d146a850e0},2' }
        $fmt = 'n/a'
        try { $fmt = Read-EngineFormat ([byte[]]$p.'{f19f064d-082c-4e27-bc73-6882a1bb8e4c},0') } catch { }
        $sysfx = $p.'{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5'
        W ""
        W ("  {0}" -f $nm)
        W ("      format       : {0}" -f $fmt)
        W ("      DisableSysFx : {0}   ({1})" -f $sysfx, $(if ($sysfx -eq 1) {'Enhancements OFF >> PASS'} else {'Enhancements ON  >> still needs to be turned off in Settings'}))
        # the APO chain that is actually left
        $fx = Join-Path $ep.PSPath 'FxProperties'
        if (Test-Path $fx) {
            $fxp = Get-ItemProperty $fx -ErrorAction SilentlyContinue
            $apoList = $fxp.PSObject.Properties |
                Where-Object { $_.Name -notlike 'PS*' -and $_.Value -is [string] -and $_.Value -like 'SWD\DRIVERENUM\*' }
            if ($apoList) {
                W "      APO chain    :"
                foreach ($a in $apoList) { W ("          {0}" -f $a.Value) }
            } else { W "      APO chain    : (none)" }
        } else { W "      APO chain    : no FxProperties" }
    }
    if ($found -eq 0) { W '  no active playback endpoint found' }
} catch { W ("  ERROR: {0}" -f $_.Exception.Message) }

# ---------------------------------------------------------------
Sec '6. audiodg + audio errors in the System log since boot'
try {
    $adg = Get-Process audiodg -ErrorAction SilentlyContinue
    if ($adg) { W ("  audiodg PID {0}  CPU {1:N1}s  Threads {2}" -f $adg.Id, $adg.CPU, $adg.Threads.Count) }
    else { W '  audiodg is not running (nothing is playing right now)' }
} catch { W ("  ERROR: {0}" -f $_.Exception.Message) }
try {
    $lb = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $ev = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=$lb} -MaxEvents 60 -ErrorAction Stop |
          Where-Object { $_.ProviderName -match 'Audio|Kernel-Pnp|Nahimic|Realtek' }
    if ($ev) { foreach ($e in $ev) { W ("  {0}  ID {1}  {2}" -f $e.TimeCreated, $e.Id, $e.ProviderName) } }
    else { W '  no audio / PnP errors since boot >> good' }
} catch { W '  (the event log could not be read)' }

W ''
W '=== END ==='
try {
    $SB.ToString() | Out-File -FilePath $OutFile -Encoding UTF8
    Write-Host ''
    Write-Host "Saved: $OutFile" -ForegroundColor Green
} catch { Write-Host "Could not write the report: $($_.Exception.Message)" -ForegroundColor Red }
