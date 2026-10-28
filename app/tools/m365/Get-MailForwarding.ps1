param([hashtable]$P = @{})
# העברת מייל לכתובת חיצונית היא סימן קלאסי לתיבה שנפרצה
. (Join-Path $PSScriptRoot '_M365.ps1')
Connect-TkExchange
$domains = @(Get-AcceptedDomain | ForEach-Object { "$($_.DomainName)".ToLower() })
$found = 0
foreach ($m in Get-EXOMailbox -ResultSize Unlimited -Properties ForwardingSmtpAddress, ForwardingAddress, DeliverToMailboxAndForward) {
    $fw = "$($m.ForwardingSmtpAddress)" -replace '^smtp:', ''
    if (-not $fw -and $m.ForwardingAddress) { $fw = "$($m.ForwardingAddress)" }
    if (-not $fw) { continue }
    $found++
    $ext = ($fw -match '@') -and ($domains -notcontains ($fw.Split('@')[-1].ToLower()))
    [pscustomobject]@{ 'תיבה' = $m.PrimarySmtpAddress; 'מועבר אל' = $fw; 'סוג' = 'העברה ברמת התיבה'; 'שומר עותק' = $(if ($m.DeliverToMailboxAndForward) { 'כן' } else { 'לא' }); 'מצב' = $(if ($ext) { 'קריטי' } else { 'לבדוק' }) }
}
if ("$($P.Rules)" -eq 'כן') {
    Write-Host 'סורק כללי Inbox בכל התיבות. זה עשוי לקחת כמה דקות...' -ForegroundColor Cyan
    foreach ($m in Get-EXOMailbox -ResultSize Unlimited) {
        foreach ($r in Get-InboxRule -Mailbox $m.PrimarySmtpAddress -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -and ($_.ForwardTo -or $_.ForwardAsAttachmentTo -or $_.RedirectTo) }) {
            $found++
            $to = (@($r.ForwardTo) + @($r.ForwardAsAttachmentTo) + @($r.RedirectTo) | Where-Object { $_ }) -join ', '
            [pscustomobject]@{ 'תיבה' = $m.PrimarySmtpAddress; 'מועבר אל' = $to; 'סוג' = "כלל Inbox: $($r.Name)"; 'שומר עותק' = ''; 'מצב' = 'לבדוק' }
        }
    }
}
if ($found -eq 0) { [pscustomobject]@{ 'תיבה' = 'אין העברות מייל'; 'מועבר אל' = ''; 'סוג' = ''; 'שומר עותק' = ''; 'מצב' = 'תקין' } }
