param([hashtable]$P = @{})
. (Join-Path $PSScriptRoot '_M365.ps1')
Connect-TkExchange
$list = "$($P.List)".Trim()
if (-not $list) {
    Get-DistributionGroup -ResultSize Unlimited | Sort-Object DisplayName | ForEach-Object {
        [pscustomobject]@{ 'רשימה' = $_.DisplayName; 'כתובת' = $_.PrimarySmtpAddress; 'חבר' = ''; 'מייל' = ''; 'סוג' = 'רשימת תפוצה'; 'דרך' = '' }
    }
    return
}
$seen = @{}
function Expand($id, $via) {
    foreach ($m in Get-DistributionGroupMember -Identity $id -ResultSize Unlimited) {
        if ("$($m.RecipientType)" -match 'Group') {
            if ($seen["g:$($m.PrimarySmtpAddress)"]) { continue }; $seen["g:$($m.PrimarySmtpAddress)"] = 1
            Expand "$($m.PrimarySmtpAddress)" $m.DisplayName
            continue
        }
        $k = "$($m.PrimarySmtpAddress)".ToLower()
        if ($k -and $seen[$k]) { continue }; if ($k) { $seen[$k] = 1 }
        $type = switch -Regex ("$($m.RecipientType)") { 'MailContact' { 'איש קשר חיצוני' } 'UserMailbox' { 'משתמש' } 'Shared' { 'תיבה משותפת' } default { "$($m.RecipientType)" } }
        [pscustomobject]@{ 'רשימה' = $list; 'כתובת' = ''; 'חבר' = $m.DisplayName; 'מייל' = "$($m.PrimarySmtpAddress)"; 'סוג' = $type; 'דרך' = $via }
    }
}
Expand $list 'ישיר'
