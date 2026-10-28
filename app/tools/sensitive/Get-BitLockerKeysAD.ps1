param([hashtable]$P = @{})
# רץ על ה-DC. מחפש לפי שם מחשב, או לפי 8 התווים הראשונים של ה-Key ID שמופיע במסך השחזור
Import-Module ActiveDirectory -ErrorAction Stop
$q = "$($P.Query)".Trim()
if (-not $q) { throw 'לא הוזן שם מחשב או Key ID' }
$objs = @()
if ($q -match '^[0-9A-Fa-f]{8}') {
    $objs = @(Get-ADObject -Filter "objectClass -eq 'msFVE-RecoveryInformation' -and Name -like '*{$($q.Substring(0,8))*'" -Properties 'msFVE-RecoveryPassword', whenCreated)
}
if ($objs.Count -eq 0) {
    $c = Get-ADComputer -Filter "Name -eq '$($q -replace "'", "''")'" -ErrorAction SilentlyContinue
    if ($c) { $objs = @(Get-ADObject -SearchBase $c.DistinguishedName -Filter "objectClass -eq 'msFVE-RecoveryInformation'" -Properties 'msFVE-RecoveryPassword', whenCreated) }
}
if ($objs.Count -eq 0) { [pscustomobject]@{ 'מחשב' = $q; 'Key ID' = ''; 'מפתח שחזור' = 'לא נמצא מפתח ב-AD. ייתכן שהמחשב לא מגבה ל-AD (צריך GPO).'; 'נשמר ב' = '' }; return }
foreach ($o in $objs | Sort-Object whenCreated -Descending) {
    $comp = (($o.DistinguishedName -split ',')[1]) -replace '^CN='
    $kid = ([regex]::Match($o.Name, '\{([0-9A-Fa-f\-]+)\}')).Groups[1].Value
    [pscustomobject]@{ 'מחשב' = $comp; 'Key ID' = $kid; 'מפתח שחזור' = $o.'msFVE-RecoveryPassword'; 'נשמר ב' = $o.whenCreated.ToString('dd/MM/yyyy HH:mm') }
}
