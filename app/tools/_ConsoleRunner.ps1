param([string]$Script, [string]$InFile, [string]$OutFile)
# מריץ כלי בחלון גלוי (לכלים שצריכים התחברות אינטראקטיבית) ומחזיר את התוצאה כ-JSON
$Host.UI.RawUI.WindowTitle = 'ארגז כלים IT · ' + [IO.Path]::GetFileNameWithoutExtension($Script)
$p = @{}
if (Test-Path $InFile) {
    $j = Get-Content $InFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($pr in $j.PSObject.Properties) { $p[$pr.Name] = $pr.Value }
}
try {
    $res = @(& $Script $p)
    if ($res.Count -eq 0) { $res = @([pscustomobject]@{ 'מצב' = 'תקין'; 'פרטים' = 'אין תוצאות' }) }
    ConvertTo-Json -InputObject $res -Depth 4 | Set-Content -Path $OutFile -Encoding UTF8
} catch {
    $err = @([pscustomobject]@{ 'מצב' = 'שגיאה'; 'פרטים' = $_.Exception.Message })
    ConvertTo-Json -InputObject $err -Depth 3 | Set-Content -Path $OutFile -Encoding UTF8
    Write-Host ''
    Write-Host ('שגיאה: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'השגיאה נשלחה לחלון הכלי. החלון ייסגר בעוד 8 שניות.'
    Start-Sleep -Seconds 8
}
