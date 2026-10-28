<#
.SYNOPSIS
    Maps a set of network drives from a simple CSV (or hashtable), persistently, without ever storing
    a password in the script.

.DESCRIPTION
    Each mapping is  DriveLetter -> UNC path. Existing mappings to the same path are kept; a letter
    mapped to a different path is reported and left alone unless -Replace is given.
    If a different account is needed, pass -Credential (you are prompted - nothing is saved in the file;
    Windows Credential Manager remembers it only if you choose "remember" yourself).

    CSV format (header required):
        Drive,Path
        P,\\<FILE_SERVER>\<PUBLIC_SHARE>
        S,\\<FILE_SERVER>\<DEPT_SHARE>

.PARAMETER CsvPath
    CSV file with Drive,Path columns.

.PARAMETER Map
    Alternative to -CsvPath: a hashtable, e.g. @{ P = '\\<FILE_SERVER>\<SHARE>' }.

.PARAMETER Credential
    Account to connect with (Get-Credential). Default: the logged-on user.

.PARAMETER Replace
    Remove an existing mapping of the same letter that points somewhere else.

.EXAMPLE
    .\Connect-NetworkDrives.ps1 -CsvPath .\drives.csv

.EXAMPLE
    .\Connect-NetworkDrives.ps1 -Map @{ P = '\\<FILE_SERVER>\<SHARE>' } -Credential (Get-Credential) -WhatIf

.NOTES
    Requirements : Windows PowerShell 5.1+, run as the user (not elevated - elevated sessions do not
                   see the user's drive mappings).
    Safety       : creates / replaces drive mappings for the current user only. Undo: Remove-PSDrive or
                   "net use X: /delete".
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Csv')]
param(
    [Parameter(ParameterSetName = 'Csv', Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(ParameterSetName = 'Map', Mandatory = $true)]
    [hashtable]$Map,
    [System.Management.Automation.PSCredential]$Credential,
    [switch]$Replace
)
$ErrorActionPreference = 'Stop'

$items = if ($PSCmdlet.ParameterSetName -eq 'Csv') {
    Import-Csv -Path $CsvPath | ForEach-Object { [pscustomobject]@{ Drive = $_.Drive; Path = $_.Path } }
} else {
    $Map.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Drive = $_.Key; Path = $_.Value } }
}

foreach ($i in $items) {
    $letter = ([string]$i.Drive).TrimEnd(':').ToUpper()
    if ($letter -notmatch '^[A-Z]$') { Write-Warning "Invalid drive letter '$($i.Drive)' - skipped"; continue }
    $existing = Get-PSDrive -Name $letter -PSProvider FileSystem -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.DisplayRoot -eq $i.Path) { Write-Host "${letter}: already mapped to $($i.Path)"; continue }
        if (-not $Replace) { Write-Warning "${letter}: is in use ($($existing.DisplayRoot) $($existing.Root)) - use -Replace"; continue }
        if ($PSCmdlet.ShouldProcess("${letter}:", 'Remove existing mapping')) {
            & net.exe use "${letter}:" /delete /y | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess("${letter}:", "Map to $($i.Path)")) {
        $params = @{ Name = $letter; PSProvider = 'FileSystem'; Root = $i.Path; Persist = $true; Scope = 'Global' }
        if ($Credential) { $params.Credential = $Credential }
        try {
            New-PSDrive @params | Out-Null
            Write-Host "${letter}: -> $($i.Path)" -ForegroundColor Green
        } catch {
            Write-Warning ("${letter}: could not map $($i.Path): {0}" -f $_.Exception.Message)
        }
    }
}
