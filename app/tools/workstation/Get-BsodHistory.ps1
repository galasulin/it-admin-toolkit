param([hashtable]$P = @{})
$since = (Get-Date).AddDays(-90)
$rows = @()
$bug = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; StartTime = $since } -ErrorAction SilentlyContinue |
       Where-Object { $_.ProviderName -match 'WER-SystemErrorReporting|BugCheck' }
foreach ($e in $bug) {
    $m = "$($e.Message)" -replace '\s+', ' '
    $code = ''; if ($m -match '0x[0-9a-fA-F]{8}') { $code = $Matches[0] }
    $rows += [pscustomobject]@{ 'תאריך' = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm'); 'סוג' = 'מסך כחול (BugCheck)'; 'קוד' = $code; 'מצב' = 'קריטי'; 'פרטים' = $m.Substring(0, [math]::Min(200, $m.Length)) }
}
$kp = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } -ErrorAction SilentlyContinue
foreach ($e in $kp) {
    $rows += [pscustomobject]@{ 'תאריך' = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm'); 'סוג' = 'כיבוי לא תקין (Kernel-Power 41)'; 'קוד' = ''; 'מצב' = 'אזהרה'; 'פרטים' = 'נפילת חשמל, תקיעה או כיבוי בכוח' }
}
$dump = Join-Path $env:SystemRoot 'Minidump'
if (Test-Path $dump) {
    foreach ($f in Get-ChildItem $dump -Filter *.dmp -ErrorAction SilentlyContinue) {
        $rows += [pscustomobject]@{ 'תאריך' = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'); 'סוג' = 'קובץ Minidump'; 'קוד' = ''; 'מצב' = 'לבדוק'; 'פרטים' = "$($f.FullName) ($([math]::Round($f.Length/1KB)) KB)" }
    }
}
if ($rows.Count -eq 0) { $rows += [pscustomobject]@{ 'תאריך' = ''; 'סוג' = 'אין קריסות ב-90 יום'; 'קוד' = ''; 'מצב' = 'תקין'; 'פרטים' = '' } }
$rows | Sort-Object 'תאריך' -Descending
