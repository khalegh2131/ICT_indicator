<#
  Report-ReverseRisk.ps1
  ------------------------------------------------------------------
  READ-ONLY: turns the indicator's reverse-risk evidence CSV into MEASURED
  probabilities (with sample counts) instead of invented numbers.

  How the measurement works (no guessing anywhere):
    * The indicator writes one row per closed bar with the features it could see
      at that moment (nearest level, level state, distance in ATR, leg progress,
      distance to the draw on liquidity, exhaustion, sweep-against-bias, score).
    * This script then looks FORWARD from each row using the High/Low columns of
      the following bars and asks one question:
         "did price move at least -AdverseATR ATR AGAINST the bias within -Horizon bars?"
      (i.e. the move that would stop out a trader who entered with the bias).
    * The share of YES answers, grouped by feature bucket, IS the measured
      probability. Buckets with fewer than -MinSamples rows are marked
      "insufficient" and are never presented as a rate.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/Report-ReverseRisk.ps1
    powershell ... -File tools/Report-ReverseRisk.ps1 -Symbol XAUUSD -Horizon 12 -AdverseATR 1.0

  NOTE: ASCII-only by design (PowerShell 5.1 misreads non-BOM UTF-8 sources).
#>
param(
   [string]$FilesDir = (Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'),
   [string]$Symbol = 'XAUUSD',
   [int]$Horizon = 12,
   [double]$AdverseATR = 1.0,
   [int]$MinSamples = 10
)

$ErrorActionPreference = 'Stop'
$path = Join-Path $FilesDir ("ICT_Assistant_Canonical_ReverseRisk_" + $Symbol + ".csv")
if (-not (Test-Path -LiteralPath $path)) {
   Write-Host ("MISSING: " + $path)
   Write-Host "The indicator creates this file when it runs on a chart (one reload is enough)."
   exit 2
}

$lines = Get-Content -LiteralPath $path -Encoding Unicode
if ($lines.Count -lt 2) { Write-Host "CSV has no data rows yet."; exit 2 }

$rows = New-Object System.Collections.ArrayList
foreach ($ln in ($lines | Select-Object -Skip 1)) {
   $p = $ln -split ';'
   if ($p.Count -lt 19) { continue }
   $price = 0.0; $high = 0.0; $low = 0.0; $atr = 0.0
   [void][double]::TryParse($p[2], [ref]$price)
   [void][double]::TryParse($p[3], [ref]$high)
   [void][double]::TryParse($p[4], [ref]$low)
   [void][double]::TryParse($p[5], [ref]$atr)
   [void]$rows.Add([pscustomobject]@{
      BarTime = $p[0]; Bias = $p[1]; Price = $price; High = $high; Low = $low; ATR = $atr
      Level = $p[6]; LevelDist = $p[7]; LevelState = $p[8]; Leg = $p[9]
      DolType = $p[10]; DolDist = $p[11]; Exh = $p[12]; SweptAgainst = $p[13]
      EvBars = $p[14]; MtfAligned = $p[15]; Score = [int]$p[16]; Label = $p[17]
   })
}
if ($rows.Count -le $Horizon) { Write-Host ("Only " + $rows.Count + " rows - not enough for a forward horizon of " + $Horizon + "."); exit 2 }

function Get-Bucket([double]$v, [double[]]$edges, [string[]]$names) {
   for ($i = 0; $i -lt $edges.Count; $i++) { if ($v -lt $edges[$i]) { return $names[$i] } }
   return $names[$names.Count - 1]
}
function Get-LegBucket([double]$v) { if ($v -lt 50) { return 'leg <50%' } elseif ($v -lt 85) { return 'leg 50-85%' } else { return 'leg >=85%' } }
function Get-DolBucket([double]$v) { if ($v -le 0.5) { return 'DOL <=0.5 ATR' } elseif ($v -le 1.0) { return 'DOL 0.5-1 ATR' } else { return 'DOL >1 ATR' } }

# --- forward measurement -----------------------------------------------------
$measured = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt ($rows.Count - $Horizon); $i++) {
   $r = $rows[$i]
   if ($r.ATR -le 0.0) { continue }
   if ($r.Bias -ne 'BULL' -and $r.Bias -ne 'BEAR') { continue }
   $window = $rows[($i + 1)..($i + $Horizon)]
   if ($r.Bias -eq 'BULL') {
      $worst = ($window | Measure-Object -Property Low -Minimum).Minimum
      $adverse = ($r.Price - $worst) / $r.ATR
   } else {
      $best = ($window | Measure-Object -Property High -Maximum).Maximum
      $adverse = ($best - $r.Price) / $r.ATR
   }
   [void]$measured.Add([pscustomobject]@{
      Adverse = $adverse
      Reversed = ($adverse -ge $AdverseATR)
      Label = $r.Label
      Level = $r.Level
      LevelDist = $r.LevelDist
      Leg = [double]$r.Leg
      DolDist = [double]$r.DolDist
      SweptAgainst = $r.SweptAgainst
      Exh = $r.Exh
      Bucket_Level = (Get-Bucket ([double]$r.LevelDist) @(0.25, 0.5, 1.0) @('dist <0.25 ATR', 'dist 0.25-0.5 ATR', 'dist 0.5-1 ATR', 'dist >1 ATR'))
      Bucket_Leg = (Get-LegBucket ([double]$r.Leg))
      Bucket_Dol = (Get-DolBucket ([double]$r.DolDist))
   })
}

function Show-Group([string]$title, [string]$key, $data) {
   Write-Host ''
   Write-Host ("--- " + $title + " ---")
   Write-Host ("{0,-26} {1,7} {2,10}" -f 'bucket', 'samples', 'adverse%')
   $groups = $data | Group-Object -Property $key | Sort-Object Count -Descending
   foreach ($g in $groups) {
      $n = $g.Count
      $yes = @($g.Group | Where-Object { $_.Reversed }).Count
      if ($n -lt $MinSamples) {
         Write-Host ("{0,-26} {1,7} {2,10}" -f $g.Name, $n, 'insufficient-n')
      } else {
         $pct = [math]::Round(100.0 * $yes / $n, 1)
         Write-Host ("{0,-26} {1,7} {2,10}" -f $g.Name, $n, ($pct.ToString('0.0') + '%'))
      }
   }
}

Write-Host ("Reverse-risk measurement | symbol=" + $Symbol + " | horizon=" + $Horizon + " bars | adverse>=" + $AdverseATR + " ATR against bias")
Write-Host ("samples measured: " + $measured.Count + " of " + $rows.Count + " rows | file: " + (Get-Item $path).LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
Write-Host 'Definition: a "reversal" here means price moved AdverseATR ATR AGAINST the bias inside the horizon.'

Show-Group 'by warning label (in-code index)' 'Label' $measured
Show-Group 'by distance to the nearest level' 'Bucket_Level' $measured
Show-Group 'by leg progress' 'Bucket_Leg' $measured
Show-Group 'by distance to the draw on liquidity' 'Bucket_Dol' $measured
Show-Group 'by sweep-against-bias flag' 'SweptAgainst' $measured
Show-Group 'by exhaustion state' 'Exh' $measured
Show-Group 'by nearest level type (top buckets)' 'Level' $measured

# --- snapshot of the latest row + its measured bucket rate -------------------
$last = $rows[$rows.Count - 1]
Write-Host ''
Write-Host '--- latest snapshot in the CSV ---'
Write-Host ("bar         : " + $last.BarTime)
Write-Host ("bias        : " + $last.Bias)
Write-Host ("nearest     : " + $last.Level + "  [" + $last.LevelState + "]  dist=" + $last.LevelDist + " ATR")
Write-Host ("leg progress: " + $last.Leg + " %")
Write-Host ("draw (DOL)  : " + $last.DolType + "  dist=" + $last.DolDist + " ATR")
Write-Host ("exhaustion  : " + $last.Exh + " | sweptAgainst=" + $last.SweptAgainst + " | mtfAligned=" + $last.MtfAligned)
Write-Host ("warning     : " + $last.Label + " (index " + $last.Score + "/100 - a sum of documented weights, not a probability)")

$lb = $measured | Where-Object { $_.Label -eq $last.Label }
if ($lb.Count -ge $MinSamples) {
   $r = [math]::Round(100.0 * @($lb | Where-Object { $_.Reversed }).Count / $lb.Count, 1)
   Write-Host ("measured    : for label " + $last.Label + " the adverse rate was " + $r + "% over " + $lb.Count + " past samples")
} else {
   Write-Host ("measured    : not enough samples for label " + $last.Label + " (n=" + $lb.Count + ") - do not trust a rate here")
}
