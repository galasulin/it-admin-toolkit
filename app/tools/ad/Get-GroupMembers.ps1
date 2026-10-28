param([hashtable]$P = @{})
Import-Module ActiveDirectory -ErrorAction Stop
$g = "$($P.Group)".Trim()
$grp = Get-ADGroup -Identity $g -ErrorAction Stop
foreach ($m in Get-ADGroupMember -Identity $grp -Recursive -ErrorAction Stop | Sort-Object Name) {
    $en = ''; $last = ''
    if ($m.objectClass -eq 'user') {
        $u = Get-ADUser $m -Properties Enabled, LastLogonDate
        $en = $(if ($u.Enabled) { 'כן' } else { 'לא' })
        if ($u.LastLogonDate) { $last = $u.LastLogonDate.ToString('dd/MM/yyyy') }
    }
    [pscustomobject]@{ 'קבוצה' = $grp.Name; 'חבר' = $m.Name; 'שם משתמש' = $m.SamAccountName; 'סוג' = $m.objectClass; 'פעיל' = $en; 'כניסה אחרונה' = $last }
}
