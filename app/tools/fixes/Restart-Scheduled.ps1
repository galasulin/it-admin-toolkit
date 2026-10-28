param([hashtable]$P = @{})
$min = 0; [int]::TryParse("$($P.Minutes)", [ref]$min) | Out-Null
if ("$($P.Minutes)".Trim() -eq 'בטל') {
    shutdown.exe /a 2>&1 | Out-Null
    [pscustomobject]@{ 'פעולה' = 'ביטול אתחול מתוזמן'; 'מצב' = $(if ($LASTEXITCODE -eq 0) { 'בוצע' } else { 'לא היה אתחול מתוזמן' }); 'פרטים' = '' }
    return
}
if ($min -lt 1) { $min = 1 }
$sec = $min * 60
$msg = "המחשב יופעל מחדש בעוד $min דקות לצורך תחזוקה. נא לשמור עבודה."
shutdown.exe /r /t $sec /c "$msg" /d p:4:1 2>&1 | Out-Null
$when = (Get-Date).AddMinutes($min).ToString('HH:mm')
[pscustomobject]@{ 'פעולה' = 'אתחול מתוזמן'; 'מצב' = $(if ($LASTEXITCODE -eq 0) { 'בוצע' } else { "נכשל ($LASTEXITCODE)" }); 'פרטים' = "בשעה $when · המשתמש קיבל הודעה · לביטול: להריץ שוב ולהקליד בטל" }
