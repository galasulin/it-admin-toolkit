<#
.SYNOPSIS
    Sets (or resets to DHCP) the DNS servers of a network adapter, then flushes and re-registers DNS.

.DESCRIPTION
    - With -DnsServers: sets a static DNS server list on the chosen adapter(s).
    - With -UseDhcp   : returns the adapter(s) to DNS servers from DHCP.
    - With neither    : only flushes the DNS client cache and re-registers this computer in DNS
                        (ipconfig /flushdns + /registerdns) - the classic "name does not resolve" fix.
    The current setting is printed before any change, so it can be put back.

.PARAMETER InterfaceAlias
    Adapter name(s) as shown by Get-NetAdapter, e.g. 'Ethernet' or 'Wi-Fi'.
    Default: every adapter that is Up and has a default gateway.

.PARAMETER DnsServers
    DNS server addresses in order of preference, e.g. '<DNS_PRIMARY>','<DNS_SECONDARY>'.

.PARAMETER UseDhcp
    Reset the DNS servers to the values given by DHCP.

.PARAMETER NoFlush
    Do not run the flush / register step.

.EXAMPLE
    .\Set-DnsServers.ps1 -InterfaceAlias Ethernet -DnsServers '<DNS_PRIMARY>','<DNS_SECONDARY>'

.EXAMPLE
    .\Set-DnsServers.ps1 -UseDhcp -WhatIf

.EXAMPLE
    .\Set-DnsServers.ps1      # flush + re-register only

.NOTES
    Requirements : run as Administrator; Windows 8 / Server 2012 or later (DnsClient / NetAdapter modules).
    Safety       : changes the adapter's DNS configuration - a wrong server breaks name resolution
                   (including domain logon). The previous servers are printed so you can restore them.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Flush')]
param(
    [string[]]$InterfaceAlias,
    [Parameter(ParameterSetName = 'Static', Mandatory = $true)]
    [ValidateScript({ $_ | ForEach-Object { [System.Net.IPAddress]::Parse($_) | Out-Null }; $true })]
    [string[]]$DnsServers,
    [Parameter(ParameterSetName = 'Dhcp', Mandatory = $true)]
    [switch]$UseDhcp,
    [switch]$NoFlush
)
$ErrorActionPreference = 'Stop'

if (-not $InterfaceAlias) {
    $InterfaceAlias = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        ForEach-Object { $_.InterfaceAlias }
}

foreach ($alias in $InterfaceAlias) {
    $current = (Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4).ServerAddresses
    Write-Host ("[{0}] current DNS: {1}" -f $alias, ($(if ($current) { $current -join ', ' } else { '(none / DHCP)' })))
    if ($PSCmdlet.ParameterSetName -eq 'Static' -and $PSCmdlet.ShouldProcess($alias, "Set DNS to $($DnsServers -join ', ')")) {
        Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $DnsServers
        Write-Host ("[{0}] new DNS    : {1}" -f $alias, ($DnsServers -join ', ')) -ForegroundColor Green
    }
    if ($PSCmdlet.ParameterSetName -eq 'Dhcp' -and $PSCmdlet.ShouldProcess($alias, 'Reset DNS to DHCP')) {
        Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses
        Write-Host ("[{0}] DNS reset to DHCP" -f $alias) -ForegroundColor Green
    }
}

if (-not $NoFlush -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Flush DNS cache and re-register in DNS')) {
    Clear-DnsClientCache
    & ipconfig.exe /registerdns | Out-Null
    Write-Host 'DNS cache flushed and DNS registration requested.' -ForegroundColor Green
}
