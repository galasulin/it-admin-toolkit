param([hashtable]$P = @{})
function Get-WingetPath {
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue; if ($c) { return $c.Source }
    $d = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($d -and (Test-Path (Join-Path $d.FullName 'winget.exe'))) { return (Join-Path $d.FullName 'winget.exe') }
}
$wg = Get-WingetPath
if (-not $wg) { throw 'winget לא מותקן במחשב (App Installer מה-Store). ב-Windows 10 ישן צריך לעדכן אותו קודם.' }
$apps = @("$($P.Apps)" -split '[,; ]+' | Where-Object { $_ })
if ($apps.Count -eq 0) { $apps = @($P.StandardApps) }
if ($apps.Count -eq 0) { throw 'לא הוגדרו תוכנות. להוסיף StandardApps ב-config.json או להזין מזהי winget.' }
foreach ($a in $apps) {
    $out = & $wg install --id $a --exact --silent --scope machine --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    $code = $LASTEXITCODE
    $st = 'נכשל'
    if ($code -eq 0) { $st = 'בוצע' } elseif ($out -match 'already installed|כבר מותקן|No available upgrade') { $st = 'תקין' }
    $last = (($out -split "`r?`n") | Where-Object { $_.Trim() -and $_ -notmatch '^[\s\-\\|/]+$' } | Select-Object -Last 1)
    [pscustomobject]@{ 'תוכנה' = $a; 'מצב' = $st; 'פרטים' = "$last".Trim() }
}
