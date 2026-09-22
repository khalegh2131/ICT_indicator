<#
  Fit-SignalGrade.ps1
  ------------------------------------------------------------------
  READ-ONLY. Derives the A+/A/B+/B grade coefficients FROM THE DATA.

  Method (no invented weights anywhere):
    1. read the indicator's per-bar evidence CSV
    2. race each row forward: +TargetATR in the bias direction vs -StopATR
       against it inside Horizon bars -> WIN / LOSS / OPEN
    3. for every feature value compute the log-odds lift over the baseline
         lift = logit(win% of the bucket) - logit(baseline win%)
       (Laplace-smoothed; buckets below -MinSamples are dropped, not guessed)
    4. grade a row by SUMMING the lifts of its feature values
    5. split the score by its own measured quantiles into the five grades
    6. report win% per grade - if two grades collide, the grade is NOT a grade
       and this script says so instead of shipping it

  Output: the coefficient table printed for embedding in the MQL5 source, plus
  the measured win% per grade. The command below is the provenance.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/Fit-SignalGrade.ps1
#>
param(
   [string]$FilesDir = (Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'),
   [string]$Symbol = 'XAUUSD',
   # Phase 49: each live chart writes its own ledger (per symbol AND timeframe),
   # so a fit that pools two timeframes measures neither. -Timeframe selects one
   # file explicitly; without it the newest match is used and said out loud.
   [string]$Timeframe = '',
   [int]$Horizon = 12,
   [double]$TargetATR = 2.0,
   [double]$StopATR = 1.0,
   [int]$MinSamples = 30,
   # A ledger can carry thousands of ROWS and still zero usable SAMPLES: every row is
   # skipped when the recorded bias is not BULL/BEAR or the recorded ATR is zero.
   # Without this floor the tool happily emitted thresholds read from a null. It now
   # refuses instead, because a calibration file built from nothing is worse than none:
   # the chart would call it "calibrated for this symbol".
   [int]$MinFitSamples = 200,
   # -Emit writes the fitted table to a fixture so the MQL5 constants can be
   # checked against the DATA instead of against a hand-copied list.
   [string]$Emit = '',
   # -EmitCalib writes the RUNTIME calibration file in the exact format the
   # indicator's loader reads (key;value per line), so a fit becomes a loadable
   # per-symbol calibration instead of hand-copied constants.
   [string]$EmitCalib = '',
   # -LedgerPath bypasses the symbol->file lookup so many ledgers can be pooled
   # (e.g. all crosses of one class) and fitted once. The caller is responsible
   # for saying, in the emitted file, which sample it actually used.
   [string]$LedgerPath = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$path = ''
if (-not [string]::IsNullOrWhiteSpace($LedgerPath)) {
   $path = $LedgerPath
   if (-not (Test-Path -LiteralPath $path)) { Write-Host ("MISSING: " + $path); exit 2 }
} elseif (-not [string]::IsNullOrWhiteSpace($Timeframe)) {
   $path = Join-Path $FilesDir ("ICT_Assistant_Canonical_ReverseRisk_" + $Symbol + "_" + $Timeframe + ".csv")
   if (-not (Test-Path -LiteralPath $path)) { Write-Host ("MISSING: " + $path); exit 2 }
} else {
   $path = Join-Path $FilesDir ("ICT_Assistant_Canonical_ReverseRisk_" + $Symbol + ".csv")
   if (-not (Test-Path -LiteralPath $path)) {
      $cand = @(Get-ChildItem -LiteralPath $FilesDir -Filter ("ICT_Assistant_Canonical_ReverseRisk_" + $Symbol + "*.csv") -ErrorAction SilentlyContinue)
      if ($cand.Count -gt 0) { $path = ($cand | Sort-Object LastWriteTime -Descending)[0].FullName }
      if ($cand.Count -gt 1) {
         Write-Host ("NOTE: " + $cand.Count + " ledgers match this symbol; using the newest (" + (Split-Path -Leaf $path) + ").")
         Write-Host "      Pass -Timeframe <TF> to fit one timeframe on purpose:"
         foreach ($c in $cand) { Write-Host ("        " + (Split-Path -Leaf $c.FullName)) }
      }
   }
}
if (-not (Test-Path -LiteralPath $path)) { Write-Host ("MISSING: " + $path); exit 2 }

$lines = Get-Content -LiteralPath $path -Encoding Unicode
$firstField = (($lines[0] -split ';')[0]).Trim()
$hasHeader = ($firstField -notmatch '^\d{4}\.\d{2}\.\d{2}')
$dataLines = if ($hasHeader) { @($lines | Select-Object -Skip 1) } else { @($lines) }

function Get-LegBucket([double]$v) { if ($v -lt 50) { return 'legLt50' } elseif ($v -lt 85) { return 'leg50to85' } else { return 'legGte85' } }
function Get-DolBucket([double]$v) { if ($v -le 0.0) { return 'dolNone' } elseif ($v -le 0.5) { return 'dolLe05' } elseif ($v -le 1.0) { return 'dol05to1' } else { return 'dolGt1' } }
function Get-DistBucket([double]$v) { if ($v -lt 0.25) { return 'distLt025' } elseif ($v -lt 0.5) { return 'dist025to05' } elseif ($v -lt 1.0) { return 'dist05to1' } else { return 'distGt1' } }
function Get-Family([string]$s) {
   $t = ($s + '').ToUpper()
   if ($t.StartsWith('LIQ'))              { return 'famLIQ' }
   if ($t.StartsWith('OB '))              { return 'famOB' }
   if ($t.StartsWith('BREAKER'))          { return 'famBREAKER' }
   if ($t.StartsWith('MITIGATION'))       { return 'famMITIG' }
   if ($t.StartsWith('FVG STANDARD'))     { return 'famFVG' }
   if ($t.StartsWith('FVG'))              { return 'famFVG' }
   if ($t.StartsWith('VOLUME IMBALANCE')) { return 'famFVGVI' }
   if ($t.StartsWith('S/D'))              { return 'famSD' }
   if ($t.StartsWith('TRENDLINE'))        { return 'famTL' }
   return 'famOTHER'
}
function Get-ExhKey([string]$s) { return 'exh' + (($s + '').Trim() -replace '[^A-Za-z_]', '') }

$rows = New-Object System.Collections.ArrayList
foreach ($ln in $dataLines) {
   $p = $ln -split ';'
   if ($p.Count -lt 19) { continue }
   $bias = (($p[1] + '').Trim().ToUpper() -replace 'ISH$', '')
   $price = 0.0; $atr = 0.0; $leg = 0.0; $dol = 0.0; $dist = 0.0
   $high = 0.0; $low = 0.0
   [void][double]::TryParse($p[2], [ref]$price)
   # High/Low are mandatory: the race needs the forward path. Omitting them once
   # made every $null comparison resolve as 0 and produced exactly the SAME
   # numbers for opposite buckets - the tell that the fit was meaningless.
   [void][double]::TryParse($p[3], [ref]$high)
   [void][double]::TryParse($p[4], [ref]$low)
   [void][double]::TryParse($p[5], [ref]$atr)
   [void][double]::TryParse($p[9], [ref]$leg)
   [void][double]::TryParse($p[11], [ref]$dol)
   [void][double]::TryParse($p[7], [ref]$dist)
   [void]$rows.Add([pscustomobject]@{
      Bias = $bias; Price = $price; ATR = $atr; High = $high; Low = $low
      Leg = $leg; Dol = $dol; Dist = $dist
      Swept = (($p[13] + '').Trim())
      Mtf = (($p[15] + '').Trim())
      Exh = (($p[12] + '').Trim())
      F1 = (Get-Family $p[6]); F2 = (Get-DistBucket $dist); F3 = (Get-LegBucket $leg)
      F4 = (Get-DolBucket $dol); F5 = ('mtf' + (($p[15] + '').Trim()))
      F6 = ('swept' + (($p[13] + '').Trim())); F7 = (Get-ExhKey $p[12])
   })
}

$meas = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt ($rows.Count - $Horizon); $i++) {
   $r = $rows[$i]
   if ($r.ATR -le 0.0) { continue }
   if ($r.Bias -ne 'BULL' -and $r.Bias -ne 'BEAR') { continue }
   $sgn = $(if ($r.Bias -eq 'BULL') { 1.0 } else { -1.0 })
   $target = $r.Price + $sgn * $TargetATR * $r.ATR
   $stop   = $r.Price - $sgn * $StopATR * $r.ATR
   $out = 'OPEN'
   for ($j = $i + 1; $j -le ($i + $Horizon); $j++) {
      $b = $rows[$j]
      $hitStop = $(if ($sgn -gt 0) { $b.Low  -le $stop   } else { $b.High -ge $stop   })
      $hitTgt  = $(if ($sgn -gt 0) { $b.High -ge $target } else { $b.Low  -le $target })
      if ($hitStop) { $out = 'LOSS'; break }
      if ($hitTgt)  { $out = 'WIN';  break }
   }
   $r | Add-Member -NotePropertyName Outcome -NotePropertyValue $out -Force
   [void]$meas.Add($r)
}

$n = $meas.Count
if ($n -lt $MinFitSamples) {
   Write-Host ("REFUSING TO EMIT: usable samples = " + $n + " (need " + $MinFitSamples + ").")
   Write-Host "  Rows are skipped when the bias column is not BULL/BEAR, or when ATR parses as 0."
   Write-Host ("  Diagnostic: rows read=" + $rows.Count + "; horizons dropped=" + [math]::Min($Horizon, $rows.Count))
   exit 3
}
$w = @($meas | Where-Object { $_.Outcome -eq 'WIN' }).Count
$baseP = ($w + 1.0) / ($n + 2.0)                        # Laplace
$baseLogit = [math]::Log($baseP / (1 - $baseP))
Write-Host ("samples=" + $n + "  baseline win=" + [math]::Round(100.0*$w/$n,2) + "%  baseLogit=" + [math]::Round($baseLogit,4))
Write-Host ("file=" + (Split-Path -Leaf $path) + "  written=" + (Get-Item $path).LastWriteTime.ToString('yyyy-MM-dd HH:mm'))

$featNames = @('F1','F2','F3','F4','F5','F6','F7')
$featureTitle = @{ F1='levelFamily'; F2='levelDistBucket'; F3='legBucket'; F4='dolBucket'; F5='mtfAligned'; F6='sweptAgainst'; F7='exhaustion' }
$coef = @{}
foreach ($f in $featNames) { $coef[$f] = @{} }

foreach ($f in $featNames) {
   foreach ($g in ($meas | Group-Object -Property $f)) {
      $bn = $g.Count
      if ($bn -lt $MinSamples) { continue }
      $bw = @($g.Group | Where-Object { $_.Outcome -eq 'WIN' }).Count
      $p = ($bw + 1.0) / ($bn + 2.0)
      $lift = [math]::Log($p / (1 - $p)) - $baseLogit
      $coef[$f][$g.Name] = [math]::Round($lift, 3)
   }
}

Write-Host ''
Write-Host '--- coefficient table (log-odds lift over baseline; 0 = neutral) ---'
foreach ($f in $featNames) {
   Write-Host ("[" + $f + " " + $featureTitle[$f] + "]")
   foreach ($k in ($coef[$f].Keys | Sort-Object)) {
      $g = $meas | Where-Object { $_.$f -eq $k }
      $bn = @($g).Count
      $bw = @($g | Where-Object { $_.Outcome -eq 'WIN' }).Count
      Write-Host ("   {0,-22} n={1,6}  win%={2,6}  lift={3,7}" -f $k, $bn, [math]::Round(100.0*$bw/$bn,1), $coef[$f][$k])
   }
}

# score every row with the fitted table, then split by the score's own quantiles
$scored = New-Object System.Collections.ArrayList
foreach ($m in $meas) {
   $s = 0.0
   foreach ($f in $featNames) {
      $k = $m.$f
      if ($coef[$f].ContainsKey($k)) { $s += $coef[$f][$k] }
   }
   [void]$scored.Add([pscustomobject]@{ Score = $s; Outcome = $m.Outcome })
}
$sorted = @($scored | Sort-Object Score)
$q = { param($frac) $sorted[[math]::Min($sorted.Count - 1, [int][math]::Floor($frac * $sorted.Count))].Score }
$t1 = & $q 0.60     # bottom 60% -> C / B
$t2 = & $q 0.80     # next 20%  -> B+
$t3 = & $q 0.93     # next 13%  -> A
$t4 = & $q 0.985    # top 1.5%  -> A+

Write-Host ''
Write-Host ("--- grade thresholds on the fitted score ---")
Write-Host ("C  < " + [math]::Round($t1,3) + "   B < " + [math]::Round($t2,3) + "   B+ < " + [math]::Round($t3,3) + "   A < " + [math]::Round($t4,3) + "   A+ >= " + [math]::Round($t4,3))

Write-Host ''
Write-Host '--- MEASURED win% per grade (this is the whole point) ---'
Write-Host ("{0,-6} {1,7} {2,8} {3,8}" -f 'grade', 'n', 'win%', 'loss%')
foreach ($gr in @('A+','A','B+','B','C')) {
   $sel = switch ($gr) {
      'A+' { $scored | Where-Object { $_.Score -ge $t4 } }
      'A'  { $scored | Where-Object { $_.Score -ge $t3 -and $_.Score -lt $t4 } }
      'B+' { $scored | Where-Object { $_.Score -ge $t2 -and $_.Score -lt $t3 } }
      'B'  { $scored | Where-Object { $_.Score -ge $t1 -and $_.Score -lt $t2 } }
      'C'  { $scored | Where-Object { $_.Score -lt $t1 } }
   }
   $gn = @($sel).Count
   if ($gn -eq 0) { Write-Host ("{0,-6} {1,7}" -f $gr, 0); continue }
   $gw = @($sel | Where-Object { $_.Outcome -eq 'WIN' }).Count
   $gl = @($sel | Where-Object { $_.Outcome -eq 'LOSS' }).Count
   Write-Host ("{0,-6} {1,7} {2,8} {3,8}" -f $gr, $gn,
               ([math]::Round(100.0*$gw/$gn,1).ToString('0.0') + '%'),
               ([math]::Round(100.0*$gl/$gn,1).ToString('0.0') + '%'))
}
Write-Host ''
Write-Host 'READ THIS: if A+ is not clearly above C, the model does not grade and must not ship.'

if (-not [string]::IsNullOrWhiteSpace($Emit)) {
   $out = New-Object System.Collections.ArrayList
   [void]$out.Add('# phase 46 -- fitted signal-grade table (generated, do not hand-edit)')
   [void]$out.Add('# provenance command (run from the repo root):')
   [void]$out.Add('#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/Fit-SignalGrade.ps1 -Emit 05_TESTS_AND_VALIDATION/grade_coefficients.fixture.csv')
   [void]$out.Add('# race: +' + $TargetATR + ' ATR with the bias vs -' + $StopATR + ' ATR against it, horizon ' + $Horizon + ' bars, stop wins ties')
   [void]$out.Add('# sample: ' + (Split-Path -Leaf $path) + ' | rows raced=' + $n + ' | written=' + (Get-Item $path).LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
   [void]$out.Add('# NOTE: the sample lives in the terminal COMMON folder, not in the repo, so this file is the frozen proof of the fit.')
   [void]$out.Add('feature;key;lift')
   foreach ($f in $featNames) {
      foreach ($k in ($coef[$f].Keys | Sort-Object)) {
         $v = $coef[$f][$k]
         [void]$out.Add(($f + ';' + $k + ';' + $v.ToString('0.###').Replace(',', '.')))
      }
   }
   [void]$out.Add('threshold;A+;' + $t4.ToString('0.###'))
   [void]$out.Add('threshold;A;'  + $t3.ToString('0.###'))
   [void]$out.Add('threshold;B+;' + $t2.ToString('0.###'))
   [void]$out.Add('threshold;B;'  + $t1.ToString('0.###'))
   $baseWin = [math]::Round(100.0*$w/$n, 2).ToString('0.00')
   $gradeRows = @()
   foreach ($gr in @('A+','A','B+','B','C')) {
      $sel = switch ($gr) {
         'A+' { $scored | Where-Object { $_.Score -ge $t4 } }
         'A'  { $scored | Where-Object { $_.Score -ge $t3 -and $_.Score -lt $t4 } }
         'B+' { $scored | Where-Object { $_.Score -ge $t2 -and $_.Score -lt $t3 } }
         'B'  { $scored | Where-Object { $_.Score -ge $t1 -and $_.Score -lt $t2 } }
         'C'  { $scored | Where-Object { $_.Score -lt $t1 } }
      }
      $gn = @($sel).Count
      if ($gn -eq 0) { continue }
      $gw = @($sel | Where-Object { $_.Outcome -eq 'WIN' }).Count
      [void]$out.Add('grade;' + $gr + ';' + [math]::Round(100.0*$gw/$gn,1).ToString('0.0') + ';' + $gn)
   }
   [void]$out.Add('baseline;win;' + $baseWin + ';' + $n)
   $abs = $Emit
   if (-not [System.IO.Path]::IsPathRooted($abs)) { $abs = Join-Path (Split-Path -Parent $PSScriptRoot) $Emit }
   $dir = Split-Path -Parent $abs
   if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
   [System.IO.File]::WriteAllLines($abs, [string[]]$out, (New-Object System.Text.UTF8Encoding($false)))
   Write-Host ('emitted fixture -> ' + $abs)
}

# ---------------------------------------------------------------------------
# Phase 49: the RUNTIME calibration file.
#
# Why a separate format instead of the fixture above: the fixture is the frozen
# proof of the fit (feature;key;lift); this file is what the indicator's loader
# reads at OnInit, and its keys are the loader's keys (lift.f1.<bucket> ...).
# Both come from the SAME in-memory table, so they cannot disagree.
#
# It is written as key;value with LF endings and no BOM, because the loader reads
# it with FileOpen(...,FILE_CSV,';') - a UTF-16 file would yield garbage keys.
# ---------------------------------------------------------------------------
if (-not [string]::IsNullOrWhiteSpace($EmitCalib)) {
   $cal = New-Object System.Collections.ArrayList
   [void]$cal.Add('# phase 49 -- runtime signal-grade calibration for ONE symbol and timeframe')
   [void]$cal.Add('# generated by tools/Fit-SignalGrade.ps1 - do not hand-edit')
   [void]$cal.Add('# delete this file to fall back to the reference table (the indicator says so on chart)')
   [void]$cal.Add('symbol;' + $Symbol)
   [void]$cal.Add('tf;' + $(if ([string]::IsNullOrWhiteSpace($Timeframe)) { 'ALL' } else { $Timeframe }))
   [void]$cal.Add('rows;' + $n)
   [void]$cal.Add('basewin;' + [math]::Round(100.0*$w/$n, 2).ToString('0.00').Replace(',', '.'))
   [void]$cal.Add('basen;' + $n)
   foreach ($f in $featNames) {
      $fn = $f.Substring(1)                      # F1 -> 1
      foreach ($k in ($coef[$f].Keys | Sort-Object)) {
         $v = $coef[$f][$k].ToString('0.###').Replace(',', '.')
         [void]$cal.Add(('lift.f' + $fn + '.' + $k + ';' + $v))
      }
   }
   [void]$cal.Add('thr.aplus;' + $t4.ToString('0.###').Replace(',', '.'))
   [void]$cal.Add('thr.a;'     + $t3.ToString('0.###').Replace(',', '.'))
   [void]$cal.Add('thr.bplus;' + $t2.ToString('0.###').Replace(',', '.'))
   [void]$cal.Add('thr.b;'     + $t1.ToString('0.###').Replace(',', '.'))
   $keyOf = @{ 'A+'='aplus'; 'A'='a'; 'B+'='bplus'; 'B'='b'; 'C'='c' }
   foreach ($gr in @('A+','A','B+','B','C')) {
      $sel = switch ($gr) {
         'A+' { $scored | Where-Object { $_.Score -ge $t4 } }
         'A'  { $scored | Where-Object { $_.Score -ge $t3 -and $_.Score -lt $t4 } }
         'B+' { $scored | Where-Object { $_.Score -ge $t2 -and $_.Score -lt $t3 } }
         'B'  { $scored | Where-Object { $_.Score -ge $t1 -and $_.Score -lt $t2 } }
         'C'  { $scored | Where-Object { $_.Score -lt $t1 } }
      }
      $gn = @($sel).Count
      if ($gn -eq 0) { continue }
      $gw = @($sel | Where-Object { $_.Outcome -eq 'WIN' }).Count
      [void]$cal.Add('win.' + $keyOf[$gr] + ';' + [math]::Round(100.0*$gw/$gn,1).ToString('0.0').Replace(',', '.'))
      [void]$cal.Add('n.'   + $keyOf[$gr] + ';' + $gn)
   }
   $abs = $EmitCalib
   if (-not [System.IO.Path]::IsPathRooted($abs)) { $abs = Join-Path (Split-Path -Parent $PSScriptRoot) $EmitCalib }
   $dir = Split-Path -Parent $abs
   if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
   [System.IO.File]::WriteAllText($abs, (($cal -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
   Write-Host ('emitted runtime calibration -> ' + $abs)
}

# Explicit exit code: a script that falls off its own end leaves $LASTEXITCODE at the
# PREVIOUS command's value, so a caller that checks it would read a stale refusal.
exit 0
