param([hashtable]$P = @{})
$grpName = (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
$members = @()
try {
    $members = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ N = $_.Name; T = "$($_.ObjectClass)"; S = "$($_.PrincipalSource)"; SID = "$($_.SID)" } }
} catch {
    # Get-LocalGroupMember נכשל כשיש SID יתום. נופלים ל-ADSI
    $g = [ADSI]"WinNT://$env:COMPUTERNAME/$grpName,group"
    foreach ($m in @($g.Invoke('Members'))) {
        $path = $m.GetType().InvokeMember('ADsPath', 'GetProperty', $null, $m, $null)
        $cls = $m.GetType().InvokeMember('Class', 'GetProperty', $null, $m, $null)
        $members += [pscustomobject]@{ N = ($path -replace '^WinNT://', '' -replace '/', '\'); T = $cls; S = ''; SID = '' }
    }
}
foreach ($m in $members) {
    $st = 'לבדוק'
    if ($m.SID -match '-500$' -or $m.N -match '\\(Domain Admins|מנהלי תחום)$' -or $m.SID -match '-512$') { $st = 'תקין' }
    if ($m.N -match '^S-1-') { $st = 'אזהרה' }
    [pscustomobject]@{ 'חבר' = $m.N; 'סוג' = $m.T; 'מקור' = $m.S; 'מצב' = $st; 'הערה' = $(if ($st -eq 'לבדוק') { 'האם הוא באמת צריך הרשאות מנהל?' } elseif ($st -eq 'אזהרה') { 'SID יתום (חשבון שנמחק)' } else { '' }) }
}
