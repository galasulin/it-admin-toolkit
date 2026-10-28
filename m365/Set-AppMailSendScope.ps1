<#
.SYNOPSIS
    Limits an Entra ID app so it can send mail ONLY as specific mailboxes, using Exchange Online
    "RBAC for Applications" - then proves it with a positive and a negative test.

.DESCRIPTION
    Typical case: an unattended report mailer / scanner / line-of-business app needs Mail.Send.
    Granting Graph Mail.Send with admin consent lets the app send as EVERY mailbox in the tenant.
    RBAC for Applications (the replacement for New-ApplicationAccessPolicy) scopes the permission:

      1. registers the app's service principal in Exchange Online (New-ServicePrincipal)
      2. tags the allowed mailbox(es) with a custom attribute (default CustomAttribute15) -
         refuses if that attribute is already used for something else
      3. creates a management scope matching that tag
      4. assigns the 'Application Mail.Send' role to the app, limited to that scope
      5. verifies with Test-ServicePrincipalAuthorization: InScope = True for the allowed mailbox(es),
         InScope = False for a mailbox that must NOT be reachable

    IMPORTANT: the app registration must have NO Graph Mail.Send application permission with admin consent.
    Entra permissions and Exchange RBAC permissions are a UNION - an org-wide consent makes this scope useless.

.PARAMETER AppId
    Application (client) ID - Entra > App registrations > <app> > Overview.

.PARAMETER ServicePrincipalObjectId
    Object ID of the ENTERPRISE APPLICATION (Entra > Enterprise applications > <app>),
    not the object ID of the app registration.

.PARAMETER AppName
    Display name for the service principal in Exchange Online.

.PARAMETER Mailbox
    Mailbox(es) the app may send as (UPN / SMTP address).

.PARAMETER NegativeTestMailbox
    A mailbox that must NOT be in scope - used to prove the scope blocks everyone else.

.PARAMETER AdminUpn
    Admin account for Connect-ExchangeOnline.

.PARAMETER CustomAttribute
    Which CustomAttributeN (1-15) holds the tag. Default: 15.

.PARAMETER Tag
    Value written into the custom attribute. Default: the app name without spaces.

.EXAMPLE
    .\Set-AppMailSendScope.ps1 -AppId '<APP_ID_GUID>' -ServicePrincipalObjectId '<ENTERPRISE_APP_OBJECT_ID>' `
        -AppName 'Report Mailer' -Mailbox '<SENDER_MAILBOX_UPN>' -NegativeTestMailbox '<OTHER_MAILBOX_UPN>' -AdminUpn '<ADMIN_UPN>' -WhatIf

.NOTES
    Requirements : ExchangeOnlineManagement module (v3+); Entra role Exchange Administrator / EXO
                   Organization Management. Windows PowerShell 5.1 or PowerShell 7.
    Safety       : changes Exchange Online (service principal, mailbox custom attribute, management scope,
                   role assignment). Use -WhatIf first. Undo: Remove-ManagementRoleAssignment,
                   Remove-ManagementScope, Set-Mailbox -CustomAttributeN $null, Remove-ServicePrincipal.
                   The permission cache can take 30 min to 2 h to settle; Test-ServicePrincipalAuthorization
                   bypasses it.
    Author       : Gal Asulin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][guid]$AppId,
    [Parameter(Mandatory = $true)][guid]$ServicePrincipalObjectId,
    [Parameter(Mandatory = $true)][string]$AppName,
    [Parameter(Mandatory = $true)][string[]]$Mailbox,
    [string]$NegativeTestMailbox,
    [Parameter(Mandatory = $true)][string]$AdminUpn,
    [ValidateRange(1, 15)][int]$CustomAttribute = 15,
    [string]$Tag = (($AppName -replace '[^A-Za-z0-9]', ''))
)
$ErrorActionPreference = 'Stop'

$ScopeName = "$AppName Scope"
$attr = "CustomAttribute$CustomAttribute"

Write-Host "`n=== 0. Connecting to Exchange Online ===" -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    throw 'ExchangeOnlineManagement is not installed. Run: Install-Module ExchangeOnlineManagement -Scope CurrentUser'
}
Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline -UserPrincipalName $AdminUpn -ShowBanner:$false

Write-Host "`n=== 1. Service principal in Exchange Online ===" -ForegroundColor Cyan
if (Get-ServicePrincipal -Identity $AppId.Guid -ErrorAction SilentlyContinue) {
    Write-Host '    already exists - skipping' -ForegroundColor DarkGray
} elseif ($PSCmdlet.ShouldProcess($AppName, 'New-ServicePrincipal')) {
    New-ServicePrincipal -AppId $AppId.Guid -ObjectId $ServicePrincipalObjectId.Guid -DisplayName $AppName | Out-Null
}

Write-Host "`n=== 2. Tagging the allowed mailbox(es) ($attr) ===" -ForegroundColor Cyan
foreach ($mbx in $Mailbox) {
    $current = (Get-Mailbox -Identity $mbx).$attr
    if ($current -and $current -ne $Tag) {
        throw "$mbx already uses $attr = '$current'. Overwriting could break another system - choose another -CustomAttribute."
    }
    if ($PSCmdlet.ShouldProcess($mbx, "Set $attr = $Tag")) {
        $setParams = @{ Identity = $mbx; $attr = $Tag }
        Set-Mailbox @setParams
        Write-Host "    tagged: $mbx" -ForegroundColor Green
    }
}

Write-Host "`n=== 3. Management scope ===" -ForegroundColor Cyan
if (Get-ManagementScope -Identity $ScopeName -ErrorAction SilentlyContinue) {
    Write-Host '    already exists - skipping' -ForegroundColor DarkGray
} elseif ($PSCmdlet.ShouldProcess($ScopeName, 'New-ManagementScope')) {
    New-ManagementScope -Name $ScopeName -RecipientRestrictionFilter "$attr -eq '$Tag'" | Out-Null
}

Write-Host "`n=== 4. Scoped 'Application Mail.Send' role ===" -ForegroundColor Cyan
$existing = Get-ManagementRoleAssignment -RoleAssignee $AppId.Guid -Role 'Application Mail.Send' -ErrorAction SilentlyContinue |
    Where-Object { $_.CustomResourceScope -eq $ScopeName }
if ($existing) {
    Write-Host '    already assigned - skipping' -ForegroundColor DarkGray
} elseif ($PSCmdlet.ShouldProcess($AppName, "Assign 'Application Mail.Send' scoped to '$ScopeName'")) {
    New-ManagementRoleAssignment -App $AppId.Guid -Role 'Application Mail.Send' -CustomResourceScope $ScopeName | Out-Null
}

Write-Host "`n=== 5. Verifying ===" -ForegroundColor Cyan
Write-Host '-- should be InScope = True --' -ForegroundColor Yellow
foreach ($mbx in $Mailbox) {
    Test-ServicePrincipalAuthorization -Identity $AppId.Guid -Resource $mbx | Format-Table Name, RoleName, InScope, AllowedResourceScope
}
if ($NegativeTestMailbox) {
    Write-Host '-- should be InScope = False (proves everyone else is blocked) --' -ForegroundColor Yellow
    Test-ServicePrincipalAuthorization -Identity $AppId.Guid -Resource $NegativeTestMailbox | Format-Table Name, RoleName, InScope, AllowedResourceScope
} else {
    Write-Warning 'Pass -NegativeTestMailbox to prove that other mailboxes are blocked.'
}

Write-Host "`nDone. The permission cache can take 30 min (idle) to 2 h (active) to settle." -ForegroundColor Cyan
