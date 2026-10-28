# Toolkit.Core.psm1 - פונקציות ליבה: הגדרות, קטלוג, הרצה מקומית/מרחוק, לוג, ייצוא
Set-StrictMode -Off

function Get-TkConfig {
    param([string]$Root)
    $cfg = Join-Path $Root 'config.json'
    if (-not (Test-Path $cfg)) {
        Copy-Item (Join-Path $Root 'config.example.json') $cfg
    }
    $c = Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $c.DiskWarnPercent)       { $c | Add-Member -NotePropertyName DiskWarnPercent -NotePropertyValue 20 -Force }
    if (-not $c.DiskCriticalPercent)   { $c | Add-Member -NotePropertyName DiskCriticalPercent -NotePropertyValue 10 -Force }
    if (-not $c.SqlFullBackupMaxHours) { $c | Add-Member -NotePropertyName SqlFullBackupMaxHours -NotePropertyValue 26 -Force }
    return $c
}

function Get-TkCatalog {
    param([string]$Root)
    Get-Content (Join-Path $Root 'catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-TkLocal {
    param([string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $true }
    $t = $Target.Trim().ToLower()
    $names = @('.', 'localhost', '127.0.0.1', [Environment]::MachineName.ToLower())
    if ($env:USERDNSDOMAIN) { $names += ("$env:COMPUTERNAME.$env:USERDNSDOMAIN").ToLower() }
    return ($names -contains $t)
}

function Get-TkServer {
    param($Config, [string]$Name)
    foreach ($s in @($Config.Servers)) {
        if ($s -and $s.Name -and ($s.Name.ToLower() -eq $Name.ToLower())) { return $s }
    }
    return $null
}

function Start-TkTool {
    param(
        [string]$Root,
        $Tool,
        [string]$Target,
        [hashtable]$Params,
        [System.Management.Automation.PSCredential]$Credential
    )
    $file = Join-Path $Root ('tools\' + $Tool.file)
    if (-not (Test-Path $file)) { throw "קובץ הכלי לא נמצא: $file" }
    $isLocal = ($Tool.runOn -eq 'local') -or (Test-TkLocal $Target)

    if ($Tool.runOn -eq 'console') {
        # כלים שצריכים התחברות אינטראקטיבית (Office 365) רצים בחלון PowerShell גלוי
        return Start-Job -ArgumentList $file, $Params, $Root -ScriptBlock {
            param($file, $p, $root)
            $id = [guid]::NewGuid().ToString('N')
            $in = Join-Path $env:TEMP "tk-in-$id.json"
            $out = Join-Path $env:TEMP "tk-out-$id.json"
            $clean = @{}
            foreach ($k in $p.Keys) { if (-not "$k".StartsWith('_')) { $clean[$k] = $p[$k] } }
            $clean | ConvertTo-Json -Depth 5 | Set-Content -Path $in -Encoding UTF8
            $runner = Join-Path $root 'tools\_ConsoleRunner.ps1'
            $pr = Start-Process powershell.exe -PassThru -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$runner`" -Script `"$file`" -InFile `"$in`" -OutFile `"$out`""
            Remove-Item $in -ErrorAction SilentlyContinue
            if (Test-Path $out) {
                $data = Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
                Remove-Item $out -ErrorAction SilentlyContinue
                foreach ($d in @($data)) { $d }
            } else {
                throw "החלון נסגר בלי תוצאה (קוד יציאה $($pr.ExitCode))."
            }
        }
    }

    Start-Job -ArgumentList $file, $isLocal, $Target, $Params, $Credential, $Root -ScriptBlock {
        param($file, $isLocal, $target, $p, $cred, $root)
        if ($isLocal) {
            $p['_Root'] = $root
            $p['_Cred'] = $cred
            & $file $p
        } else {
            $clean = @{}
            foreach ($k in $p.Keys) { if (-not "$k".StartsWith('_')) { $clean[$k] = $p[$k] } }
            $a = @{ ComputerName = $target; FilePath = $file; ArgumentList = @(, $clean); ErrorAction = 'Stop' }
            if ($cred) { $a.Credential = $cred }
            Invoke-Command @a
        }
    }
}

function ConvertTo-TkRows {
    param($Objects)
    $skip = 'PSComputerName', 'RunspaceId', 'PSShowComputerName', 'PSSourceJobInstanceId'
    $out = New-Object System.Collections.ArrayList
    foreach ($o in @($Objects)) {
        if ($null -eq $o) { continue }
        if ($o -is [string] -or $o -is [ValueType]) {
            [void]$out.Add([pscustomobject]@{ 'פלט' = "$o" })
            continue
        }
        $h = [ordered]@{}
        foreach ($pr in $o.PSObject.Properties) {
            if ($skip -contains $pr.Name) { continue }
            $v = $pr.Value
            if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) { $v = (@($v) -join ', ') }
            $h[$pr.Name] = $v
        }
        if ($h.Count -gt 0) { [void]$out.Add([pscustomobject]$h) }
    }
    return , $out
}

function Write-TkLog {
    param([string]$Root, [string]$ToolId, [string]$Target, [hashtable]$Params, [string]$Status, [int]$Rows, [string]$ErrorText)
    $dir = Join-Path $Root 'logs'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $file = Join-Path $dir ('toolkit-' + (Get-Date -Format 'yyyy-MM') + '.log')
    $pp = @()
    $internal = 'DiskWarn', 'DiskCrit', 'SqlMaxHours', 'Instances', 'Databases', 'IgnoreDatabases', 'IgnoreThreats', 'StandardApps'
    if ($Params) { foreach ($k in $Params.Keys) { if (-not "$k".StartsWith('_') -and $internal -notcontains $k) { $v = $Params[$k]; if ($v -is [System.Management.Automation.PSCredential]) { $v = $v.UserName }; $pp += "$k=$v" } } }
    $line = '{0} | {1} | {2} | {3} | {4} | {5} | rows={6} | {7}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), "$env:USERDOMAIN\$env:USERNAME", $ToolId, $Target, ($pp -join '; '), $Status, $Rows, ($ErrorText -replace "[\r\n]+", ' ')
    Add-Content -Path $file -Value $line -Encoding UTF8
}

function Get-TkStatusClass {
    param([string]$s)
    switch -Regex ($s) {
        'קריטי|נכשל|שגיאה|אין חיבור' { return 'crit' }
        'אזהרה|לבדוק'                 { return 'warn' }
        'תקין|הצליח|בוצע'             { return 'ok' }
        default                       { return '' }
    }
}

function Export-TkHtml {
    param($Rows, [string]$Title, [string]$Path)
    $rows = @($Rows)
    $enc = { param($x) [System.Net.WebUtility]::HtmlEncode("$x") }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8"><title>$(& $enc $Title)</title>
<style>
body{font-family:'Segoe UI',Arial,sans-serif;background:#f4f6f9;color:#1d2733;margin:24px}
h1{font-size:22px;margin:0 0 4px}.meta{color:#5b6b7d;margin-bottom:16px;font-size:13px}
table{border-collapse:collapse;background:#fff;width:100%;font-size:13px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
th{background:#1f3a5f;color:#fff;text-align:right;padding:8px 10px;position:sticky;top:0}
td{padding:7px 10px;border-bottom:1px solid #e6eaef;vertical-align:top}
tr.crit td{background:#fde8e8}tr.warn td{background:#fff4e0}tr.ok td.st{color:#1b7a3e;font-weight:600}
tr.crit td.st{color:#b3261e;font-weight:700}tr.warn td.st{color:#a15c00;font-weight:700}
</style></head><body><h1>$(& $enc $Title)</h1>
<div class="meta">הופק: $(Get-Date -Format 'dd/MM/yyyy HH:mm') · על ידי: $env:USERNAME · שורות: $($rows.Count)</div>
"@)
    if ($rows.Count -gt 0) {
        $cols = @($rows[0].PSObject.Properties | ForEach-Object { $_.Name })
        [void]$sb.Append('<table><tr>')
        foreach ($c in $cols) { [void]$sb.Append('<th>' + (& $enc $c) + '</th>') }
        [void]$sb.Append('</tr>')
        foreach ($r in $rows) {
            $cls = Get-TkStatusClass "$($r.'מצב')"
            [void]$sb.Append("<tr class=`"$cls`">")
            foreach ($c in $cols) {
                $tdc = ''; if ($c -eq 'מצב') { $tdc = ' class="st"' }
                [void]$sb.Append("<td$tdc>" + (& $enc $r.$c) + '</td>')
            }
            [void]$sb.Append('</tr>')
        }
        [void]$sb.Append('</table>')
    } else { [void]$sb.Append('<p>אין נתונים.</p>') }
    [void]$sb.Append('</body></html>')
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
    return $Path
}

function Save-TkDailyLatest {
    param([string]$Root, $Rows)
    $dir = Join-Path $Root 'reports'; if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
    $cnt = @{ crit = 0; warn = 0; ok = 0 }
    foreach ($r in @($Rows)) { $c = Get-TkStatusClass "$($r.'מצב')"; if ($c) { $cnt[$c]++ } }
    $top = @(@($Rows) | Where-Object { (Get-TkStatusClass "$($_.'מצב')") -in 'crit', 'warn' } | Select-Object -First 8 | ForEach-Object { @{ server = "$($_.'שרת')"; item = "$($_.'פריט')"; status = "$($_.'מצב')"; details = "$($_.'פרטים')" } })
    $obj = @{ when = (Get-Date).ToString('dd/MM/yyyy HH:mm'); crit = $cnt.crit; warn = $cnt.warn; ok = $cnt.ok; top = $top }
    [System.IO.File]::WriteAllText((Join-Path $dir 'daily-latest.json'), (ConvertTo-Json $obj -Depth 5), (New-Object System.Text.UTF8Encoding $false))
}

Export-ModuleMember -Function *
