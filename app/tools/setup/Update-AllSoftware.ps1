param([hashtable]$P = @{})
function Get-WingetPath {
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue; if ($c) { return $c.Source }
    $d = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($d -and (Test-Path (Join-Path $d.FullName 'winget.exe'))) { return (Join-Path $d.FullName 'winget.exe') }
}
$wg = Get-WingetPath
if (-not $wg) { throw 'winget לא מותקן במחשב' }
$only = @("$($P.Ids)" -split '[,; ]+' | Where-Object { $_ })
$common = '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
if ($only.Count -gt 0) {
    foreach ($id in $only) {
        $o = & $wg upgrade --id $id --exact @common 2>&1 | Out-String
        [pscustomobject]@{ 'תוכנה' = $id; 'מצב' = $(if ($LASTEXITCODE -eq 0) { 'בוצע' } else { "נכשל ($LASTEXITCODE)" }); 'פרטים' = (($o -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 1) }
    }
} else {
    $o = & $wg upgrade --all @common 2>&1 | Out-String
    $ok = ([regex]::Matches($o, 'Successfully installed|הותקן בהצלחה')).Count
    [pscustomobject]@{ 'תוכנה' = 'הכול'; 'מצב' = $(if ($LASTEXITCODE -eq 0) { 'בוצע' } else { 'אזהרה' }); 'פרטים' = "$ok עודכנו בהצלחה · קוד $LASTEXITCODE" }
}
