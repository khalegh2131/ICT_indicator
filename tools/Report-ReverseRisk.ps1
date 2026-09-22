<#
  Report-ReverseRisk.ps1
  ------------------------------------------------------------------
  READ-ONLY: turns the indicator's per-bar evidence CSV into MEASURED
  outcome rates (with sample counts) instead of invented numbers.

  WHY THE DEFINITION CHANGED (phase 46)
  ------------------------------------
  The first version asked one question: "did price move -AdverseATR ATR
  against the bias inside -Horizon bars?". On XAUUSD M15 that answer is
  YES about 65% of the time for EVERY feature bucket (measured: label LOW
  62.4%, MEDIUM 66.8%, HIGH 67.1%, EXTREME 64.3%) - i.e. the number did
  not rank anything, because a 1-ATR retrace inside 12 bars is nearly
  unconditional. A metric that cannot separate cannot grade.

  This version measures a RACE, which is what a trader actually faces:
     from the bar's close, did price travel +TargetATR in the BIAS
     direction BEFORE travelling -StopATR against it, inside Horizon bars?
  WIN / LOSS / OPEN per row. WIN% is the measured edge for that bucket.
  Tie-break inside a single bar: STOP wins (conservative, documented) -
  a bar that touches both proves nothing about order.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/Report-ReverseRisk.ps1
    powershell ... -File tools/Report-ReverseRisk.ps1 -Symbol XAUUSD -Horizon 12 -TargetATR 2 -StopATR 1

  NOTE: ASCII-only by design (PowerShell 5.1 misreads non-BOM UTF-8 sources).
#>
param(
   [string]$FilesDir = (Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'),
   [string]$Symbol = 'XAUUSD',
   [int]$Horizon = 12,
   [double]$TargetATR = 2.0,
   [double]$StopATR = 1.0,
   [int]$MinSamples = 10
)

$ErrorActionPreference = 'Stop'

# The indicator names the file after _Symbol, and most brokers append a suffix
# (XAUUSD.x). Resolving the exact name here removes the "MISSING" dead end.
$path = Join-Path $FilesDir ("ICT_Assistant_Canonical_ReverseRisk_" + $Symbol + ".csv")
if (-not (Test-Path -LiteralPath $path)) {
   $cand = @(Get-ChildItem -LiteralPath $FilesDir -Filter ("ICT_Assistant_Canonical_ReverseRisk_" + $Symbol + "*.csv") -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notmatch '\.csv\.' })
   if ($cand.Count -gt 0) {
      $path = ($cand | Sort-Object LastWriteTime -Descending)[0].FullName
      Write-Host ("resolved CSV: " + (Split-Path -Leaf $path))
   }
}
if (-not (Test-Path -LiteralPath $path)) {
   Write-Host ("MISSING: " + $path)
   Write-Host "The indicator creates this file when it runs on a chart (one reload is enough)."
   exit 2
}

$lines = Get-Content -LiteralPath $path -Encoding Unicode
if ($lines.Count -lt 2) { Write-Host "CSV has no data rows yet."; exit 2 }

# The indicator writes a header only when it creates an EMPTY file. A file that
# was started by an older build and appended to ever since carries no header at
# all, so skipping the first line unconditionally would throw away one real bar.
# Decide from the content instead of assuming.
$firstField = (($lines[0] -split ';')[0]).Trim()
$hasHeader = ($firstField -notmatch '^\d{4}\.\d{2}\.\d{2}')
$dataLines = if ($hasHeader) { @($lines | Select-Object -Skip 1) } else { @($lines) }
if ($hasHeader) { Write-Host ("header row detected: " + $firstField) }
else            { Write-Host "no header row in this file (legacy archive) - every line is treated as data" }

$rows = New-Object System.Collections.ArrayList
foreach ($ln in $dataLines) {
   $p = $ln -split ';'
   if ($p.Count -lt 19) { continue }
   # The Bias column is written by DirToStr(), which yields BULLISH / BEARISH /
   # NEUTRAL. Matching the bare BULL / BEAR form here would filter out every
   # single row and the report would claim "0 samples" for a file with 10k bars.
   $bias = (($p[1] + '').Trim().ToUpper() -replace 'ISH$', '')
   $price = 0.0; $high = 0.0; $low = 0.0; $atr = 0.0
   [void][double]::TryParse($p[2], [ref]$price)
   [void][double]::TryParse($p[3], [ref]$high)
   [void][double]::TryParse($p[4], [ref]$low)
   [void][double]::TryParse($p[5], [ref]$atr)
   [void]$rows.Add([pscustomobject]@{
      BarTime = $p[0]; Bias = $bias; Price = $price; High = $high; Low = $low; ATR = $atr
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
function Get-DolBucket([double]$v) { if ($v -le 0.0) { return 'DOL none' } elseif ($v -le 0.5) { return 'DOL <=0.5 ATR' } elseif ($v -le 1.0) { return 'DOL 0.5-1 ATR' } else { return 'DOL >1 ATR' } }
function Get-LevelFamily([string]$s) {
   $t = ($s + '').ToUpper()
   if ($t.StartsWith('LIQ'))             { return 'family LIQ' }
   if ($t.StartsWith('OB '))             { return 'family OB' }
   if ($t.StartsWith('BREAKER'))         { return 'family BREAKER' }
   if ($t.StartsWith('MITIGATION'))      { return 'family MITIGATION' }
   if ($t.StartsWith('FVG'))             { return 'family FVG' }
   if ($t.StartsWith('VOLUME IMBALANCE')){ return 'family FVG-VI' }
   if ($t.StartsWith('S/D'))             { return 'family S/D' }
   if ($t.StartsWith('TRENDLINE'))       { return 'family TRENDLINE' }
   return 'family OTHER'
}

# --- forward measurement: target-vs-stop race --------------------------------
$measured = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt ($rows.Count - $Horizon); $i++) {
   $r = $rows[$i]
   if ($r.ATR -le 0.0) { continue }
   if ($r.Bias -ne 'BULL' -and $r.Bias -ne 'BEAR') { continue }
   $target = $r.Price + $(if ($r.Bias -eq 'BULL') { $TargetATR * $r.ATR } else { -$TargetATR * $r.ATR })
   $stop   = $r.Price + $(if ($r.Bias -eq 'BULL') { -$StopATR * $r.ATR } else { $StopATR * $r.ATR })
   $outcome = 'OPEN'
   for ($j = $i + 1; $j -le ($i + $Horizon); $j++) {
      $b = $rows[$j]
      $hitStop = $(if ($r.Bias -eq 'BULL') { $b.Low  -le $stop   } else { $b.High -ge $stop   })
      $hitTgt  = $(if ($r.Bias -eq 'BULL') { $b.High -ge $target } else { $b.Low  -le $target })
      if ($hitStop) { $outcome = 'LOSS'; break }   # same-bar tie -> STOP wins
      if ($hitTgt)  { $outcome = 'WIN';  break }
   }
   [void]$measured.Add([pscustomobject]@{
      Outcome = $outcome
      Win = ($outcome -eq 'WIN')
      R = $(if ($outcome -eq 'WIN') { $TargetATR } elseif ($outcome -eq 'LOSS') { -$StopATR } else { 0.0 })
      Label = $r.Label
      Level = $r.Level
      Family = (Get-LevelFamily $r.Level)
      LevelDist = [double]$r.LevelDist
      Leg = [double]$r.Leg
      DolDist = [double]$r.DolDist
      SweptAgainst = $r.SweptAgainst
      MtfAligned = $r.MtfAligned
      Exh = $r.Exh
      Bucket_Level = (Get-Bucket ([double]$r.LevelDist) @(0.25, 0.5, 1.0) @('dist <0.25 ATR', 'dist 0.25-0.5 ATR', 'dist 0.5-1 ATR', 'dist >1 ATR'))
      Bucket_Leg   = (Get-LegBucket ([double]$r.Leg))
      Bucket_Dol   = (Get-DolBucket ([double]$r.DolDist))
   })
}

function Show-Group([string]$title, [string]$key, $data) {
   Write-Host ''
   Write-Host ("--- " + $title + " ---")
   Write-Host ("{0,-30} {1,7} {2,8} {3,8} {4,8}" -f 'bucket', 'n', 'win%', 'loss%', 'open%')
   $groups = $data | Group-Object -Property $key | Sort-Object Count -Descending
   foreach ($g in $groups) {
      $n = $g.Count
      if ($n -lt $MinSamples) {
         Write-Host ("{0,-30} {1,7} {2,8}" -f $g.Name, $n, 'insufficient-n')
      } else {
         $w = @($g.Group | Where-Object { $_.Outcome -eq 'WIN'  }).Count
         $l = @($g.Group | Where-Object { $_.Outcome -eq 'LOSS' }).Count
         $o = $n - $w - $l
         Write-Host ("{0,-30} {1,7} {2,8} {3,8} {4,8}" -f $g.Name, $n,
                     ([math]::Round(100.0 * $w / $n, 1).ToString('0.0') + '%'),
                     ([math]::Round(100.0 * $l / $n, 1).ToString('0.0') + '%'),
                     ([math]::Round(100.0 * $o / $n, 1).ToString('0.0') + '%'))
      }
   }
}

Write-Host ("Reverse-risk RACE measurement | symbol=" + (Split-Path -Leaf $path) + " | horizon=" + $Horizon + " bars | target=+" + $TargetATR + " ATR in bias dir | stop=-" + $StopATR + " ATR")
$totW = @($measured | Where-Object { $_.Outcome -eq 'WIN' }).Count
$totL = @($measured | Where-Object { $_.Outcome -eq 'LOSS' }).Count
$totO = @($measured | Where-Object { $_.Outcome -eq 'OPEN' }).Count
Write-Host ("samples raced: " + $measured.Count + " of " + $rows.Count + " rows | file written: " + (Get-Item $path).LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
Write-Host ("BASELINE (all samples): win=" + [math]::Round(100.0*$totW/$measured.Count,1) + "%  loss=" + [math]::Round(100.0*$totL/$measured.Count,1) + "%  open=" + [math]::Round(100.0*$totO/$measured.Count,1) + "%")
Write-Host 'A grade is only useful if its win% sits clearly ABOVE this baseline; anything near it ranks nothing.'

Show-Group 'by warning label (the current on-chart index)' 'Label' $measured
Show-Group 'by distance to the nearest level' 'Bucket_Level' $measured
Show-Group 'by nearest level family' 'Family' $measured
Show-Group 'by leg progress' 'Bucket_Leg' $measured
Show-Group 'by distance to the draw on liquidity' 'Bucket_Dol' $measured
Show-Group 'by sweep-against-bias flag' 'SweptAgainst' $measured
Show-Group 'by MTF alignment' 'MtfAligned' $measured
Show-Group 'by exhaustion state' 'Exh' $measured

# --- candidate axis combinations (phase 46 grade design) ---------------------
Write-Host ''
Write-Host '--- candidate grade axes (confluence count, measured) ---'
$axis = New-Object System.Collections.ArrayList
foreach ($m in $measured) {
   $s = 0
   if ($m.MtfAligned -eq 'true')          { $s++ }   # structure axis proxy
   if ($m.Bucket_Dol -eq 'DOL >1 ATR')    { $s++ }   # a draw still ahead
   if ($m.Leg -ge 85)                     { $s++ }   # price at the end of the leg
   if ($m.SweptAgainst -eq 'false')       { $s++ }   # no sweep against the bias
   [void]$axis.Add([pscustomobject]@{ Outcome = $m.Outcome; Axes = $s })
}
Show-Group 'by number of satisfied axes (0..4)' 'Axes' $axis

# --- snapshot of the latest row ---------------------------------------------
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

# The latest read is only useful next to what that same situation actually did in
# the recorded past, so the snapshot always ends with a measured number or an
# explicit refusal. A label that cannot reach the sample floor gets no rate.
$lb = @($measured | Where-Object { $_.Label -eq $last.Label })
if ($lb.Count -ge $MinSamples) {
   $lw = @($lb | Where-Object { $_.Outcome -eq 'WIN' }).Count
   Write-Host ("measured    : for label " + $last.Label + " the win rate was " + [math]::Round(100.0*$lw/$lb.Count,1) + "% over " + $lb.Count + " past samples (baseline " + [math]::Round(100.0*$totW/$measured.Count,1) + "%)")
} else {
   Write-Host ("measured    : not enough samples for label " + $last.Label + " (n=" + $lb.Count + ") - do not trust a rate here")
}
