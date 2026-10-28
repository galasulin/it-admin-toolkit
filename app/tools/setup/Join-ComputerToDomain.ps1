param([hashtable]$P = @{})
$new = "$($P.NewName)".Trim().ToUpper()
$dom = "$($P.Domain)".Trim()
$cred = $P.DomainCred
$cs = Get-CimInstance Win32_ComputerSystem
function Emit($n, $s, $d) { [pscustomobject]@{ 'שלב' = $n; 'מצב' = $s; 'פרטים' = "$d" } }
if ($new -and $new.Length -gt 15) { throw 'שם מחשב מוגבל ל-15 תווים' }
if ($new -and $new -notmatch '^[A-Z0-9\-]+$') { throw 'שם מחשב: רק אותיות באנגלית, ספרות ומקף' }
$args2 = @{ Force = $true; ErrorAction = 'Stop' }
if ($dom -and -not $cs.PartOfDomain) {
    if (-not $cred) { throw 'חסר משתמש לצירוף לדומיין' }
    $args2.DomainName = $dom; $args2.Credential = $cred
    if ($new -and $new -ne $env:COMPUTERNAME) { $args2.NewName = $new }
    if ($P.OU) { $args2.OUPath = "$($P.OU)" }
    Add-Computer @args2
    Emit 'צירוף לדומיין' 'בוצע' "$dom$(if ($args2.NewName) { " · שם חדש: $new" })"
} elseif ($new -and $new -ne $env:COMPUTERNAME) {
    $r = @{ NewName = $new; Force = $true; ErrorAction = 'Stop' }
    if ($cs.PartOfDomain -and $cred) { $r.DomainCredential = $cred }
    Rename-Computer @r
    Emit 'שינוי שם' 'בוצע' "$env:COMPUTERNAME → $new"
} else { Emit 'אין שינוי' 'תקין' "המחשב כבר בדומיין $($cs.Domain) עם השם $env:COMPUTERNAME" }
Emit 'הבא בתור' 'לבדוק' 'נדרש אתחול כדי שהשינוי ייכנס לתוקף. הכלי לא מאתחל לבד. אפשר להשתמש ב"אתחול מתוזמן".'
