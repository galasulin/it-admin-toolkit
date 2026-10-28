param([hashtable]$P = @{})
$days = 60; if ($P.Days) { $days = [int]$P.Days }
$certs = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue)
if ($certs.Count -eq 0) { [pscustomobject]@{ 'תעודה' = 'אין תעודות בחנות LocalMachine\My'; 'מנפיק' = ''; 'פג תוקף' = ''; 'ימים שנותרו' = ''; 'מצב' = 'תקין'; 'Thumbprint' = '' }; return }
foreach ($c in $certs | Sort-Object NotAfter) {
    $left = [int]($c.NotAfter - (Get-Date)).TotalDays
    $st = 'תקין'; if ($left -lt 0) { $st = 'קריטי' } elseif ($left -lt 14) { $st = 'קריטי' } elseif ($left -lt $days) { $st = 'אזהרה' }
    $name = $c.FriendlyName; if (-not $name) { $name = $c.Subject }
    [pscustomobject]@{ 'תעודה' = $name; 'מנפיק' = ($c.Issuer -replace '^CN=([^,]+).*', '$1'); 'פג תוקף' = $c.NotAfter.ToString('dd/MM/yyyy'); 'ימים שנותרו' = $left; 'מצב' = $st; 'Thumbprint' = $c.Thumbprint }
}
