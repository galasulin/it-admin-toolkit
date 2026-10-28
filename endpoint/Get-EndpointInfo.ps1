<#
.SYNOPSIS
    Collects a one-file support/inventory report of a workstation: user, network, OS, hardware
    (service tag / serial), disks, GPU and installed programs.

.DESCRIPTION
    PowerShell rewrite of a classic "userinfo" helpdesk batch file. Read-only. Writes one text report
    (and optionally a CSV of installed programs) named <COMPUTER>_<USER>_<yyyyMMdd_HHmm>.txt.
    Sections: user & groups (whoami), mapped drives, IP configuration, OS / install date / last boot,
    manufacturer / model / serial number (service tag), BIOS, CPU / RAM, disks and free space,
    display adapters, power sleep states, installed programs (from the registry - fast, unlike
    Win32_Product which triggers MSI repairs).

    It deliberately does NOT read product keys or any other secret.

.PARAMETER OutputFolder
    Where the report is written. Default: the current user's Desktop, or a share such as
    '\\<FILE_SERVER>\<SHARE>\inventory' for helpdesk collection.

.PARAMETER ProgramsCsv
    Also write the installed-programs list as a separate CSV.

.PARAMETER ServiceTagOnly
    Write only the short hardware identification (manufacturer, model, serial / service tag).

.EXAMPLE
    .\Get-EndpointInfo.ps1

.EXAMPLE
    .\Get-EndpointInfo.ps1 -OutputFolder '\\<FILE_SERVER>\<SHARE>\inventory' -ProgramsCsv

.EXAMPLE
    .\Get-EndpointInfo.ps1 -ServiceTagOnly

.NOTES
    Requirements : Windows PowerShell 5.1+. No admin rights needed (some fields are richer when elevated).
    Safety       : read-only. The report contains user names, IP addresses and serial numbers -
                   store it on an access-controlled location.
    Author       : Gal Asulin
#>
[CmdletBinding()]
param(
    [string]$OutputFolder = [Environment]::GetFolderPath('Desktop'),
    [switch]$ProgramsCsv,
    [switch]$ServiceTagOnly
)
$ErrorActionPreference = 'Continue'

if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
$base = Join-Path $OutputFolder ('{0}_{1}_{2}' -f $env:COMPUTERNAME, $env:USERNAME, $stamp)
$report = "$base.txt"

$sb = New-Object System.Text.StringBuilder
function Add-Line([string]$Text = '') { [void]$sb.AppendLine($Text) }
function Add-Section([string]$Title) { Add-Line ''; Add-Line ('-' * 85); Add-Line $Title; Add-Line ('-' * 85) }
function Add-Object($Obj, [switch]$Table) {
    if ($null -eq $Obj) { Add-Line '  (no data)'; return }
    $txt = if ($Table) { $Obj | Format-Table -AutoSize | Out-String -Width 250 } else { $Obj | Format-List | Out-String -Width 250 }
    Add-Line $txt.TrimEnd()
}

Add-Line ("Info file for user : {0}\{1} on computer : {2}" -f $env:USERDOMAIN, $env:USERNAME, $env:COMPUTERNAME)
Add-Line ("Generated on       : {0}" -f (Get-Date))
Add-Line ('=' * 85)

$cs = Get-CimInstance Win32_ComputerSystem
$csp = Get-CimInstance Win32_ComputerSystemProduct
$bios = Get-CimInstance Win32_BIOS

Add-Section 'Hardware identification (service tag)'
Add-Object ([pscustomobject]@{
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        SerialNumber = $bios.SerialNumber
        ProductName  = $csp.Name
        UUID         = $csp.UUID
    })

if (-not $ServiceTagOnly) {
    $os = Get-CimInstance Win32_OperatingSystem
    Add-Section 'Operating system'
    Add-Object ([pscustomobject]@{
            Caption      = $os.Caption
            Version      = $os.Version
            Build        = $os.BuildNumber
            Architecture = $os.OSArchitecture
            InstallDate  = $os.InstallDate
            LastBoot     = $os.LastBootUpTime
            Domain       = $cs.Domain
        })

    Add-Section 'BIOS / CPU / memory'
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Add-Object ([pscustomobject]@{
            BIOSVersion = $bios.SMBIOSBIOSVersion
            BIOSDate    = $bios.ReleaseDate
            CPU         = $cpu.Name
            Cores       = $cpu.NumberOfCores
            Threads     = $cpu.NumberOfLogicalProcessors
            RAM_GB      = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        })

    Add-Section 'User and group membership (whoami /all)'
    Add-Line ((& whoami.exe /all) -join "`r`n")

    Add-Section 'Mapped drives (net use)'
    Add-Line ((& net.exe use) -join "`r`n")

    Add-Section 'Network configuration (ipconfig /all)'
    Add-Line ((& ipconfig.exe /all) -join "`r`n")

    Add-Section 'Disks'
    Add-Object (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
            Select-Object DeviceID, VolumeName, @{n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB) } }, @{n = 'Free_GB'; e = { [math]::Round($_.FreeSpace / 1GB) } }) -Table
    Add-Object (Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName, MediaType, BusType, HealthStatus, @{n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB) } }) -Table

    Add-Section 'Display adapters'
    Add-Object (Get-CimInstance Win32_VideoController | Select-Object Caption, DriverVersion, @{n = 'RAM_MB'; e = { [math]::Round($_.AdapterRAM / 1MB) } }) -Table

    Add-Section 'Available sleep states (powercfg /a)'
    Add-Line ((& powercfg.exe /a) -join "`r`n")

    Add-Section 'Installed programs'
    $programs = foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    }
    $programs = $programs | Sort-Object DisplayName -Unique
    Add-Object $programs -Table
    if ($ProgramsCsv) { $programs | Export-Csv -Path "$base-programs.csv" -NoTypeInformation -Encoding UTF8 }
}

Add-Line ''
Add-Line 'End of file.'
$sb.ToString() | Out-File -FilePath $report -Encoding UTF8
Write-Host "Report written: $report" -ForegroundColor Green
