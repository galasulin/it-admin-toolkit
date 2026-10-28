#Requires -Version 5.1
# ארגז כלים IT - חלון ראשי
# הפעלה: Run.cmd (מריץ כמנהל עם ExecutionPolicy Bypass לתהליך הזה בלבד)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- הרצה כמנהל ---
$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`""
    return
}

Get-ChildItem $Root -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, Microsoft.VisualBasic
trap {
    [System.Windows.MessageBox]::Show("שגיאה בהפעלת הכלי:`n`n$($_.Exception.Message)`n`n$($_.InvocationInfo.PositionMessage)", 'ארגז כלים IT', 'OK', 'Error', 'OK', 'RtlReading') | Out-Null
    break
}
Import-Module (Join-Path $Root 'modules\Toolkit.Core.psm1') -Force

$Config  = Get-TkConfig -Root $Root
$Catalog = Get-TkCatalog -Root $Root

[xml]$xaml = Get-Content (Join-Path $Root 'ui\MainWindow.xaml') -Raw -Encoding UTF8
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'txtTitle','txtSubtitle','cmbTarget','btnTest','btnRdp','btnMgmt','btnCred','txtCred','txtSearch','tvTools','txtToolTitle','txtToolDesc',
               'bdRisk','txtRisk','txtRunOn','btnRun','btnStop','btnHtml','btnCsv','btnCopy','btnLogs','dgResults','txtLog','pbBusy','txtStatus') {
    $ui[$n] = $win.FindName($n)
}

$script:Tool = $null
$script:Job = $null
$script:JobMeta = $null
$script:Cred = $null
$script:Rows = $null
$script:RowsTitle = ''

$brush = { param($hex) (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex) }

function Add-UiLog([string]$m) {
    $ui.txtLog.AppendText(('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) + "`r`n")
    $ui.txtLog.ScrollToEnd()
}

function Show-Msg([string]$text, [string]$icon = 'Information', [string]$buttons = 'OK') {
    [System.Windows.MessageBox]::Show($win, $text, 'ארגז כלים IT', $buttons, $icon, 'None', 'RtlReading')
}

# --- כותרת ויעדים ---
$ui.txtTitle.Text = 'ארגז כלים IT · ' + $Config.OrgName
$ui.txtSubtitle.Text = "מחובר כ: $env:USERDOMAIN\$env:USERNAME · מחשב: $env:COMPUTERNAME"
[void]$ui.cmbTarget.Items.Add('localhost')
foreach ($s in @($Config.Servers)) { if ($s.Name) { [void]$ui.cmbTarget.Items.Add($s.Name) } }
if ($Config.DomainController -and -not ($ui.cmbTarget.Items -contains $Config.DomainController)) { [void]$ui.cmbTarget.Items.Add($Config.DomainController) }
foreach ($t in @($Config.Targets)) { if ($t -and -not ($ui.cmbTarget.Items -contains $t)) { [void]$ui.cmbTarget.Items.Add($t) } }
$ui.cmbTarget.Text = 'localhost'

# --- עץ הכלים ---
function Update-ToolTree([string]$filter) {
    $ui.tvTools.Items.Clear()
    foreach ($cat in $Catalog.categories) {
        $tools = @($Catalog.tools | Where-Object { $_.category -eq $cat })
        if ($filter) { $tools = @($tools | Where-Object { $_.title -like "*$filter*" -or $_.desc -like "*$filter*" -or $_.id -like "*$filter*" }) }
        if ($tools.Count -eq 0) { continue }
        $node = New-Object System.Windows.Controls.TreeViewItem
        $node.Header = "$cat  ($($tools.Count))"
        $node.FontWeight = 'SemiBold'
        $node.IsExpanded = [bool]$filter -or ($cat -eq $Catalog.categories[0])
        foreach ($t in $tools) {
            $leaf = New-Object System.Windows.Controls.TreeViewItem
            $mark = ''
            if ($t.risk -eq 'change') { $mark = '  ✎' } elseif ($t.risk -eq 'sensitive') { $mark = '  🔒' }
            $leaf.Header = $t.title + $mark
            $leaf.Tag = $t.id
            $leaf.FontWeight = 'Normal'
            $leaf.Padding = '2,3'
            [void]$node.Items.Add($leaf)
        }
        [void]$ui.tvTools.Items.Add($node)
    }
}

function Select-Tool($tool) {
    $script:Tool = $tool
    $ui.txtToolTitle.Text = $tool.title
    $ui.txtToolDesc.Text = $tool.desc
    switch ($tool.risk) {
        'change'    { $ui.txtRisk.Text = 'מבצע שינוי · יבקש אישור';           $ui.bdRisk.Background = (& $brush '#FFE7C2') }
        'sensitive' { $ui.txtRisk.Text = 'מידע רגיש · מוצג רק על המסך';       $ui.bdRisk.Background = (& $brush '#F3D9FA') }
        default     { $ui.txtRisk.Text = 'קריאה בלבד · לא משנה כלום';        $ui.bdRisk.Background = (& $brush '#D7F2DF') }
    }
    switch ($tool.runOn) {
        'dc'    { $ui.txtRunOn.Text = "רץ על: בקר הדומיין ($($Config.DomainController))" }
        'local'   { $ui.txtRunOn.Text = 'רץ מ: המחשב הזה' }
        'console' { $ui.txtRunOn.Text = 'רץ מ: המחשב הזה, בחלון נפרד להתחברות ל-Office 365' }
        default   { $ui.txtRunOn.Text = 'רץ על: היעד שנבחר למעלה' }
    }
    $ui.btnRun.IsEnabled = ($null -eq $script:Job)
}

$ui.tvTools.Add_SelectedItemChanged({
    $sel = $ui.tvTools.SelectedItem
    if ($sel -and $sel.Tag) {
        $t = $Catalog.tools | Where-Object { $_.id -eq $sel.Tag } | Select-Object -First 1
        if ($t) { Select-Tool $t }
    }
})
$ui.txtSearch.Add_TextChanged({ Update-ToolTree $ui.txtSearch.Text.Trim() })

# --- הרצה ---
function Get-ToolTarget($tool) {
    switch ($tool.runOn) {
        'dc'    { return "$($Config.DomainController)" }
        'local'   { return 'localhost' }
        'console' { return 'Office 365' }
        default {
            $t = "$($ui.cmbTarget.Text)".Trim()
            if (-not $t) { $t = 'localhost' }
            return $t
        }
    }
}

function Invoke-SelectedTool($tool) {
    if ($script:Job) { Show-Msg 'כלי אחר עדיין רץ. חכה שיסתיים או לחץ "עצור".' 'Warning'; return }
    $target = Get-ToolTarget $tool
    if ($tool.runOn -eq 'dc' -and -not $target) { Show-Msg 'לא הוגדר DomainController בקובץ config.json.' 'Warning'; return }

    # פרמטרים
    $p = @{}
    foreach ($par in @($tool.params)) {
        if (-not $par) { continue }
        if ($par.type -eq 'credential') {
            $c = Get-Credential -Message $par.label
            if (-not $c) { Add-UiLog "בוטל: $($tool.title)"; return }
            $p[$par.name] = $c
            continue
        }
        $v = [Microsoft.VisualBasic.Interaction]::InputBox($par.label, $tool.title, "$($par.default)")
        if ($par.required -and [string]::IsNullOrWhiteSpace($v)) { Add-UiLog "בוטל: $($tool.title)"; return }
        $p[$par.name] = $v.Trim()
    }
    if ($tool.id -eq 'net-test' -and -not $p['Hosts']) { $p['Hosts'] = "$($ui.cmbTarget.Text)".Trim() }
    if ($tool.id -eq 'net-winrm') { $p['Target'] = "$($ui.cmbTarget.Text)".Trim() }

    # הגדרות מתוך config
    $p['DiskWarn'] = [int]$Config.DiskWarnPercent
    $p['DiskCrit'] = [int]$Config.DiskCriticalPercent
    $p['SqlMaxHours'] = [int]$Config.SqlFullBackupMaxHours
    $srv = Get-TkServer $Config $target
    if ($srv) {
        if ($srv.SqlInstances) { $p['Instances'] = @($srv.SqlInstances) }
        if ($srv.SqlDatabases) { $p['Databases'] = @($srv.SqlDatabases) }
        if ($srv.SqlIgnoreDatabases) { $p['IgnoreDatabases'] = @($srv.SqlIgnoreDatabases) }
    }
    if ($Config.DefenderIgnoreThreats) { $p['IgnoreThreats'] = @($Config.DefenderIgnoreThreats) }
    if ($Config.VirusTotalApiKey) { $p['_VtKey'] = "$($Config.VirusTotalApiKey)" }
    if ($Config.StandardApps) { $p['StandardApps'] = @($Config.StandardApps) }

    # אישור לפני שינוי / מידע רגיש
    if ($tool.risk -eq 'change' -or $tool.risk -eq 'sensitive') {
        $pp = (@($p.Keys | Where-Object { -not "$_".StartsWith('_') -and @('DiskWarn','DiskCrit','SqlMaxHours','Instances','Databases','StandardApps') -notcontains $_ } |
                ForEach-Object { if ($p[$_] -is [System.Management.Automation.PSCredential]) { "$_ = $($p[$_].UserName)" } else { "$_ = $($p[$_])" } }) -join "`n")
        $what = $tool.actions
        if (-not $what) { $what = $tool.desc }
        $head = 'לבצע את הפעולה?'
        if ($tool.risk -eq 'sensitive') { $head = 'הכלי יציג מידע רגיש על המסך. לוודא שאף אחד לא רואה את המסך שלך.' }
        $msg = "$head`n`nכלי: $($tool.title)`nיעד: $target`n`nמה יקרה:`n$what"
        if ($pp) { $msg += "`n`nפרמטרים:`n$pp" }
        if ((Show-Msg $msg 'Warning' 'YesNo') -ne 'Yes') { Add-UiLog "בוטל על ידך: $($tool.title)"; return }
    }

    try {
        $script:Job = Start-TkTool -Root $Root -Tool $tool -Target $target -Params $p -Credential $script:Cred
    } catch {
        Add-UiLog "שגיאה בהפעלה: $($_.Exception.Message)"; return
    }
    $script:JobMeta = @{ Tool = $tool; Target = $target; Params = $p; Start = Get-Date }
    $ui.btnRun.IsEnabled = $false; $ui.btnStop.IsEnabled = $true
    $ui.pbBusy.Visibility = 'Visible'
    $ui.txtStatus.Text = "רץ: $($tool.title) על $target ..."
    Add-UiLog "התחלה: $($tool.title) → $target"
    $timer.Start()
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(500)
$timer.Add_Tick({
    $j = $script:Job
    if (-not $j) { $timer.Stop(); return }
    if ($j.State -in 'Running', 'NotStarted') {
        $sec = [int]((Get-Date) - $script:JobMeta.Start).TotalSeconds
        $ui.txtStatus.Text = "רץ: $($script:JobMeta.Tool.title) על $($script:JobMeta.Target) ... ($sec שניות)"
        return
    }
    $timer.Stop()
    $meta = $script:JobMeta
    $out = Receive-Job $j -ErrorAction SilentlyContinue -ErrorVariable jobErr
    $errText = ''
    foreach ($cj in $j.ChildJobs) { foreach ($e in $cj.Error) { $errText += $e.ToString() + ' ' } }
    foreach ($e in @($jobErr)) { if ($e) { $errText += $e.ToString() + ' ' } }
    if ($j.State -eq 'Failed' -and $j.ChildJobs[0].JobStateInfo.Reason) { $errText += $j.ChildJobs[0].JobStateInfo.Reason.Message }
    $state = "$($j.State)"
    Remove-Job $j -Force -ErrorAction SilentlyContinue
    $script:Job = $null

    $rows = ConvertTo-TkRows $out
    $script:Rows = $rows
    $script:RowsTitle = "$($meta.Tool.title) · $($meta.Target)"
    $ui.dgResults.ItemsSource = $null
    $ui.dgResults.ItemsSource = $rows
    $has = ($rows.Count -gt 0)
    $ui.btnHtml.IsEnabled = $has; $ui.btnCsv.IsEnabled = $has; $ui.btnCopy.IsEnabled = $has
    $ui.btnRun.IsEnabled = $true; $ui.btnStop.IsEnabled = $false
    $ui.pbBusy.Visibility = 'Collapsed'

    $dur = [int]((Get-Date) - $meta.Start).TotalSeconds
    if ($errText.Trim()) {
        $hint = ''
        if ($errText -match 'WinRM|WS-Management|cannot connect|לא ניתן להתחבר|Access is denied|הגישה נדחתה') {
            $hint = ' · טיפ: הרץ "בדוק חיבור" על היעד כדי לראות מה חוסם.'
        }
        Add-UiLog "שגיאה: $($errText.Trim())$hint"
    }
    $status = 'OK'; if ($state -eq 'Failed' -or ($errText.Trim() -and -not $has)) { $status = 'FAILED' } elseif ($state -eq 'Stopped') { $status = 'STOPPED' }
    Add-UiLog ("סיום: {0} · {1} שורות · {2} שניות · {3}" -f $meta.Tool.title, $rows.Count, $dur, $status)
    $ui.txtStatus.Text = "הסתיים: $($meta.Tool.title) ($($rows.Count) שורות)"
    try { Write-TkLog -Root $Root -ToolId $meta.Tool.id -Target $meta.Target -Params $meta.Params -Status $status -Rows $rows.Count -ErrorText $errText } catch {}
    # שמירה אוטומטית לדוחות
    if ($has -and $meta.Tool.id -eq 'rep-daily') {
        $path = Join-Path $Root ('reports\daily-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.html')
        Export-TkHtml -Rows $rows -Title "צ'קליסט בוקר $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -Path $path | Out-Null
        Add-UiLog "הדוח נשמר: $path"
    }
    if ($has -and $meta.Tool.id -eq 'rep-inventory') {
        $dir = Join-Path $Root 'reports'; if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
        $path = Join-Path $dir ('inventory-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.csv')
        $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
        Add-UiLog "המלאי נשמר: $path"
    }
})

# שמות עמודות עם סוגריים, נקודה או לוכסן שוברים את ה-Binding האוטומטי של WPF, ולכן מבריחים אותם עם ^
$ui.dgResults.Add_AutoGeneratingColumn({
    param($s, $e)
    $name = "$($e.PropertyName)"
    $esc = $name -replace '([\.\/\(\)\[\]\^,])', '^$1'
    if ($e.Column -is [System.Windows.Controls.DataGridBoundColumn]) {
        $e.Column.Binding = New-Object System.Windows.Data.Binding $esc
        $e.Column.SortMemberPath = $esc
    }
    $e.Column.Header = $name
    if ($name -match 'הודעה|פרטים|קבוצות|פקודה|הערה') { $e.Column.MaxWidth = 520 }
})

# צביעת שורות לפי עמודת "מצב"
$ui.dgResults.Add_LoadingRow({
    param($s, $e)
    $st = ''
    try { $st = "$($e.Row.Item.'מצב')" } catch {}
    switch (Get-TkStatusClass $st) {
        'crit'  { $e.Row.Background = (& $brush '#FDE8E8') }
        'warn'  { $e.Row.Background = (& $brush '#FFF4E0') }
        default { $e.Row.Background = (& $brush '#FFFFFF') }
    }
})

$ui.btnRun.Add_Click({ if ($script:Tool) { try { Invoke-SelectedTool $script:Tool } catch { Add-UiLog "שגיאה: $($_.Exception.Message)" } } })
$ui.btnStop.Add_Click({ if ($script:Job) { Stop-Job $script:Job; Add-UiLog 'נשלחה בקשת עצירה.' } })
$ui.btnTest.Add_Click({
    $t = $Catalog.tools | Where-Object { $_.id -eq 'net-winrm' } | Select-Object -First 1
    Select-Tool $t; try { Invoke-SelectedTool $t } catch { Add-UiLog "שגיאה: $($_.Exception.Message)" }
})
$ui.btnRdp.Add_Click({ $t = "$($ui.cmbTarget.Text)".Trim(); if ($t -and -not (Test-TkLocal $t)) { Start-Process mstsc.exe "/v:$t" } })
$ui.btnMgmt.Add_Click({ $t = "$($ui.cmbTarget.Text)".Trim(); if (-not $t -or (Test-TkLocal $t)) { Start-Process compmgmt.msc } else { Start-Process compmgmt.msc "/computer=$t" } })
$ui.btnCred.Add_Click({
    $c = Get-Credential -Message 'משתמש להרצה מרחוק (למשל DOMAIN\admin). ביטול = חזרה למשתמש הנוכחי.'
    $script:Cred = $c
    if ($c) { $ui.txtCred.Text = "מריץ כ: $($c.UserName)" } else { $ui.txtCred.Text = 'משתמש נוכחי' }
})

function Confirm-SensitiveExport {
    if ($script:JobMeta -and $script:JobMeta.Tool.risk -eq 'sensitive') {
        return ((Show-Msg 'התוצאה כוללת מידע רגיש (סיסמאות או מפתחות). לשמור אותה בקובץ על הדיסק?' 'Warning' 'YesNo') -eq 'Yes')
    }
    return $true
}
$ui.btnHtml.Add_Click({
    if (-not (Confirm-SensitiveExport)) { return }
    $path = Join-Path $Root ('reports\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $script:JobMeta.Tool.id + '.html')
    Export-TkHtml -Rows $script:Rows -Title $script:RowsTitle -Path $path | Out-Null
    Add-UiLog "נשמר: $path"; Start-Process $path
})
$ui.btnCsv.Add_Click({
    if (-not (Confirm-SensitiveExport)) { return }
    $dir = Join-Path $Root 'reports'; if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
    $path = Join-Path $dir ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $script:JobMeta.Tool.id + '.csv')
    $script:Rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Add-UiLog "נשמר: $path"; Start-Process $path
})
$ui.btnCopy.Add_Click({
    $txt = ($script:Rows | ConvertTo-Csv -NoTypeInformation -Delimiter "`t") -join "`r`n"
    [System.Windows.Clipboard]::SetText($txt)
    Add-UiLog 'הועתק ללוח. אפשר להדביק באקסל או במייל.'
})
$ui.btnLogs.Add_Click({
    foreach ($d in 'logs', 'reports') { $x = Join-Path $Root $d; if (-not (Test-Path $x)) { New-Item -ItemType Directory $x | Out-Null } }
    Start-Process explorer.exe (Join-Path $Root 'reports')
})
$win.Add_Closing({ if ($script:Job) { Stop-Job $script:Job -ErrorAction SilentlyContinue; Remove-Job $script:Job -Force -ErrorAction SilentlyContinue } })

Update-ToolTree ''
Add-UiLog "נטענו $(@($Catalog.tools).Count) כלים. הגדרות: config.json"
if ("$($Config.DomainController)" -eq 'DC-EXAMPLE') {
    Add-UiLog 'שים לב: config.json עדיין עם ערכי דוגמה. ערוך אותו עם שמות השרתים וה-DC האמיתיים ופתח מחדש.'
}
[void]$win.ShowDialog()
