<#
.SYNOPSIS
    Exports every Exchange Online / Microsoft 365 distribution list (and optionally Microsoft 365 groups)
    with all their members to an Excel workbook - or to CSV files when ImportExcel is not installed.

.DESCRIPTION
    Read-only. For each group it collects the settings people usually ask about (owners, who can send
    to it, external senders allowed, hidden from the address list...) and every member (recursively
    expanded on request), then writes:

      Excel (ImportExcel module present):
        DistributionLists_<yyyyMMdd_HHmm>.xlsx
          sheet "Summary"  - one row per group (name, address, type, member count, owners, settings)
          sheet "Members"  - one row per group/member pair (filterable table)
          -SheetPerGroup   - additionally one sheet per group
      CSV fallback:
        DistributionLists_<stamp>_Summary.csv and DistributionLists_<stamp>_Members.csv (UTF-8 with BOM,
        opens correctly in Excel including Hebrew / non-Latin names)

.PARAMETER OutputFolder
    Where the export is written. Default: .\exports next to the script.

.PARAMETER IncludeM365Groups
    Also export Microsoft 365 (Unified) groups - members and owners via Get-UnifiedGroupLinks.

.PARAMETER Expand
    Expand nested distribution lists so every person is listed (the nesting path is kept in a column).

.PARAMETER Filter
    Optional name filter (wildcards), e.g. 'Branch*'.

.PARAMETER SheetPerGroup
    Excel only: add one worksheet per group (sheet names are truncated to 31 characters).

.PARAMETER AdminUpn
    Admin account for Connect-ExchangeOnline. If omitted, the sign-in prompt asks for it.
    When already connected, the existing session is reused.

.PARAMETER ForceCsv
    Write CSV even when ImportExcel is available.

.EXAMPLE
    .\Export-DistributionLists.ps1 -AdminUpn '<ADMIN_UPN>'

.EXAMPLE
    .\Export-DistributionLists.ps1 -IncludeM365Groups -Expand -SheetPerGroup -OutputFolder 'C:\Exports'

.EXAMPLE
    .\Export-DistributionLists.ps1 -Filter 'Branch*' -ForceCsv

.NOTES
    Requirements : ExchangeOnlineManagement module (v3+): Install-Module ExchangeOnlineManagement -Scope CurrentUser
                   ImportExcel module (optional, for .xlsx): Install-Module ImportExcel -Scope CurrentUser
                   Role: View-Only Recipients / Exchange Recipient Administrator (read access is enough).
    Safety       : read-only in Exchange Online. The export contains names and addresses of staff -
                   store it in an access-controlled location (exports/ is git-ignored).
    Author       : Gal Asulin
#>
[CmdletBinding()]
param(
    [string]$OutputFolder = (Join-Path $PSScriptRoot 'exports'),
    [switch]$IncludeM365Groups,
    [switch]$Expand,
    [string]$Filter = '*',
    [switch]$SheetPerGroup,
    [string]$AdminUpn,
    [switch]$ForceCsv
)
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- modules & connection
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    throw 'ExchangeOnlineManagement is not installed. Run: Install-Module ExchangeOnlineManagement -Scope CurrentUser'
}
Import-Module ExchangeOnlineManagement
$useExcel = (-not $ForceCsv) -and [bool](Get-Module -ListAvailable -Name ImportExcel)
if ($useExcel) { Import-Module ImportExcel } elseif (-not $ForceCsv) {
    Write-Warning 'ImportExcel is not installed - writing CSV instead. For .xlsx: Install-Module ImportExcel -Scope CurrentUser'
}

$connected = $false
try { $connected = [bool](Get-ConnectionInformation -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Connected' }) } catch { }
if (-not $connected) {
    $cp = @{ ShowBanner = $false }
    if ($AdminUpn) { $cp.UserPrincipalName = $AdminUpn }
    Connect-ExchangeOnline @cp
}

if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd_HHmm'

# ---------------------------------------------------------------- helpers
function Get-DlMembers {
    param([string]$Identity, [string]$Path, [hashtable]$Seen)
    foreach ($m in (Get-DistributionGroupMember -Identity $Identity -ResultSize Unlimited)) {
        $isGroup = $m.RecipientTypeDetails -match 'Group'
        if ($Expand -and $isGroup) {
            $key = [string]$m.Guid
            if ($Seen.ContainsKey($key)) { continue }   # nested loop protection
            $Seen[$key] = $true
            Get-DlMembers -Identity $key -Path ("{0} > {1}" -f $Path, $m.DisplayName) -Seen $Seen
        } else {
            [pscustomobject]@{
                MemberName    = $m.DisplayName
                MemberAddress = [string]$m.PrimarySmtpAddress
                MemberType    = [string]$m.RecipientTypeDetails
                Via           = $Path
            }
        }
    }
}

function Get-OwnerNames($ManagedBy) {
    (@($ManagedBy) | Where-Object { $_ } | ForEach-Object {
        $r = Get-Recipient -Identity $_ -ErrorAction SilentlyContinue
        if ($r) { $r.DisplayName } else { [string]$_ }
    }) -join '; '
}

$summary = New-Object System.Collections.Generic.List[object]
$members = New-Object System.Collections.Generic.List[object]

# ---------------------------------------------------------------- distribution lists
$dls = @(Get-DistributionGroup -ResultSize Unlimited -Filter "Name -like '$($Filter.Replace("'", "''"))'" | Sort-Object DisplayName)
Write-Host ("{0} distribution list(s) / mail-enabled security group(s)" -f $dls.Count)
$i = 0
foreach ($g in $dls) {
    $i++
    Write-Progress -Activity 'Distribution lists' -Status $g.DisplayName -PercentComplete ($i * 100 / [math]::Max(1, $dls.Count))
    $list = @(Get-DlMembers -Identity ([string]$g.Guid) -Path $g.DisplayName -Seen @{ ([string]$g.Guid) = $true })
    foreach ($m in $list) {
        $members.Add([pscustomobject]@{
                Group         = $g.DisplayName
                GroupAddress  = [string]$g.PrimarySmtpAddress
                MemberName    = $m.MemberName
                MemberAddress = $m.MemberAddress
                MemberType    = $m.MemberType
                Via           = $m.Via
            })
    }
    $summary.Add([pscustomobject]@{
            Name                    = $g.DisplayName
            Address                 = [string]$g.PrimarySmtpAddress
            Type                    = [string]$g.RecipientTypeDetails
            Members                 = $list.Count
            Owners                  = Get-OwnerNames $g.ManagedBy
            ExternalSendersAllowed  = -not $g.RequireSenderAuthenticationEnabled
            HiddenFromAddressList   = $g.HiddenFromAddressListsEnabled
            RestrictedSenders       = (@($g.AcceptMessagesOnlyFromSendersOrMembers) -join '; ')
            MemberJoinRestriction   = [string]$g.MemberJoinRestriction
            Created                 = $g.WhenCreated
        })
}

# ---------------------------------------------------------------- Microsoft 365 groups
if ($IncludeM365Groups) {
    $ugs = @(Get-UnifiedGroup -ResultSize Unlimited -Filter "DisplayName -like '$($Filter.Replace("'", "''"))'" | Sort-Object DisplayName)
    Write-Host ("{0} Microsoft 365 group(s)" -f $ugs.Count)
    foreach ($g in $ugs) {
        $list = @(Get-UnifiedGroupLinks -Identity ([string]$g.Guid) -LinkType Members -ResultSize Unlimited)
        $owners = @(Get-UnifiedGroupLinks -Identity ([string]$g.Guid) -LinkType Owners -ResultSize Unlimited)
        foreach ($m in $list) {
            $members.Add([pscustomobject]@{
                    Group         = $g.DisplayName
                    GroupAddress  = [string]$g.PrimarySmtpAddress
                    MemberName    = $m.DisplayName
                    MemberAddress = [string]$m.PrimarySmtpAddress
                    MemberType    = [string]$m.RecipientTypeDetails
                    Via           = $g.DisplayName
                })
        }
        $summary.Add([pscustomobject]@{
                Name                   = $g.DisplayName
                Address                = [string]$g.PrimarySmtpAddress
                Type                   = 'Microsoft365Group'
                Members                = $list.Count
                Owners                 = ($owners.DisplayName -join '; ')
                ExternalSendersAllowed = -not $g.RequireSenderAuthenticationEnabled
                HiddenFromAddressList  = $g.HiddenFromAddressListsEnabled
                RestrictedSenders      = (@($g.AcceptMessagesOnlyFromSendersOrMembers) -join '; ')
                MemberJoinRestriction  = [string]$g.AccessType
                Created                = $g.WhenCreated
            })
    }
}
Write-Progress -Activity 'Distribution lists' -Completed

# ---------------------------------------------------------------- write
if ($useExcel) {
    $xlsx = Join-Path $OutputFolder "DistributionLists_$stamp.xlsx"
    $summary | Export-Excel -Path $xlsx -WorksheetName 'Summary' -TableName 'Summary' -AutoSize -FreezeTopRow -BoldTopRow
    $members | Export-Excel -Path $xlsx -WorksheetName 'Members' -TableName 'Members' -AutoSize -FreezeTopRow -BoldTopRow
    if ($SheetPerGroup) {
        $used = @{}
        foreach ($grp in ($members | Group-Object Group)) {
            $name = ($grp.Name -replace '[\[\]\*\?/\\:]', '_')
            if ($name.Length -gt 28) { $name = $name.Substring(0, 28) }
            $n = $name; $k = 1
            while ($used.ContainsKey($n.ToLower())) { $k++; $n = '{0}~{1}' -f $name, $k }
            $used[$n.ToLower()] = $true
            $grp.Group | Select-Object MemberName, MemberAddress, MemberType, Via |
                Export-Excel -Path $xlsx -WorksheetName $n -AutoSize -FreezeTopRow -BoldTopRow
        }
    }
    Write-Host "Saved: $xlsx" -ForegroundColor Green
} else {
    $s = Join-Path $OutputFolder "DistributionLists_${stamp}_Summary.csv"
    $m = Join-Path $OutputFolder "DistributionLists_${stamp}_Members.csv"
    # UTF-8 with BOM so Excel shows non-Latin names correctly (5.1: 'UTF8' has a BOM; 7+: 'utf8BOM')
    $enc = if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }
    $summary | Export-Csv -Path $s -NoTypeInformation -Encoding $enc
    $members | Export-Csv -Path $m -NoTypeInformation -Encoding $enc
    Write-Host "Saved: $s" -ForegroundColor Green
    Write-Host "Saved: $m" -ForegroundColor Green
}
Write-Host ("{0} group(s), {1} membership row(s)." -f $summary.Count, $members.Count)
