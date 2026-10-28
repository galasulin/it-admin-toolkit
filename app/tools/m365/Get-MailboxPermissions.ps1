param([hashtable]$P = @{})
. (Join-Path $PSScriptRoot '_M365.ps1')
Connect-TkExchange
$mb = "$($P.Mailbox)".Trim()
$targets = if ($mb) { @(Get-EXOMailbox -Identity $mb) } else { @(Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails SharedMailbox) }
foreach ($t in $targets) {
    foreach ($item in Get-EXOMailboxPermission -Identity $t.PrimarySmtpAddress | Where-Object { $_.User -notmatch '^NT AUTHORITY|^S-1-5' -and -not $_.IsInherited }) {
        [pscustomobject]@{ 'תיבה' = $t.PrimarySmtpAddress; 'סוג תיבה' = "$($t.RecipientTypeDetails)"; 'מי' = $item.User; 'הרשאה' = ($item.AccessRights -join ', ') }
    }
    foreach ($item in Get-EXORecipientPermission -Identity $t.PrimarySmtpAddress | Where-Object { $_.Trustee -notmatch '^NT AUTHORITY' }) {
        [pscustomobject]@{ 'תיבה' = $t.PrimarySmtpAddress; 'סוג תיבה' = "$($t.RecipientTypeDetails)"; 'מי' = $item.Trustee; 'הרשאה' = 'SendAs' }
    }
    foreach ($s in @($t.GrantSendOnBehalfTo)) { if ($s) { [pscustomobject]@{ 'תיבה' = $t.PrimarySmtpAddress; 'סוג תיבה' = "$($t.RecipientTypeDetails)"; 'מי' = $s; 'הרשאה' = 'SendOnBehalf' } } }
}
