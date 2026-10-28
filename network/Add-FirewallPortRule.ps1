<#
.SYNOPSIS
    Opens Windows Firewall ports for common line-of-business needs (SQL Server, RDP, ping, custom ports)
    with one consistent, idempotent command.

.DESCRIPTION
    Replaces a set of one-off netsh .bat files with a single script based on the NetSecurity module.
    Choose a -Preset or give your own -Port / -Protocol. Rules are created for inbound (and optionally
    outbound) traffic, are named with a common prefix so they are easy to find, and are skipped when a
    rule with the same name already exists.

    Presets:
      SqlServer     TCP 1433 (default instance), TCP 1434 (DAC), UDP 1434 (SQL Browser), TCP 4022 (Service Broker)
      SqlAnalysis   TCP 2383 (SSAS default instance), TCP 2382 (SQL Server Browser for SSAS)
      Rdp           enables the built-in "Remote Desktop" rule group
      Ping          ICMPv4 echo request (inbound)
      Custom        uses -Port and -Protocol

.PARAMETER Preset
    SqlServer | SqlAnalysis | Rdp | Ping | Custom. Default: Custom.

.PARAMETER Port
    Port(s) or range(s) for -Preset Custom, e.g. 8080 or '2221-2226'.

.PARAMETER Protocol
    TCP or UDP (Custom only). Use -Protocol TCP,UDP for both. Default: TCP.

.PARAMETER Name
    Display name prefix. Default: the preset name.

.PARAMETER Outbound
    Also create matching outbound allow rules (only needed when outbound traffic is blocked by policy).

.PARAMETER FirewallProfile
    Firewall profile(s): Domain, Private, Public, Any. Default: Domain,Private.

.PARAMETER RemoteAddress
    Limit the rule to source addresses / subnets, e.g. LocalSubnet or '<MGMT_SUBNET>/24'. Default: Any.

.EXAMPLE
    .\Add-FirewallPortRule.ps1 -Preset SqlServer -RemoteAddress LocalSubnet

.EXAMPLE
    .\Add-FirewallPortRule.ps1 -Preset Custom -Name 'AV management agent' -Port '2221-2226' -Protocol TCP,UDP -Outbound -WhatIf

.EXAMPLE
    .\Add-FirewallPortRule.ps1 -Preset Rdp

.NOTES
    Requirements : run as Administrator; Windows 8 / Server 2012 or later (NetSecurity module).
    Safety       : opens inbound ports. Prefer -FirewallProfile Domain and -RemoteAddress to keep exposure small.
                   Undo: Remove-NetFirewallRule -DisplayName '<prefix>*'
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('SqlServer', 'SqlAnalysis', 'Rdp', 'Ping', 'Custom')]
    [string]$Preset = 'Custom',
    [string[]]$Port,
    [ValidateSet('TCP', 'UDP')]
    [string[]]$Protocol = @('TCP'),
    [string]$Name,
    [switch]$Outbound,
    [ValidateSet('Domain', 'Private', 'Public', 'Any')]
    [string[]]$FirewallProfile = @('Domain', 'Private'),
    [string[]]$RemoteAddress = @('Any')
)
$ErrorActionPreference = 'Stop'
Import-Module NetSecurity

if (-not $Name) { $Name = $Preset }

$rules = switch ($Preset) {
    'SqlServer' {
        @{ Port = '1433'; Protocol = 'TCP'; Label = 'SQL Server' },
        @{ Port = '1434'; Protocol = 'TCP'; Label = 'SQL Admin Connection (DAC)' },
        @{ Port = '1434'; Protocol = 'UDP'; Label = 'SQL Browser' },
        @{ Port = '4022'; Protocol = 'TCP'; Label = 'SQL Service Broker' }
    }
    'SqlAnalysis' {
        @{ Port = '2383'; Protocol = 'TCP'; Label = 'Analysis Services' },
        @{ Port = '2382'; Protocol = 'TCP'; Label = 'SQL Browser for SSAS' }
    }
    'Custom' {
        if (-not $Port) { throw '-Preset Custom needs -Port.' }
        foreach ($pr in $Protocol) { @{ Port = ($Port -join ','); Protocol = $pr; Label = "$pr $($Port -join ',')" } }
    }
    default { @() }
}

if ($Preset -eq 'Rdp') {
    if ($PSCmdlet.ShouldProcess('Remote Desktop rule group', 'Enable')) {
        Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'
        Write-Host 'Remote Desktop firewall rules enabled.' -ForegroundColor Green
    }
    return
}

if ($Preset -eq 'Ping') {
    $dn = "$Name - ICMPv4 echo in"
    if (Get-NetFirewallRule -DisplayName $dn -ErrorAction SilentlyContinue) { Write-Host "exists: $dn"; return }
    if ($PSCmdlet.ShouldProcess($dn, 'Create rule')) {
        New-NetFirewallRule -DisplayName $dn -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -Profile $FirewallProfile -RemoteAddress $RemoteAddress | Out-Null
        Write-Host "created: $dn" -ForegroundColor Green
    }
    return
}

$directions = @('Inbound')
if ($Outbound) { $directions += 'Outbound' }

foreach ($r in $rules) {
    foreach ($dir in $directions) {
        $dn = '{0} - {1} {2} {3}' -f $Name, $r.Label, $r.Protocol, $dir
        if (Get-NetFirewallRule -DisplayName $dn -ErrorAction SilentlyContinue) { Write-Host "exists: $dn"; continue }
        if (-not $PSCmdlet.ShouldProcess($dn, "Allow $($r.Protocol) $($r.Port)")) { continue }
        $ports = $r.Port -split ','
        $common = @{ DisplayName = $dn; Direction = $dir; Protocol = $r.Protocol; Action = 'Allow'; Profile = $FirewallProfile }
        if ($dir -eq 'Inbound') {
            New-NetFirewallRule @common -LocalPort $ports -RemoteAddress $RemoteAddress | Out-Null
        } else {
            New-NetFirewallRule @common -RemotePort $ports | Out-Null
        }
        Write-Host "created: $dn" -ForegroundColor Green
    }
}
