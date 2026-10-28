param([hashtable]$P = @{})
$id = "$($P.SessionId)".Trim()
if ($id -notmatch '^\d+$') { [pscustomobject]@{ 'פעולה' = 'ניתוק סשן'; 'מצב' = 'נכשל'; 'פרטים' = 'צריך מספר סשן (ID). להריץ קודם "מי מחובר עכשיו".' }; return }
logoff.exe $id 2>&1 | Out-Null
[pscustomobject]@{ 'פעולה' = "Log off לסשן $id"; 'מצב' = $(if ($LASTEXITCODE -eq 0) { 'בוצע' } else { "נכשל ($LASTEXITCODE)" }); 'פרטים' = 'קבצים פתוחים שלא נשמרו אצל המשתמש אבדו.' }
