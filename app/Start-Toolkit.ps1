#Requires -Version 5.1
# ארגז כלים IT · מפעיל ושרת מקומי
# שלב 1 (בלי -Serve, הרשאות רגילות): בוחר פורט וטוקן, מפעיל את השרת כמנהל ופותח חלון Edge (לא כמנהל)
# שלב 2 (-Serve, כמנהל): שרת HTTP על 127.0.0.1 בלבד, שמגיש את הממשק ומריץ את הכלים
param([switch]$Serve, [int]$Port = 0, [string]$Token = '', [switch]$NoBrowser)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Edge {
    foreach ($p in "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe") {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

# ======================= שלב 1: מפעיל =======================
if (-not $Serve) {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0); $l.Start(); $Port = $l.LocalEndpoint.Port; $l.Stop()
    $bytes = New-Object byte[] 24; (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $Token = ([Convert]::ToBase64String($bytes) -replace '[+/=]', '')
    $args2 = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Serve -Port $Port -Token $Token"
    $pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Start-Process powershell.exe -ArgumentList $args2 -WindowStyle Hidden }
    else { try { Start-Process powershell.exe -Verb RunAs -ArgumentList $args2 -WindowStyle Hidden } catch { return } }
    # מחכים שהשרת יעלה (עד 30 שניות)
    $ok = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        try { $c = New-Object System.Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $Port); $c.Close(); $ok = $true; break } catch {}
    }
    $url = "http://127.0.0.1:$Port/#t=$Token"
    if (-not $ok) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("השרת המקומי לא עלה. אפשר לפתוח את החלון הקלאסי: Run-Classic.cmd", 'ארגז כלים IT', 'OK', 'Error', 'OK', 'RtlReading') | Out-Null
        return
    }
    if ($NoBrowser) { Write-Output $url; return }
    $edge = Find-Edge
    if ($edge) {
        $prof = Join-Path $env:LOCALAPPDATA 'IT-Toolkit\edge-profile'
        Start-Process $edge -ArgumentList "--app=$url", "--user-data-dir=`"$prof`"", '--window-size=1480,920', '--no-first-run', '--disable-features=Translate'
    } else { Start-Process $url }
    return
}

# ======================= שלב 2: שרת =======================
$ErrorActionPreference = 'Continue'
Get-ChildItem $Root -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
Import-Module (Join-Path $Root 'modules\Toolkit.Core.psm1') -Force
$Config  = Get-TkConfig -Root $Root
$Catalog = Get-TkCatalog -Root $Root
$Web     = Join-Path $Root 'web'
$Jobs    = @{}
$script:Cred = $null
$script:LastPing = Get-Date
$script:Running = $true

$mime = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.json' = 'application/json; charset=utf-8'
           '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'; '.woff2' = 'font/woff2'; '.woff' = 'font/woff'; '.ttf' = 'font/ttf' }

function Send($ctx, [int]$code, [string]$body, [string]$type = 'application/json; charset=utf-8') {
    $b = [System.Text.Encoding]::UTF8.GetBytes($body)
    $r = $ctx.Response
    $r.StatusCode = $code; $r.ContentType = $type
    $r.Headers['Cache-Control'] = 'no-store'
    $r.Headers['X-Content-Type-Options'] = 'nosniff'
    $r.Headers['Content-Security-Policy'] = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; connect-src 'self'"
    $r.ContentLength64 = $b.Length
    try { $r.OutputStream.Write($b, 0, $b.Length) } catch {}
    try { $r.OutputStream.Close() } catch {}
}
function Send-Json($ctx, $obj, [int]$code = 200) { Send $ctx $code (ConvertTo-Json -InputObject $obj -Depth 8 -Compress) }
function Send-Err($ctx, [int]$code, [string]$msg) { Send-Json $ctx @{ error = $msg } $code }

function Read-Body($ctx) {
    if (-not $ctx.Request.HasEntityBody) { return $null }
    $sr = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
    $t = $sr.ReadToEnd(); $sr.Close()
    if (-not $t) { return $null }
    return ($t | ConvertFrom-Json)
}

function New-Cred($u, $p) {
    if (-not $u) { return $null }
    $sec = ConvertTo-SecureString "$p" -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential("$u", $sec)
}

function Get-Target($tool, [string]$t) {
    switch ($tool.runOn) {
        'dc'      { return "$($Config.DomainController)" }
        'local'   { return 'localhost' }
        'console' { return 'Office 365' }
        default   { if ([string]::IsNullOrWhiteSpace($t)) { return 'localhost' } return $t.Trim() }
    }
}

function Convert-Rows($objs) {
    $rows = ConvertTo-TkRows $objs
    $cols = New-Object System.Collections.ArrayList
    foreach ($r in $rows) { foreach ($p in $r.PSObject.Properties) { if (-not $cols.Contains($p.Name)) { [void]$cols.Add($p.Name) } } }
    $data = New-Object System.Collections.ArrayList
    foreach ($r in $rows) {
        $line = New-Object System.Collections.ArrayList
        foreach ($c in $cols) {
            $v = $r.$c
            if ($v -is [datetime]) { $v = $v.ToString('dd/MM/yyyy HH:mm') }
            [void]$line.Add($(if ($null -eq $v) { '' } else { "$v" }))
        }
        [void]$data.Add($line)
    }
    return @{ rows = $rows; columns = @($cols); data = @($data) }
}

function Get-History {
    $dir = Join-Path $Root 'logs'
    $f = Get-ChildItem $dir -Filter 'toolkit-*.log' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 2
    $lines = @(); foreach ($x in $f) { $lines += @(Get-Content $x.FullName -Encoding UTF8 -ErrorAction SilentlyContinue) }
    $lines = @($lines | Sort-Object -Descending | Select-Object -First 40)
    $names = @{}; foreach ($t in $Catalog.tools) { $names[$t.id] = $t.title }
    foreach ($l in $lines) {
        $p = $l -split ' \| '
        if ($p.Count -lt 7) { continue }
        @{ when = $p[0]; user = $p[1]; id = $p[2]; title = $(if ($names[$p[2]]) { $names[$p[2]] } else { $p[2] }); target = $p[3]; status = $p[5]; rows = ($p[6] -replace 'rows=', '') }
    }
}

function Handle-Api($ctx, [string]$path) {
    $req = $ctx.Request
    switch ($path) {
        '/api/ping' { $script:LastPing = Get-Date; Send-Json $ctx @{ ok = $true }; return }

        '/api/bootstrap' {
            $daily = $null
            $dl = Join-Path $Root 'reports\daily-latest.json'
            if (Test-Path $dl) { try { $daily = Get-Content $dl -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
            $targets = @('localhost') + @($Config.Servers | Where-Object { $_.Name } | ForEach-Object { "$($_.Name)" })
            if ($Config.DomainController -and $targets -notcontains "$($Config.DomainController)") { $targets += "$($Config.DomainController)" }
            foreach ($t in @($Config.Targets)) { if ($t -and $targets -notcontains "$t") { $targets += "$t" } }
            Send-Json $ctx @{
                org = "$($Config.OrgName)"; dc = "$($Config.DomainController)"; user = "$env:USERDOMAIN\$env:USERNAME"; computer = "$env:COMPUTERNAME"
                exampleConfig = ("$($Config.DomainController)" -eq 'DC-EXAMPLE'); targets = $targets
                servers = @($Config.Servers | Where-Object { $_.Name } | ForEach-Object { @{ name = "$($_.Name)"; roles = @($_.Roles) } })
                categories = @($Catalog.categories); tools = @($Catalog.tools)
                cred = $(if ($script:Cred) { $script:Cred.UserName } else { $null })
                daily = $daily; history = @(Get-History); vt = [bool]$Config.VirusTotalApiKey
            }
            return
        }

        '/api/cred' {
            $b = Read-Body $ctx
            if ($b.clear) { $script:Cred = $null } else { $script:Cred = New-Cred $b.user $b.password }
            Send-Json $ctx @{ cred = $(if ($script:Cred) { $script:Cred.UserName } else { $null }) }; return
        }

        '/api/run' {
            $b = Read-Body $ctx
            $tool = $Catalog.tools | Where-Object { $_.id -eq $b.toolId } | Select-Object -First 1
            if (-not $tool) { Send-Err $ctx 404 'כלי לא קיים'; return }
            if ($tool.risk -in 'change', 'sensitive' -and -not $b.confirmed) { Send-Err $ctx 400 'הפעולה דורשת אישור'; return }
            $running = @($Jobs.Values | Where-Object { $_.Job.State -in 'Running', 'NotStarted' })
            if ($running.Count -ge 4) { Send-Err $ctx 429 'כבר רצים 4 כלים במקביל. חכה שאחד יסתיים.'; return }
            $target = Get-Target $tool "$($b.target)"
            if ($tool.runOn -eq 'dc' -and -not $target) { Send-Err $ctx 400 'לא הוגדר DomainController ב-config.json'; return }
            $p = @{}
            foreach ($par in @($tool.params)) {
                if (-not $par) { continue }
                $v = $null; if ($b.params) { $v = $b.params."$($par.name)" }
                if ($par.type -eq 'credential') {
                    $c = New-Cred $v.user $v.password
                    if (-not $c -and $par.required) { Send-Err $ctx 400 "חסר: $($par.label)"; return }
                    $p[$par.name] = $c; continue
                }
                $v = "$v".Trim()
                if ($par.required -and -not $v) { Send-Err $ctx 400 "חסר: $($par.label)"; return }
                $p[$par.name] = $v
            }
            if ($tool.id -eq 'net-test' -and -not $p['Hosts']) { $p['Hosts'] = "$($b.target)".Trim() }
            if ($tool.id -eq 'net-winrm') { $p['Target'] = "$($b.target)".Trim() }
            $p['DiskWarn'] = [int]$Config.DiskWarnPercent; $p['DiskCrit'] = [int]$Config.DiskCriticalPercent; $p['SqlMaxHours'] = [int]$Config.SqlFullBackupMaxHours
            $srv = Get-TkServer $Config $target
            if ($srv) { if ($srv.SqlInstances) { $p['Instances'] = @($srv.SqlInstances) }; if ($srv.SqlDatabases) { $p['Databases'] = @($srv.SqlDatabases) }; if ($srv.SqlIgnoreDatabases) { $p['IgnoreDatabases'] = @($srv.SqlIgnoreDatabases) } }
            if ($Config.DefenderIgnoreThreats) { $p['IgnoreThreats'] = @($Config.DefenderIgnoreThreats) }
            if ($Config.VirusTotalApiKey) { $p['_VtKey'] = "$($Config.VirusTotalApiKey)" }
            if ($Config.StandardApps) { $p['StandardApps'] = @($Config.StandardApps) }
            try { $job = Start-TkTool -Root $Root -Tool $tool -Target $target -Params $p -Credential $script:Cred }
            catch { Send-Err $ctx 500 $_.Exception.Message; return }
            $id = [guid]::NewGuid().ToString('N').Substring(0, 12)
            $Jobs[$id] = @{ Job = $job; Tool = $tool; Target = $target; Params = $p; Start = Get-Date; Result = $null }
            Send-Json $ctx @{ id = $id; target = $target }; return
        }

        '/api/job' {
            $id = $req.QueryString['id']; $j = $Jobs[$id]
            if (-not $j) { Send-Err $ctx 404 'לא נמצא'; return }
            if (-not $j.Result) {
                $st = "$($j.Job.State)"
                if ($st -in 'Running', 'NotStarted') { Send-Json $ctx @{ state = 'running'; seconds = [int]((Get-Date) - $j.Start).TotalSeconds }; return }
                $out = Receive-Job $j.Job -ErrorAction SilentlyContinue -ErrorVariable jerr
                $errs = @()
                foreach ($cj in $j.Job.ChildJobs) { foreach ($e in $cj.Error) { $errs += "$e" } }
                foreach ($e in @($jerr)) { if ($e -and $errs -notcontains "$e") { $errs += "$e" } }
                if ($st -eq 'Failed' -and $j.Job.ChildJobs[0].JobStateInfo.Reason) { $m = $j.Job.ChildJobs[0].JobStateInfo.Reason.Message; if ($errs -notcontains $m) { $errs += $m } }
                Remove-Job $j.Job -Force -ErrorAction SilentlyContinue
                $conv = Convert-Rows $out
                $status = 'OK'; if ($st -eq 'Stopped') { $status = 'STOPPED' } elseif ($st -eq 'Failed' -or ($errs.Count -and $conv.rows.Count -eq 0)) { $status = 'FAILED' }
                $j.Result = @{ state = 'done'; status = $status; seconds = [int]((Get-Date) - $j.Start).TotalSeconds; columns = $conv.columns; data = $conv.data; errors = @($errs); saved = $null }
                $j.Rows = $conv.rows
                try { Write-TkLog -Root $Root -ToolId $j.Tool.id -Target $j.Target -Params $j.Params -Status $status -Rows $conv.rows.Count -ErrorText ($errs -join ' ') } catch {}
                if ($conv.rows.Count -gt 0 -and $j.Tool.id -eq 'rep-daily') {
                    $path = Join-Path $Root ('reports\daily-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.html')
                    Export-TkHtml -Rows $conv.rows -Title "צ'קליסט בוקר $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -Path $path | Out-Null
                    Save-TkDailyLatest -Root $Root -Rows $conv.rows; $j.Result.saved = $path
                }
                if ($conv.rows.Count -gt 0 -and $j.Tool.id -eq 'rep-inventory') {
                    $path = Join-Path $Root ('reports\inventory-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.csv')
                    $conv.rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8; $j.Result.saved = $path
                }
            }
            Send-Json $ctx $j.Result; return
        }

        '/api/stop' {
            $b = Read-Body $ctx; $j = $Jobs["$($b.id)"]
            if ($j -and $j.Job) { Stop-Job $j.Job -ErrorAction SilentlyContinue }
            Send-Json $ctx @{ ok = $true }; return
        }

        '/api/export' {
            $b = Read-Body $ctx; $j = $Jobs["$($b.id)"]
            if (-not $j -or -not $j.Rows) { Send-Err $ctx 404 'אין תוצאות לייצוא'; return }
            if ($j.Tool.risk -eq 'sensitive' -and -not $b.confirmSensitive) { Send-Err $ctx 400 'צריך אישור לשמירת מידע רגיש'; return }
            $dir = Join-Path $Root 'reports'; if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
            $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $j.Tool.id
            if ($b.format -eq 'csv') {
                $path = Join-Path $dir "$stamp.csv"
                $j.Rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
            } else {
                $path = Join-Path $dir "$stamp.html"
                Export-TkHtml -Rows $j.Rows -Title "$($j.Tool.title) · $($j.Target)" -Path $path | Out-Null
            }
            Start-Process $path
            Send-Json $ctx @{ path = $path }; return
        }

        '/api/open' {
            $b = Read-Body $ctx; $t = "$($b.target)".Trim()
            if ($t -and $t -notmatch '^[A-Za-z0-9\.\-_]+$') { Send-Err $ctx 400 'שם יעד לא תקין'; return }
            switch ("$($b.kind)") {
                'rdp'     { if ($t -and -not (Test-TkLocal $t)) { Start-Process mstsc.exe "/v:$t" } }
                'mgmt'    { if (-not $t -or (Test-TkLocal $t)) { Start-Process compmgmt.msc } else { Start-Process compmgmt.msc "/computer=$t" } }
                'reports' { $d = Join-Path $Root 'reports'; if (-not (Test-Path $d)) { New-Item -ItemType Directory $d | Out-Null }; Start-Process explorer.exe $d }
                'logs'    { $d = Join-Path $Root 'logs'; if (-not (Test-Path $d)) { New-Item -ItemType Directory $d | Out-Null }; Start-Process explorer.exe $d }
                'config'  { Start-Process notepad.exe (Join-Path $Root 'config.json') }
                'file'    { $f = "$($b.path)"; if ($f -and $f.StartsWith((Join-Path $Root 'reports')) -and (Test-Path $f)) { Start-Process $f } }
            }
            Send-Json $ctx @{ ok = $true }; return
        }

        '/api/quit' { Send-Json $ctx @{ ok = $true }; $script:Running = $false; return }

        default { Send-Err $ctx 404 'לא קיים' }
    }
}

function Handle($ctx) {
    $req = $ctx.Request
    $path = $req.Url.AbsolutePath
    # הגנה מ-DNS rebinding: רק Host של 127.0.0.1 עם הפורט שלנו
    if ("$($req.Headers['Host'])" -ne "127.0.0.1:$Port") { Send-Err $ctx 403 'forbidden'; return }
    if ($path.StartsWith('/api/')) {
        if ("$($req.Headers['X-Tk-Token'])" -ne $Token) { Send-Err $ctx 401 'unauthorized'; return }
        if ($req.HttpMethod -eq 'POST' -and "$($req.ContentType)" -notlike 'application/json*') { Send-Err $ctx 415 'json only'; return }
        try { Handle-Api $ctx $path } catch { try { Send-Err $ctx 500 $_.Exception.Message } catch {} }
        return
    }
    # קבצים סטטיים
    if ($path -eq '/' -or -not $path) { $path = '/index.html' }
    $full = [System.IO.Path]::GetFullPath((Join-Path $Web $path.TrimStart('/')))
    if (-not $full.StartsWith([System.IO.Path]::GetFullPath($Web)) -or -not (Test-Path $full -PathType Leaf)) { $full = Join-Path $Web 'index.html' }
    $ext = [System.IO.Path]::GetExtension($full).ToLower()
    $type = $mime[$ext]; if (-not $type) { $type = 'application/octet-stream' }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    $r = $ctx.Response; $r.StatusCode = 200; $r.ContentType = $type; $r.ContentLength64 = $bytes.Length
    if ($ext -ne '.html') { $r.Headers['Cache-Control'] = 'max-age=86400' } else { $r.Headers['Cache-Control'] = 'no-store' }
    try { $r.OutputStream.Write($bytes, 0, $bytes.Length) } catch {}
    try { $r.OutputStream.Close() } catch {}
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
try {
    while ($script:Running -and $listener.IsListening) {
        $ar = $listener.BeginGetContext($null, $null)
        while (-not $ar.AsyncWaitHandle.WaitOne(1000)) {
            # החלון נסגר: אין Ping שלוש דקות, ואין כלי שרץ
            $busy = @($Jobs.Values | Where-Object { $_.Job -and "$($_.Job.State)" -in 'Running', 'NotStarted' }).Count
            if ($busy -eq 0 -and ((Get-Date) - $script:LastPing).TotalSeconds -gt 180) { $script:Running = $false; break }
        }
        if (-not $script:Running) { break }
        $ctx = $listener.EndGetContext($ar)
        Handle $ctx
    }
} finally {
    foreach ($j in $Jobs.Values) { if ($j.Job) { Stop-Job $j.Job -ErrorAction SilentlyContinue; Remove-Job $j.Job -Force -ErrorAction SilentlyContinue } }
    $listener.Stop(); $listener.Close()
}
