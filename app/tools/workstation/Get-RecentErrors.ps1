param([hashtable]$P = @{})
$days = 1; if ($P.Days) { $days = [double]$P.Days }
$since = (Get-Date).AddDays(-$days)
$ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = $since } -MaxEvents 3000 -ErrorAction SilentlyContinue)
if ($ev.Count -eq 0) {
    [pscustomobject]@{ 'יומן' = ''; 'מקור' = ''; 'מזהה' = ''; 'כמות' = 0; 'אחרון' = ''; 'מצב' = 'תקין'; 'הודעה' = "אין שגיאות מאז $($since.ToString('dd/MM HH:mm'))" }
    return
}
$ev | Group-Object LogName, ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 50 | ForEach-Object {
    $last = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
    $lvl = 'אזהרה'; if ($last.Level -eq 1) { $lvl = 'קריטי' }
    $msg = "$($last.Message)" -replace '\s+', ' '
    if ($msg.Length -gt 220) { $msg = $msg.Substring(0, 220) + '…' }
    [pscustomobject]@{
        'יומן' = $last.LogName; 'מקור' = $last.ProviderName; 'מזהה' = $last.Id; 'כמות' = $_.Count
        'אחרון' = $last.TimeCreated.ToString('dd/MM HH:mm'); 'מצב' = $lvl; 'הודעה' = $msg
    }
}
