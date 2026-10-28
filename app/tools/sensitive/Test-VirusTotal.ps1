param([hashtable]$P = @{})
# בודק קבצים מול VirusTotal. ברירת המחדל שולחת רק את ה-Hash (SHA256), כך שהקובץ עצמו לא יוצא מהמחשב.
# העלאת קובץ שלא מוכר ל-VirusTotal קורית רק אם בחרת "כן". אז הקובץ נשמר אצלם ונגיש למנויים שלהם.
$key = "$($P._VtKey)"
if (-not $key) { throw 'חסר VirusTotalApiKey בקובץ config.json (מפתח חינמי: virustotal.com > API key)' }
$path = "$($P.Path)".Trim('"', ' ')
if (-not (Test-Path $path)) { throw "הנתיב לא קיים: $path" }
$upload = ("$($P.Upload)".Trim() -eq 'כן')
$files = @(Get-Item $path | Where-Object { -not $_.PSIsContainer })
if ($files.Count -eq 0) { $files = @(Get-ChildItem $path -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 50) }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$h = @{ 'x-apikey' = $key }
$n = 0
foreach ($f in $files) {
    if ($n -gt 0 -and ($n % 4) -eq 0) { Start-Sleep -Seconds 61 }   # מגבלת המפתח החינמי: 4 בקשות בדקה
    $n++
    $sha = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
    $row = [ordered]@{ 'קובץ' = $f.FullName; 'SHA256' = $sha; 'זיהויים' = ''; 'מצב' = ''; 'פרטים' = '' }
    try {
        $r = Invoke-RestMethod -Uri "https://www.virustotal.com/api/v3/files/$sha" -Headers $h -ErrorAction Stop
        $s = $r.data.attributes.last_analysis_stats
        $bad = [int]$s.malicious; $sus = [int]$s.suspicious; $tot = $bad + $sus + [int]$s.undetected + [int]$s.harmless
        $row['זיהויים'] = "$bad/$tot"
        $row['מצב'] = $(if ($bad -ge 3) { 'קריטי' } elseif ($bad -gt 0 -or $sus -gt 0) { 'אזהרה' } else { 'תקין' })
        $row['פרטים'] = "https://www.virustotal.com/gui/file/$sha"
    } catch {
        $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        if ($code -eq 404 -and $upload) {
            if ($f.Length -gt 32MB) { $row['מצב'] = 'לבדוק'; $row['פרטים'] = 'לא מוכר ל-VirusTotal, וגדול מ-32MB להעלאה' }
            else {
                Add-Type -AssemblyName System.Net.Http
                $cl = New-Object System.Net.Http.HttpClient
                $cl.DefaultRequestHeaders.Add('x-apikey', $key)
                $mp = New-Object System.Net.Http.MultipartFormDataContent
                $fs = [System.IO.File]::OpenRead($f.FullName)
                $mp.Add((New-Object System.Net.Http.StreamContent $fs), 'file', $f.Name)
                $resp = $cl.PostAsync('https://www.virustotal.com/api/v3/files', $mp).Result
                $fs.Close()
                $row['מצב'] = 'לבדוק'
                $row['פרטים'] = $(if ($resp.IsSuccessStatusCode) { "הועלה לסריקה. להריץ שוב בעוד 2-3 דקות, או לבדוק כאן: https://www.virustotal.com/gui/file/$sha" } else { "ההעלאה נכשלה: $([int]$resp.StatusCode)" })
            }
        } elseif ($code -eq 404) { $row['מצב'] = 'לבדוק'; $row['פרטים'] = 'הקובץ לא מוכר ל-VirusTotal. אפשר להריץ שוב עם העלאה = כן' }
        elseif ($code -eq 401) { $row['מצב'] = 'שגיאה'; $row['פרטים'] = 'מפתח ה-API לא תקין' }
        elseif ($code -eq 429) { $row['מצב'] = 'שגיאה'; $row['פרטים'] = 'עברת את מכסת הבקשות של המפתח החינמי' }
        else { $row['מצב'] = 'שגיאה'; $row['פרטים'] = $_.Exception.Message }
    }
    [pscustomobject]$row
}
