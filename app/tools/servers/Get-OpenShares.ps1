param([hashtable]$P = @{})
$wide = 'Everyone|Authenticated Users|Domain Users|כולם|משתמשים מאומתים'
$shares = @(Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '\$$' })
if ($shares.Count -eq 0) { [pscustomobject]@{ 'שיתוף' = 'אין שיתופים (חוץ משיתופי מערכת כמו C$)'; 'נתיב' = ''; 'חשבון' = ''; 'הרשאה' = ''; 'סוג' = ''; 'מצב' = 'תקין' }; return }
foreach ($s in $shares) {
    foreach ($a in Get-SmbShareAccess -Name $s.Name -ErrorAction SilentlyContinue) {
        $st = 'תקין'
        if ($a.AccountName -match $wide -and $a.AccessRight -in 'Full', 'Change' -and $a.AccessControlType -eq 'Allow') { $st = 'לבדוק' }
        [pscustomobject]@{ 'שיתוף' = $s.Name; 'נתיב' = $s.Path; 'חשבון' = $a.AccountName; 'הרשאה' = "$($a.AccessRight)"; 'סוג' = "$($a.AccessControlType)"; 'מצב' = $st }
    }
}
