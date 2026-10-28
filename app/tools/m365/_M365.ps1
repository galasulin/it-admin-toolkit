# פונקציות משותפות לכלי Office 365 (רצים בחלון גלוי במחשב שלך)
function Use-TkModule([string]$Name) {
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "מתקין את המודול $Name (פעם אחת, למשתמש שלך בלבד)..." -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -Scope CurrentUser -Force | Out-Null }
        Install-Module $Name -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $Name -ErrorAction Stop
}
function Connect-TkExchange {
    Use-TkModule 'ExchangeOnlineManagement'
    $c = $null; try { $c = Get-ConnectionInformation -ErrorAction Stop | Where-Object { $_.State -eq 'Connected' } } catch {}
    if (-not $c) { Write-Host 'מתחבר ל-Exchange Online. תיפתח חלונית התחברות.' -ForegroundColor Cyan; Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop }
}
function Connect-TkGraph([string[]]$Scopes) {
    Use-TkModule 'Microsoft.Graph.Authentication'
    Write-Host 'מתחבר ל-Microsoft Graph. תיפתח חלונית התחברות.' -ForegroundColor Cyan
    Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
}
function Invoke-TkGraphAll([string]$Uri) {
    $all = @(); $next = $Uri
    while ($next) { $r = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject; $all += @($r.value); $next = $r.'@odata.nextLink' }
    return $all
}
