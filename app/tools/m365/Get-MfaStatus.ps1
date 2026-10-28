﻿param([hashtable]$P = @{})
. (Join-Path $PSScriptRoot '_M365.ps1')
Connect-TkGraph @('UserAuthenticationMethod.Read.All', 'User.Read.All', 'Directory.Read.All', 'AuditLog.Read.All')

# מנהלים: כל מי שחבר בתפקיד ניהולי פעיל ב-Entra
$admins = @{}
try {
    foreach ($r in Invoke-TkGraphAll 'https://graph.microsoft.com/v1.0/directoryRoles?$expand=members') {
        foreach ($m in @($r.members)) { if ($m.userPrincipalName) { $admins["$($m.userPrincipalName)".ToLower()] = $r.displayName } }
    }
} catch {}

$rows = $null
try {
    # דרך מהירה: הדוח המרוכז (דורש Entra ID P1)
    $rows = Invoke-TkGraphAll 'https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails'
} catch { $rows = $null }

if ($rows) {
    foreach ($r in $rows | Sort-Object userDisplayName) {
        $isAdm = $r.isAdmin -or $admins.ContainsKey("$($r.userPrincipalName)".ToLower())
        $st = 'תקין'; if (-not $r.isMfaRegistered) { $st = 'קריטי' }
        [pscustomobject]@{ 'משתמש' = $r.userDisplayName; 'UPN' = $r.userPrincipalName; 'MFA רשום' = $(if ($r.isMfaRegistered) { 'כן' } else { 'לא' }); 'שיטות' = (@($r.methodsRegistered) -join ', '); 'מנהל' = $(if ($isAdm) { 'כן' } else { '' }); 'מצב' = $st }
    }
    return
}

# דרך חלופית בלי P1: בודקים את שיטות האימות של כל משתמש פעיל עם רישיון
Write-Host 'הדוח המרוכז לא זמין בלי Entra ID P1. בודק משתמש אחרי משתמש (לוקח כדקה)...' -ForegroundColor Cyan
$users = @(Invoke-TkGraphAll 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,accountEnabled,assignedLicenses&$top=999' |
           Where-Object { $_.accountEnabled -and @($_.assignedLicenses).Count -gt 0 })
$names = @{ 'microsoftAuthenticatorAuthenticationMethod' = 'Authenticator'; 'phoneAuthenticationMethod' = 'טלפון'; 'fido2AuthenticationMethod' = 'FIDO2'
            'softwareOathAuthenticationMethod' = 'קוד OTP'; 'windowsHelloForBusinessAuthenticationMethod' = 'Windows Hello'; 'emailAuthenticationMethod' = 'מייל'
            'passwordAuthenticationMethod' = 'סיסמה'; 'temporaryAccessPassAuthenticationMethod' = 'TAP' }
$strong = 'microsoftAuthenticator|phone|fido2|softwareOath|windowsHello'
$i = 0
foreach ($u in $users | Sort-Object displayName) {
    $i++; Write-Progress -Activity 'MFA' -Status $u.userPrincipalName -PercentComplete ($i / [math]::Max(1, $users.Count) * 100)
    $types = @()
    try { $types = @(Invoke-TkGraphAll "https://graph.microsoft.com/v1.0/users/$($u.id)/authentication/methods" | ForEach-Object { ("$($_.'@odata.type')" -replace '^#microsoft\.graph\.', '') }) } catch {}
    $has = [bool](@($types | Where-Object { $_ -match $strong }).Count)
    $isAdm = $admins.ContainsKey("$($u.userPrincipalName)".ToLower())
    $st = 'תקין'; if (-not $has) { $st = 'קריטי' }
    $shown = @($types | ForEach-Object { $n = $names[$_]; if ($n) { $n } else { $_ } }) | Select-Object -Unique
    [pscustomobject]@{ 'משתמש' = $u.displayName; 'UPN' = $u.userPrincipalName; 'MFA רשום' = $(if ($has) { 'כן' } else { 'לא' }); 'שיטות' = ($shown -join ', '); 'מנהל' = $(if ($isAdm) { "כן ($($admins["$($u.userPrincipalName)".ToLower()]))" } else { '' }); 'מצב' = $st }
}
