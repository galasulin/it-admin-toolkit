# הרצה בלי חלון של צ'קליסט הבוקר (מופעל ע"י המשימה המתוזמנת). שומר HTML, פותח אותו, ומציג התראה אם יש בעיות.
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $Root 'modules\Toolkit.Core.psm1') -Force
$null = Get-TkConfig -Root $Root
$rows = @(& (Join-Path $Root 'tools\reports\Invoke-DailyCheck.ps1') @{ _Root = $Root; _Cred = $null })
$path = Join-Path $Root ('reports\daily-' + (Get-Date -Format 'yyyyMMdd') + '.html')
Export-TkHtml -Rows $rows -Title "צ'קליסט בוקר $(Get-Date -Format 'dd/MM/yyyy')" -Path $path | Out-Null
Save-TkDailyLatest -Root $Root -Rows $rows
$bad = @($rows | Where-Object { $_.'מצב' -in 'קריטי', 'אין חיבור', 'שגיאה' }).Count
$warn = @($rows | Where-Object { $_.'מצב' -eq 'אזהרה' }).Count
Write-TkLog -Root $Root -ToolId 'rep-daily (scheduled)' -Target 'all' -Params @{} -Status 'OK' -Rows $rows.Count -ErrorText "critical=$bad warn=$warn"
Start-Process $path
if ($bad -gt 0 -or $warn -gt 0) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("צ'קליסט בוקר: $bad בעיות קריטיות, $warn אזהרות. הדוח נפתח בדפדפן.", 'ארגז כלים IT', 'OK', 'Warning', 'OK', 'RtlReading') | Out-Null
}
