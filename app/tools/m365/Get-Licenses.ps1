param([hashtable]$P = @{})
. (Join-Path $PSScriptRoot '_M365.ps1')
Connect-TkGraph @('Organization.Read.All', 'User.Read.All', 'AuditLog.Read.All')
$names = @{ 'O365_BUSINESS_PREMIUM' = 'Microsoft 365 Business Standard'; 'SPB' = 'Microsoft 365 Business Premium'; 'O365_BUSINESS_ESSENTIALS' = 'Microsoft 365 Business Basic'; 'EXCHANGESTANDARD' = 'Exchange Online (Plan 1)'; 'EXCHANGEENTERPRISE' = 'Exchange Online (Plan 2)'; 'ENTERPRISEPACK' = 'Office 365 E3'; 'SPE_E3' = 'Microsoft 365 E3'; 'FLOW_FREE' = 'Power Automate Free'; 'POWER_BI_STANDARD' = 'Power BI Free'; 'TEAMS_EXPLORATORY' = 'Teams Exploratory'; 'O365_BUSINESS' = 'Microsoft 365 Apps for Business' }
$skus = Invoke-TkGraphAll 'https://graph.microsoft.com/v1.0/subscribedSkus'
$skuName = @{}
foreach ($s in $skus) {
    $n = $names["$($s.skuPartNumber)"]; if (-not $n) { $n = $s.skuPartNumber }
    $skuName["$($s.skuId)"] = $n
    $tot = [int]$s.prepaidUnits.enabled; $used = [int]$s.consumedUnits
    $st = 'תקין'; if ($tot -gt 0 -and $used -ge $tot) { $st = 'אזהרה' }
    if ($tot -gt 0 -and $tot -lt 1000 -and ($tot - $used) -ge 3) { $st = 'לבדוק' }   # מוצרים חינמיים מגיעים עם אלפי יחידות, לא בזבוז
    [pscustomobject]@{ 'סוג' = 'רישיון'; 'שם' = $n; 'פרט' = "בשימוש $used מתוך $tot · פנויים $($tot - $used)"; 'כניסה אחרונה' = ''; 'מצב' = $st }
}
$sel = 'displayName,userPrincipalName,accountEnabled,assignedLicenses'
$users = @()
try { $users = Invoke-TkGraphAll "https://graph.microsoft.com/v1.0/users?`$select=$sel,signInActivity&`$top=999" } catch { $users = Invoke-TkGraphAll "https://graph.microsoft.com/v1.0/users?`$select=$sel&`$top=999" }
foreach ($u in $users | Where-Object { @($_.assignedLicenses).Count -gt 0 } | Sort-Object displayName) {
    $lic = (@($u.assignedLicenses) | ForEach-Object { $skuName["$($_.skuId)"] }) -join ', '
    $last = ''; $d = $u.signInActivity.lastSignInDateTime
    if ($d) { $last = ([datetime]$d).ToString('dd/MM/yyyy') }
    $st = 'תקין'
    if (-not $u.accountEnabled) { $st = 'קריטי' } elseif ($d -and ((Get-Date) - [datetime]$d).TotalDays -gt 60) { $st = 'לבדוק' }
    [pscustomobject]@{ 'סוג' = 'משתמש'; 'שם' = "$($u.displayName) · $($u.userPrincipalName)"; 'פרט' = $lic + $(if (-not $u.accountEnabled) { ' · חשבון חסום עם רישיון (כסף מבוזבז)' } else { '' }); 'כניסה אחרונה' = $last; 'מצב' = $st }
}
