param([hashtable]$P = @{})
. (Join-Path $PSScriptRoot '_M365.ps1')
Connect-TkExchange
$i = 0
$all = @(Get-EXOMailbox -ResultSize Unlimited -Properties ProhibitSendQuota)
foreach ($m in $all) {
    $i++; Write-Progress -Activity 'גודל תיבות' -Status $m.PrimarySmtpAddress -PercentComplete ($i / [math]::Max(1, $all.Count) * 100)
    $s = Get-EXOMailboxStatistics -Identity $m.PrimarySmtpAddress -Properties LastLogonTime -ErrorAction SilentlyContinue
    $gb = 0; if ("$($s.TotalItemSize)" -match '\(([\d,]+) bytes\)') { $gb = [math]::Round(([double]($Matches[1] -replace ',', '')) / 1GB, 2) }
    $q = 0; if ("$($m.ProhibitSendQuota)" -match '\(([\d,]+) bytes\)') { $q = [math]::Round(([double]($Matches[1] -replace ',', '')) / 1GB, 1) }
    $pct = 0; if ($q -gt 0) { $pct = [math]::Round($gb / $q * 100) }
    $st = 'תקין'; if ($pct -ge 95) { $st = 'קריטי' } elseif ($pct -ge 85) { $st = 'אזהרה' }
    $last = ''; if ($s.LastLogonTime) { $last = ([datetime]$s.LastLogonTime).ToString('dd/MM/yyyy') }
    if ($s.LastLogonTime -and ((Get-Date) - [datetime]$s.LastLogonTime).TotalDays -gt 90 -and $st -eq 'תקין') { $st = 'לבדוק' }
    [pscustomobject]@{ 'תיבה' = $m.PrimarySmtpAddress; 'שם' = $m.DisplayName; 'סוג' = "$($m.RecipientTypeDetails)"; 'גודל GB' = $gb; 'מכסה GB' = $q; 'ניצול %' = $pct; 'פריטים' = $s.ItemCount; 'כניסה אחרונה' = $last; 'מצב' = $st }
}
