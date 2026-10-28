<#
.SYNOPSIS
    Diagnoses choppy / stuttering / crackling audio on Windows 10/11 and writes everything to one report.

.DESCRIPTION
    Collects into a single text file every setting that commonly causes audio dropouts:
      1. system summary (OS build, uptime, model, BIOS, CPU, RAM)
      2. audio endpoints: engine format (sample rate / bit depth), Enhancements on/off, exclusive mode,
         and the APO effect chain (Realtek / Nahimic / Dolby / DTS ...)
      3. audio drivers and any PnP device in an error state
      4. virtual / third-party audio software, services and startup items
      5. Windows audio services and the audiodg.exe engine process
      6. power settings (processor min/max, core parking, USB selective suspend, PCIe ASPM)
      7. network / GPU / storage drivers and disk health (the usual DPC-latency offenders)
      8. a live DPC / Interrupt time measurement (-CounterSeconds) - play audio that stutters meanwhile
      9. event logs (System / Application errors, Kernel-Power, WHEA, disk, display driver resets)
     10. MMCSS, Fast Startup, memory integrity (VBS)
    The script is READ-ONLY - it changes nothing. Perf-counter names are translated, so it also works on
    non-English Windows. Pair it with Repair-AudioStutter.ps1 and Test-AudioFix.ps1.

.PARAMETER CounterSeconds
    Length of the live DPC / Interrupt sample in seconds. Default: 15.

.PARAMETER EventDays
    How many days of event logs to summarise. Default: 14.

.PARAMETER OutputFolder
    Where the report AudioDiag_<COMPUTER>_<date>.txt is written. Default: the Desktop.

.EXAMPLE
    .\Get-AudioDiagnostics.ps1

    While it samples DPC time, play a video or song that reproduces the stutter.

.EXAMPLE
    .\Get-AudioDiagnostics.ps1 -CounterSeconds 60 -EventDays 30 -OutputFolder C:\Temp

.NOTES
    Requirements : Windows 10/11, Windows PowerShell 5.1. Run as Administrator (some sections are empty otherwise).
    Safety       : read-only. The report includes the computer name, user name and installed software.
    Author       : Gal Asulin
#>

[CmdletBinding()]
param(
    [int]$CounterSeconds = 15,
    [int]$EventDays      = 14,
    [string]$OutputFolder
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ---------- output file ----------
$stamp   = Get-Date -Format 'yyyy-MM-dd_HHmm'
$desktop = ''
try { $desktop = [Environment]::GetFolderPath('Desktop') } catch { }
foreach ($cand in @($OutputFolder, $desktop, $env:USERPROFILE, $env:TEMP, $PSScriptRoot, '.')) {
    if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand)) { $desktop = $cand ; break }
}
$OutFile = Join-Path $desktop ("AudioDiag_{0}_{1}.txt" -f $env:COMPUTERNAME, $stamp)

$script:SB = New-Object System.Text.StringBuilder

function W {
    param([string]$Text = '')
    [void]$script:SB.AppendLine($Text)
    Write-Host $Text
}
function Section {
    param([string]$Title)
    W ''
    W ('=' * 74)
    W ("  $Title")
    W ('=' * 74)
}
function Sub { param([string]$T) ; W '' ; W ("--- $T ---") }

# Runs a block in isolation: one failing check does not stop the others
function Try-Do {
    param([scriptblock]$Body, [string]$Label = '')
    try { & $Body } catch { W ("  [ERROR $Label] {0}" -f $_.Exception.Message) }
}

function Out-Block {
    param($InputObject, [string]$Format = 'List')
    if ($null -eq $InputObject) { W '  (no data)' ; return }
    if (@($InputObject).Count -eq 0) { W '  (none)' ; return }
    $txt = if ($Format -eq 'Table') {
        $InputObject | Format-Table -AutoSize | Out-String -Width 300
    } else {
        $InputObject | Format-List | Out-String -Width 300
    }
    $printed = $false
    foreach ($line in ($txt -split "`r?`n")) {
        if ($line.Trim().Length -gt 0) { W ("  " + $line.TrimEnd()) ; $printed = $true }
    }
    if (-not $printed) { W '  (none)' }
}

$isAdmin = $false
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

W "AUDIO DIAGNOSTICS REPORT"
W ("Generated : {0}" -f (Get-Date))
W ("Computer  : {0}   User: {1}" -f $env:COMPUTERNAME, $env:USERNAME)
W ("Elevated  : {0}" -f $isAdmin)
W ("PS Version: {0}" -f $PSVersionTable.PSVersion)
if (-not $isAdmin) { W "!! WARNING: not running as Administrator - some sections will be empty." }

# =====================================================================
Section '1. SYSTEM'
# =====================================================================
Try-Do -Label 'system' -Body {
    $os  = Get-CimInstance Win32_OperatingSystem
    $cs  = Get-CimInstance Win32_ComputerSystem
    $bio = Get-CimInstance Win32_BIOS
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    W ("OS            : {0} (Build {1})" -f $os.Caption, $os.BuildNumber)
    W ("Installed     : {0}" -f $os.InstallDate)
    W ("Last boot     : {0}   (uptime {1:N1} h)" -f $os.LastBootUpTime, ((Get-Date) - $os.LastBootUpTime).TotalHours)
    W ("Manufacturer  : {0} / {1}" -f $cs.Manufacturer, $cs.Model)
    W ("BIOS          : {0}  {1}" -f $bio.SMBIOSBIOSVersion, $bio.ReleaseDate)
    W ("CPU           : {0}" -f $cpu.Name)
    W ("CPU cores     : {0} cores / {1} threads   Max {2} MHz / Current {3} MHz" -f `
        $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, $cpu.MaxClockSpeed, $cpu.CurrentClockSpeed)
    W ("RAM total     : {0:N1} GB   Free: {1:N1} GB" -f `
        ($cs.TotalPhysicalMemory/1GB), ($os.FreePhysicalMemory/1MB))
    W ("PCSystemType  : {0}   (2 = Mobile/Laptop)" -f $cs.PCSystemType)
}

# =====================================================================
Section '2. AUDIO ENDPOINTS (format / enhancements / exclusive mode / APO chain)'
# =====================================================================
# This is where most "choppy audio" problems live:
#   DeviceFormat  - the sample rate the engine plays at (48000 = normal; 192000 = needless load)
#   DisableSysFx  - 1 = Enhancements off (preferred), 0/missing = on (prime suspect)
#   Exclusive     - whether an application may take exclusive control of the device
#   FxProperties  - the sound-processing (APO) chain (Realtek/Nahimic/Dolby/DTS)
$stateMap = @{ 1 = 'ACTIVE'; 2 = 'DISABLED'; 4 = 'NOTPRESENT'; 8 = 'UNPLUGGED' }

function Get-AudioEndpointInfo {
    param([string]$Flow)   # Render / Capture
    $root = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$Flow"
    if (-not (Test-Path $root)) { return @() }
    $result = @()
    foreach ($ep in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
        $propPath = Join-Path $ep.PSPath 'Properties'
        $p = $null
        try { $p = Get-ItemProperty -Path $propPath -ErrorAction Stop } catch { }

        $name = $null ; $desc = $null
        if ($p) {
            $name = $p.'{a45c254e-df1c-4efd-8020-67d146a850e0},14'
            $desc = $p.'{a45c254e-df1c-4efd-8020-67d146a850e0},2'
        }
        $stateRaw = (Get-ItemProperty -Path $ep.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
        $state    = if ($null -ne $stateRaw -and $stateMap.ContainsKey([int]$stateRaw)) { $stateMap[[int]$stateRaw] } else { $stateRaw }

        # decode WAVEFORMATEXTENSIBLE
        $fmtStr = 'n/a'
        if ($p -and $p.'{f19f064d-082c-4e27-bc73-6882a1bb8e4c},0') {
            try {
                $b  = [byte[]]$p.'{f19f064d-082c-4e27-bc73-6882a1bb8e4c},0'
                $ch = [BitConverter]::ToUInt16($b, 2)
                $sr = [BitConverter]::ToUInt32($b, 4)
                $bd = [BitConverter]::ToUInt16($b, 14)
                $vb = if ($b.Length -ge 20) { [BitConverter]::ToUInt16($b, 18) } else { $bd }
                $fmtStr = "$sr Hz / $vb-bit valid (container $bd) / $ch ch"
            } catch { $fmtStr = 'parse error' }
        }

        $sysfx = $null
        if ($p) { $sysfx = $p.'{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5' }
        $enh = switch ($sysfx) {
            1       { 'DISABLED (good)' }
            0       { 'ENABLED  (<-- suspect)' }
            default { 'not set / default = ENABLED (<-- suspect)' }
        }

        $exAllow = $null ; $exPrio = $null
        if ($p) {
            $exAllow = $p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},3'
            $exPrio  = $p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},4'
        }

        $result += [pscustomobject]@{
            Flow         = $Flow
            Name         = $name
            Desc         = $desc
            State        = $state
            Format       = $fmtStr
            Enhancements = $enh
            ExclusiveOK  = $exAllow
            ExclusivePri = $exPrio
            Key          = $ep.PSChildName
        }
    }
    return $result
}

Try-Do -Label 'render-endpoints' -Body {
    Sub 'Playback devices (Render)'
    $render = Get-AudioEndpointInfo -Flow 'Render'
    if (@($render).Count -eq 0) { W '  (no endpoints found in registry)' }
    foreach ($r in ($render | Sort-Object State)) {
        W ""
        W ("  [{0}] {1}  |  {2}" -f $r.State, $r.Name, $r.Desc)
        W ("      Engine format : {0}" -f $r.Format)
        W ("      Enhancements  : {0}" -f $r.Enhancements)
        W ("      Exclusive mode: allow={0}  priority={1}" -f $r.ExclusiveOK, $r.ExclusivePri)
        W ("      Endpoint GUID : {0}" -f $r.Key)
    }
}

Try-Do -Label 'apo-chain' -Body {
    Sub 'FxProperties - APO effect chain per ACTIVE playback endpoint'
    $rootR = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    foreach ($ep in (Get-ChildItem $rootR -ErrorAction SilentlyContinue)) {
        $st = (Get-ItemProperty -Path $ep.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
        if ($st -ne 1) { continue }
        $nm = (Get-ItemProperty -Path (Join-Path $ep.PSPath 'Properties') -ErrorAction SilentlyContinue).'{a45c254e-df1c-4efd-8020-67d146a850e0},14'
        $fx = Join-Path $ep.PSPath 'FxProperties'
        W ""
        W ("  Endpoint: {0}" -f $nm)
        if (Test-Path $fx) {
            $fxp = Get-ItemProperty $fx -ErrorAction SilentlyContinue
            $names = $fxp.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | Select-Object -First 30
            if ($names) {
                foreach ($n in $names) {
                    $val = $n.Value
                    if ($val -is [byte[]]) { $val = '(binary ' + $val.Length + ' bytes)' }
                    W ("      {0} = {1}" -f $n.Name, $val)
                }
            } else { W '      (FxProperties key exists but empty)' }
        } else {
            W '      no FxProperties - clean Microsoft audio path (good)'
        }
    }
}

Try-Do -Label 'capture-endpoints' -Body {
    Sub 'Recording devices (Capture) - short list'
    Out-Block ((Get-AudioEndpointInfo -Flow 'Capture') | Select-Object State, Name, Format) 'Table'
}

# =====================================================================
Section '3. AUDIO DRIVERS'
# =====================================================================
Try-Do -Label 'pnp-media' -Body {
    Sub 'PnP devices in MEDIA / AudioEndpoint / SoftwareDevice classes'
    Out-Block (Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Class -in @('MEDIA','AudioEndpoint','AudioProcessingObject','SoftwareDevice','SWD') } |
        Select-Object Status, Class, FriendlyName, InstanceId |
        Sort-Object Class, FriendlyName) 'Table'
}

Try-Do -Label 'signed-drivers' -Body {
    Sub 'Signed drivers - MEDIA class (version + date = the key evidence)'
    Out-Block (Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceClass -eq 'MEDIA' } |
        Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer, InfName |
        Sort-Object DeviceName) 'Table'
}

Try-Do -Label 'problem-devices' -Body {
    Sub 'Any PnP device in a PROBLEM state (whole machine)'
    Out-Block (Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Error' -or $_.Status -eq 'Degraded' -or $_.ConfigManagerErrorCode -gt 0 } |
        Select-Object Status, Class, FriendlyName, ConfigManagerErrorCode) 'Table'
}

# =====================================================================
Section '4. VIRTUAL / THIRD-PARTY AUDIO SOFTWARE (classic cause of stutter)'
# =====================================================================
$audioKeywords = @('nahimic','sonic studio','dts','dolby','waves','maxxaudio','realtek audio console',
                   'voicemeeter','vb-audio','virtual cable','krisp','nvidia broadcast','rtx voice',
                   'steelseries','sonar','razer','synapse','logitech g hub','corsair icue','equalizer apo',
                   'fxsound','boom 3d','asio','audio router','soundwire','elgato','streamlabs','obs')

Try-Do -Label 'installed-apps' -Body {
    Sub 'Installed programs matching audio keywords'
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = foreach ($pth in $paths) {
        Get-ItemProperty $pth -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    }
    $hits = $apps | Where-Object {
        $dn = $_.DisplayName.ToLower()
        @($audioKeywords | Where-Object { $dn -like "*$_*" }).Count -gt 0
    } | Sort-Object DisplayName -Unique
    if ($hits) { Out-Block $hits 'Table' } else { W '  (none found - good)' }
}

Try-Do -Label 'appx' -Body {
    Sub 'Appx / Store apps for audio & spatial sound'
    Out-Block (Get-AppxPackage -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Dolby|DTS|Sonic|Audio|Realtek|Nahimic|Waves' } |
        Select-Object Name, Version) 'Table'
}

Try-Do -Label 'audio-services' -Body {
    Sub 'Services matching audio keywords'
    Out-Block (Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            $n = ("$($_.Name) $($_.DisplayName)").ToLower()
            @($audioKeywords | Where-Object { $n -like "*$_*" }).Count -gt 0
        } | Select-Object Name, DisplayName, State, StartMode) 'Table'
}

Try-Do -Label 'startup-items' -Body {
    Sub 'Startup items (something loading at boot can be the trigger)'
    Out-Block (Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
        Select-Object Name, Command, Location) 'Table'
}

# =====================================================================
Section '5. AUDIO SERVICES & PROCESSES'
# =====================================================================
Try-Do -Label 'core-services' -Body {
    Out-Block (Get-Service -Name 'Audio*', 'RpcSs' -ErrorAction SilentlyContinue |
        Select-Object Name, Status, StartType, DisplayName) 'Table'
}

Try-Do -Label 'audiodg' -Body {
    Sub 'audiodg.exe (audio engine) - state right now'
    $adg = Get-Process audiodg -ErrorAction SilentlyContinue
    if ($adg) {
        $prio = 'n/a'
        try { $prio = $adg.PriorityClass } catch { $prio = 'access denied' }
        W ("  audiodg PID {0}  CPU(s) {1:N1}  WS {2:N0} MB  Threads {3}  Priority {4}" -f `
            $adg.Id, $adg.CPU, ($adg.WorkingSet64/1MB), $adg.Threads.Count, $prio)
    } else { W '  audiodg not running (nothing is playing right now)' }
}

Try-Do -Label 'top-cpu' -Body {
    Sub 'Top 12 processes by accumulated CPU time'
    Out-Block (Get-Process | Sort-Object CPU -Descending | Select-Object -First 12 `
        Name, Id, @{n='CPU_sec';e={[math]::Round($_.CPU,1)}}, @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB)}}) 'Table'
}

# =====================================================================
Section '6. POWER SETTINGS (a top cause of random stutter on Win11)'
# =====================================================================
$activeSchemeGuid = 'SCHEME_CURRENT'
Try-Do -Label 'active-scheme' -Body {
    Sub 'Active power scheme'
    $scheme = (powercfg /getactivescheme) 2>&1 | Out-String
    W ("  " + $scheme.Trim())
    $m = [regex]::Match($scheme, '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
    if ($m.Success) { $script:activeSchemeGuid = $m.Groups[1].Value }
}

Try-Do -Label 'power-values' -Body {
    Sub 'Relevant power settings (AC / DC current values)'
    $checks = @(
        @{ Name='Processor min state';    Sub='54533251-82be-4824-96c1-47b60b740d00'; Set='893dee8e-2bef-41e0-89c6-b55d0929964c' },
        @{ Name='Processor max state';    Sub='54533251-82be-4824-96c1-47b60b740d00'; Set='bc5038f7-23e0-4960-96da-33abaf5935ec' },
        @{ Name='Core parking min cores'; Sub='54533251-82be-4824-96c1-47b60b740d00'; Set='0cc5b647-c1df-4637-891a-dec35c318583' },
        @{ Name='USB selective suspend';  Sub='2a737441-1930-4402-8d77-b2bebba308a3'; Set='48e6b7a6-50f5-4782-a5d4-53bb8f07e226' },
        @{ Name='PCIe ASPM link state';   Sub='501a4d13-42af-4429-9fd1-a8218c268e20'; Set='ee12f906-d277-404b-b6da-e5fa1a576df5' },
        @{ Name='Turn off hard disk';     Sub='0012ee47-9041-4b5d-9b77-535fba8b1442'; Set='6738e2c4-e8a5-4a42-b16a-e040e769756e' }
    )
    foreach ($c in $checks) {
        try {
            $raw = (powercfg /query $script:activeSchemeGuid $c.Sub $c.Set) 2>&1 | Out-String
            # powercfg output is localized, so do not rely on its text:
            # the last two hex values are always Current AC, then Current DC.
            $hex = [regex]::Matches($raw, '0x[0-9a-fA-F]{2,}')
            if ($hex.Count -ge 2) {
                $acv = [Convert]::ToInt64($hex[$hex.Count-2].Value, 16)
                $dcv = [Convert]::ToInt64($hex[$hex.Count-1].Value, 16)
                W ("  {0,-24} AC={1}  DC={2}" -f $c.Name, $acv, $dcv)
            } else {
                W ("  {0,-24} (not available on this scheme)" -f $c.Name)
            }
        } catch { W ("  {0,-24} ERROR {1}" -f $c.Name, $_.Exception.Message) }
    }
}

Try-Do -Label 'device-power' -Body {
    Sub 'Devices with "allow the computer to turn off this device" ENABLED (first 40)'
    Out-Block (Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
        Where-Object { $_.Enable -eq $true } |
        Select-Object -First 40 @{n='Device';e={$_.InstanceName}}) 'Table'
}

# =====================================================================
Section '7. NETWORK / GPU / STORAGE (top DPC-latency offenders)'
# =====================================================================
Try-Do -Label 'nics' -Body {
    Sub 'Network adapters + driver versions'
    Out-Block (Get-NetAdapter -ErrorAction SilentlyContinue |
        Select-Object Name, InterfaceDescription, Status, LinkSpeed, DriverVersion, DriverDate, DriverProvider) 'Table'
}

Try-Do -Label 'nic-power' -Body {
    Sub 'NIC power saving (this alone can cause periodic audio drops)'
    foreach ($nic in (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $pm = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction SilentlyContinue
        if ($pm) {
            W ("  {0}: SelectiveSuspend={1}  WakeOnMagic={2}  DeviceSleepOnDisconnect={3}" -f `
                $nic.Name, $pm.SelectiveSuspend, $pm.WakeOnMagicPacket, $pm.DeviceSleepOnDisconnect)
        }
    }
}

Try-Do -Label 'gpu' -Body {
    Sub 'Display adapters + driver versions'
    Out-Block (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Select-Object Name, DriverVersion, DriverDate, VideoProcessor, CurrentHorizontalResolution, CurrentRefreshRate) 'Table'
}

Try-Do -Label 'disks' -Body {
    Sub 'Physical disks health'
    Out-Block (Get-PhysicalDisk -ErrorAction SilentlyContinue |
        Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, `
            @{n='Size_GB';e={[math]::Round($_.Size/1GB)}}) 'Table'

    Sub 'Disk reliability counters (read/write errors + wear)'
    foreach ($d in (Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        $rc = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($rc) {
            W ("  {0}: Temp={1}C  PowerOnHours={2}  ReadErrTotal={3}  WriteErrTotal={4}  Wear={5}" -f `
                $d.FriendlyName, $rc.Temperature, $rc.PowerOnHours, $rc.ReadErrorsTotal, $rc.WriteErrorsTotal, $rc.Wear)
        }
    }
}

Try-Do -Label 'freespace' -Body {
    Sub 'Free space on fixed drives'
    Out-Block (Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
        Select-Object DeviceID, @{n='Size_GB';e={[math]::Round($_.Size/1GB)}}, `
                      @{n='Free_GB';e={[math]::Round($_.FreeSpace/1GB)}}, `
                      @{n='Free_pct';e={ if ($_.Size -gt 0) { [math]::Round(100*$_.FreeSpace/$_.Size) } else { 0 } }}) 'Table'
}

# =====================================================================
Section "8. DPC / INTERRUPT MEASUREMENT ($CounterSeconds sec live sample)"
# =====================================================================
# If % DPC Time or % Interrupt Time jumps above ~2-3%, a driver is starving the system -
# exactly what makes audio stutter regardless of the application playing it.
function Get-LocalizedCounterPath {
    param([string]$EnglishPath)
    try {
        $en  = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009' -Name Counter -ErrorAction Stop).Counter
        $loc = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\CurrentLanguage' -Name Counter -ErrorAction Stop).Counter
        $map = @{}
        for ($i = 0; $i -lt $en.Length - 1; $i += 2) {
            $id = $en[$i]; $nm = $en[$i+1]
            if ($nm -and -not $map.ContainsKey($nm)) { $map[$nm] = $id }
        }
        $locMap = @{}
        for ($i = 0; $i -lt $loc.Length - 1; $i += 2) { $locMap[$loc[$i]] = $loc[$i+1] }

        $parts = $EnglishPath.Trim('\') -split '\\'
        $objEn = ($parts[0] -split '\(')[0]
        $inst  = if ($parts[0] -match '\((.+)\)') { $Matches[1] } else { $null }
        $ctrEn = $parts[1]
        if (-not $map.ContainsKey($objEn) -or -not $map.ContainsKey($ctrEn)) { return $EnglishPath }
        $objLoc = $locMap[$map[$objEn]]
        $ctrLoc = $locMap[$map[$ctrEn]]
        if ($inst) { return "\$objLoc($inst)\$ctrLoc" } else { return "\$objLoc\$ctrLoc" }
    } catch { return $EnglishPath }
}

Try-Do -Label 'counters' -Body {
    $wanted = @('\Processor(_Total)\% DPC Time',
                '\Processor(_Total)\% Interrupt Time',
                '\Processor(_Total)\% Processor Time',
                '\System\Processor Queue Length')
    $paths  = $wanted | ForEach-Object { Get-LocalizedCounterPath $_ }
    W ""
    W ">>> Sampling for $CounterSeconds seconds - PLAY A YOUTUBE VIDEO NOW, ideally one that stutters <<<"
    $samples = Get-Counter -Counter $paths -SampleInterval 1 -MaxSamples $CounterSeconds -ErrorAction Stop

    $byPath = @{}
    foreach ($s in $samples) {
        foreach ($v in $s.CounterSamples) {
            if (-not $byPath.ContainsKey($v.Path)) { $byPath[$v.Path] = New-Object System.Collections.ArrayList }
            [void]$byPath[$v.Path].Add([double]$v.CookedValue)
        }
    }
    W ""
    foreach ($k in $byPath.Keys) {
        $vals = $byPath[$k]
        $avg  = ($vals | Measure-Object -Average).Average
        $max  = ($vals | Measure-Object -Maximum).Maximum
        W ("  {0}" -f $k)
        W ("      avg = {0:N2}   max = {1:N2}" -f $avg, $max)
    }
    W ''
    W '  Rule of thumb: DPC/Interrupt avg > 2% or max > 8% = a driver is hogging the CPU.'
}

# =====================================================================
Section "9. EVENT LOGS (last $EventDays days)"
# =====================================================================
$since = (Get-Date).AddDays(-$EventDays)

function Show-Events {
    param([string]$Title, [hashtable]$Filter, [int]$Max = 25)
    Sub $Title
    try {
        $ev = Get-WinEvent -FilterHashtable $Filter -MaxEvents $Max -ErrorAction Stop
        if (-not $ev) { W '  (none)' ; return }
        $grp = $ev | Group-Object Id, ProviderName | Sort-Object Count -Descending
        foreach ($g in $grp) {
            $first = $g.Group[0]
            W ("  x{0,-4} ID {1,-6} {2}" -f $g.Count, $first.Id, $first.ProviderName)
            $msg = ($first.Message -split "`r?`n")[0]
            W ("        last: {0}  |  {1}" -f $first.TimeCreated, $msg)
        }
    } catch { W '  (none / not available)' }
}

Show-Events 'System log - Errors & Critical'   @{LogName='System'; Level=1,2; StartTime=$since} 40
Show-Events 'Kernel-Power'                     @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; StartTime=$since} 15
Show-Events 'WHEA hardware errors'             @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$since} 15
Show-Events 'Disk / storage'                   @{LogName='System'; ProviderName='disk','storahci','stornvme','volmgr','Ntfs'; StartTime=$since} 25
Show-Events 'Display driver reset (TDR)'       @{LogName='System'; Id=4101,4103,14; StartTime=$since} 15
Show-Events 'Application errors / hangs'       @{LogName='Application'; Level=1,2; StartTime=$since} 30

Try-Do -Label 'hotfix' -Body {
    Sub 'Windows Update history (last 60 days) - correlate with when it started'
    Out-Block (Get-HotFix -ErrorAction SilentlyContinue |
        Where-Object { $_.InstalledOn -and $_.InstalledOn -gt (Get-Date).AddDays(-60) } |
        Select-Object HotFixID, Description, InstalledOn |
        Sort-Object InstalledOn -Descending) 'Table'
}

Try-Do -Label 'reliability' -Body {
    Sub 'Reliability records (recent instability)'
    Out-Block (Get-CimInstance Win32_ReliabilityRecords -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeGenerated -gt $since } |
        Sort-Object TimeGenerated -Descending |
        Select-Object -First 20 TimeGenerated, SourceName, @{n='Msg';e={($_.Message -split "`r?`n")[0]}}) 'Table'
}

# =====================================================================
Section '10. MISC'
# =====================================================================
Try-Do -Label 'mmcss' -Body {
    Sub 'MMCSS - multimedia scheduling (audio thread priority)'
    $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    if (Test-Path $mm) {
        Out-Block (Get-ItemProperty $mm | Select-Object SystemResponsiveness, NetworkThrottlingIndex, NoLazyMode) 'List'
    } else { W '  (SystemProfile key not found)' }
    $mmAudio = "$mm\Tasks\Audio"
    if (Test-Path $mmAudio) {
        Out-Block (Get-ItemProperty $mmAudio | Select-Object Priority, 'Scheduling Category', 'SFIO Priority', 'Clock Rate') 'List'
    }
}

Try-Do -Label 'fast-startup' -Body {
    Sub 'Fast Startup (keeps stale driver state between boots)'
    $hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
    W ("  HiberbootEnabled = {0}   (1 = Fast Startup ON)" -f $hb)
}

Try-Do -Label 'vbs' -Body {
    Sub 'Memory integrity / VBS (adds latency on some machines)'
    Out-Block (Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue |
        Select-Object VirtualizationBasedSecurityStatus, SecurityServicesRunning, SecurityServicesConfigured) 'List'
}

Try-Do -Label 'browsers' -Body {
    Sub 'Browsers installed'
    foreach ($b in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                     "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                     "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                     "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")) {
        if ($b -and (Test-Path $b)) { W ("  {0} = {1}" -f (Split-Path $b -Leaf), (Get-Item $b).VersionInfo.ProductVersion) }
    }
}

# =====================================================================
W ''
W ('=' * 74)
W '  END OF REPORT'
W ('=' * 74)

try {
    $script:SB.ToString() | Out-File -FilePath $OutFile -Encoding UTF8
    Write-Host ''
    Write-Host "Report saved to: $OutFile" -ForegroundColor Green
    Write-Host "Next: review sections 2, 6 and 8, then try Repair-AudioStutter.ps1 (report mode first)." -ForegroundColor Green
} catch {
    Write-Host "Could not write report file: $($_.Exception.Message)" -ForegroundColor Red
}
