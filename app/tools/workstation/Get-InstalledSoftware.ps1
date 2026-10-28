param([hashtable]$P = @{})
$f = "$($P.Filter)".Trim()
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$seen = @{}
Get-ItemProperty $keys -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 -and -not $_.ParentKeyName } |
  Where-Object { -not $f -or $_.DisplayName -like "*$f*" -or $_.Publisher -like "*$f*" } |
  Sort-Object DisplayName | ForEach-Object {
    $k = "$($_.DisplayName)|$($_.DisplayVersion)"
    if ($seen[$k]) { return }; $seen[$k] = 1
    $d = "$($_.InstallDate)"
    if ($d -match '^\d{8}$') { $d = "$($d.Substring(6,2))/$($d.Substring(4,2))/$($d.Substring(0,4))" }
    [pscustomobject]@{ 'שם' = $_.DisplayName; 'גרסה' = $_.DisplayVersion; 'יצרן' = $_.Publisher; 'הותקן' = $d }
  }
