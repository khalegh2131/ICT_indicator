<#
  Fit-PendingScenario.ps1
  ------------------------------------------------------------------
  READ-ONLY. Answers one question FROM THE DATA, not from intuition:

      price is near the protected level and we are waiting for a candle
      to close - how likely is it that the NEXT closed HTF candle
      actually closes beyond that level?

  Method (nothing invented):
    1. read the indicator's reversal ledger for one symbol (it writes one
       row per closed HTF bar, plus a row whenever the state changes)
    2. group rows into EPISODES: a run of rows sharing the same protected
       swing id. While that id is fixed the pending condition is fixed.
    3. inside an episode keep the LAST state of each closed HTF bar. A bar
       whose state is ARMED is an observation of "waiting"; CONFIRMED means
       the bar closed beyond the protected level.
    4. join with the reverse-risk ledger (same symbol, same bar timestamp)
       for the chart ATR, so distance is measured in ATR and not in price.
       Price units do not transfer between symbols.
    5. bucket |last closed HTF close - protected level| / ATR and count how
       often the NEXT observed closed HTF bar confirmed.

  Honest limits (printed, not buried):
    * the unit is one OBSERVED closed HTF bar transition. While MT5 was
      closed no state rows were written, so one transition can span more
      than one HTF bar (most gaps are 4h; weekends are longer). The table is
      therefore per observed transition, not per wall-clock HTF bar.
    * one symbol, one archive window. n is printed for every bucket and a
      bucket below -MinSamples is reported as UNFITTED, never guessed.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/Fit-PendingScenario.ps1
    powershell ... tools/Fit-PendingScenario.ps1 -Symbol XAUUSD.x -Emit 05_TESTS_AND_VALIDATION/pending_scenario.fixture.csv
#>
param(
   [string]$FilesDir = (Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'),
   [string]$Symbol = 'XAUUSD.x',
   [int]$MinSamples = 10,
   [string]$Emit = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Pick the ledger that is being written NOW: the newest file matching the pattern.
# The newest wins on purpose - a legacy file without a timeframe suffix may still
# exist, and preferring it by exact name would freeze the fit on stale rows.
function Find-Ledger([string]$pattern, [string]$exact) {
   $cand = @(Get-ChildItem -LiteralPath $FilesDir -Filter $pattern -ErrorAction SilentlyContinue)
   if ($cand.Count -eq 0) {
      $full = Join-Path $FilesDir $exact
      if (Test-Path -LiteralPath $full) { return $full }
      return $null
   }
   return ($cand | Sort-Object LastWriteTime -Descending)[0].FullName
}

$revExact = 'ICT_Assistant_Canonical_Reversal_Diag.csv'
$revPath = Find-Ledger 'ICT_Assistant_Canonical_Reversal_Diag*.csv' $revExact
if (-not $revPath) {
   Write-Output ("MISSING: reversal ledger under " + $FilesDir)
   exit 2
}
Write-Output ("reversal ledger : " + (Split-Path -Leaf $revPath))
if ((Split-Path -Leaf $revPath) -eq $revExact) {
   Write-Output "NOTE            : legacy name, no chart-timeframe suffix in the file name."
   Write-Output "                  Rows written from phase 47 on carry a ChartTF column and a"
   Write-Output "                  suffixed file name, so two charts stop sharing one file."
}

# The chart ATR is only available from the reverse-risk ledger.
$atr = @{}
$rrPath = Find-Ledger ("ICT_Assistant_Canonical_ReverseRisk_" + $Symbol + "*.csv") ("ICT_Assistant_Canonical_ReverseRisk_" + $Symbol + ".csv")
if (-not $rrPath) {
   Write-Output "atr ledger      : MISSING - distance cannot be normalised; aborting."
   exit 2
}
Write-Output ("atr ledger      : " + (Split-Path -Leaf $rrPath))
foreach ($ln in (Get-Content -LiteralPath $rrPath -Encoding Unicode)) {
   $c = $ln.TrimEnd("`r") -split ';'
   if ($c.Count -lt 7) { continue }
   if ($c[0] -notmatch '^\d{4}\.\d{2}\.\d{2}') { continue }
   $a = 0.0
   if ([double]::TryParse($c[5], [ref]$a) -and $a -gt 0) {
      if (-not $atr.ContainsKey($c[0])) { $atr[$c[0]] = $a }
   }
}
Write-Output ("atr rows indexed: {0}" -f $atr.Count)

# --- rows for this symbol only ---------------------------------------------
$rows = New-Object System.Collections.ArrayList
foreach ($ln in (Get-Content -LiteralPath $revPath -Encoding Unicode)) {
   $c = $ln.TrimEnd("`r") -split ';'
   if ($c.Count -lt 20) { continue }
   if ($c[1] -ne $Symbol) { continue }
   $gp = 0.0; $hc = 0.0
   [void][double]::TryParse($c[5], [ref]$gp)
   [void][double]::TryParse($c[8], [ref]$hc)
   [void]$rows.Add([pscustomobject]@{ state = $c[2]; gid = $c[4]; gp = $gp; side = $c[6]; hbar = $c[7]; hclose = $hc })
}
Write-Output ("rows for {0}: {1}" -f $Symbol, $rows.Count)
if ($rows.Count -eq 0) {
   Write-Output "no rows for that symbol - nothing to fit"
   exit 3
}

# --- episodes: same guard id = same pending condition ----------------------
$epList = New-Object System.Collections.ArrayList
$cur = $null
foreach ($r in $rows) {
   if ($r.side -ne 'HIGH' -and $r.side -ne 'LOW') { $cur = $null; continue }
   if ($null -eq $cur -or $cur.gid -ne $r.gid) {
      $cur = [pscustomobject]@{ gid = $r.gid; gp = $r.gp; bars = [ordered]@{}; st = [ordered]@{}; cl = [ordered]@{} }
      [void]$epList.Add($cur)
   }
   if ($cur.bars.Contains($r.hbar)) { $cur.st[$r.hbar] = $r.state } else {
      $cur.bars[$r.hbar] = 1
      $cur.st[$r.hbar] = $r.state
      $cur.cl[$r.hbar] = $r.hclose
   }
}
Write-Output ("episodes        : {0}" -f $epList.Count)
if ($epList.Count -eq 0) { exit 4 }

function Get-PendBucket([double]$d) {
   if ($d -lt 0.20) { return 'pendLt020' }
   elseif ($d -lt 0.50) { return 'pend020to050' }
   elseif ($d -lt 1.00) { return 'pend050to100' }
   elseif ($d -lt 2.00) { return 'pend100to200' }
   else { return 'pendGt200' }
}

$order = @('pendLt020', 'pend020to050', 'pend050to100', 'pend100to200', 'pendGt200')
$hits = @{}; $counts = @{}
foreach ($b in $order) { $hits[$b] = 0; $counts[$b] = 0 }
$noAtr = 0
foreach ($e in $epList) {
   $k = @($e.bars.Keys); $s = @($e.st.Values); $c = @($e.cl.Values)
   for ($i = 0; $i -lt ($k.Count - 1); $i++) {
      if ($s[$i] -ne 'ARMED') { continue }
      if (-not $atr.ContainsKey($k[$i])) { $noAtr++; continue }
      $d = [math]::Abs($c[$i] - $e.gp) / $atr[$k[$i]]
      $b = Get-PendBucket $d
      $counts[$b]++
      if ($s[$i + 1] -eq 'CONFIRMED') { $hits[$b]++ }
   }
}

$totN = 0; $totHit = 0
foreach ($b in $order) { $totN += $counts[$b]; $totHit += $hits[$b] }
$base = 0.0
if ($totN -gt 0) { $base = 100.0 * $totHit / $totN }

Write-Output ""
Write-Output "bucket          n     confirmNext    rate      status"
foreach ($b in $order) {
   $n = $counts[$b]
   if ($n -eq 0) {
      Write-Output ("{0,-14} {1,5} {2,11} {3,9}   {4}" -f $b, 0, 0, '-', 'EMPTY')
      continue
   }
   $r = 100.0 * $hits[$b] / $n
   $st = 'ok'
   if ($n -lt $MinSamples) { $st = 'UNFITTED (below -MinSamples)' }
   Write-Output ("{0,-14} {1,5} {2,11} {3,9:N2}%  {4}" -f $b, $n, $hits[$b], $r, $st)
}
Write-Output ""
Write-Output ("baseline: {0:N2}%  ({1}/{2} armed transitions)" -f $base, $totHit, $totN)
Write-Output ("armed transitions skipped for a missing ATR row: {0}" -f $noAtr)

# --- embeds: the exact MQL5 table, so the constant is not hand-copied ------
Write-Output ""
Write-Output "--- paste into 01_CANONICAL_CANDIDATES/modules/32_PendingScenario.mqh ---"
Write-Output "double PendMeasuredRate(string b)"
Write-Output "{"
foreach ($b in $order) {
   $n = $counts[$b]
   if ($n -eq 0 -or $n -lt $MinSamples) { continue }
   Write-Output ("   if(b==`"{0}`") return {1:N1};" -f $b, (100.0 * $hits[$b] / $n))
}
Write-Output "   return 0.0;"
Write-Output "}"
Write-Output "int PendMeasuredN(string b)"
Write-Output "{"
foreach ($b in $order) {
   $n = $counts[$b]
   if ($n -eq 0 -or $n -lt $MinSamples) { continue }
   Write-Output ("   if(b==`"{0}`") return {1};" -f $b, $n)
}
Write-Output "   return 0;"
Write-Output "}"

if ($Emit -ne '') {
   $out = New-Object System.Collections.ArrayList
   [void]$out.Add('bucket;n;confirmNext;ratePct')
   foreach ($b in $order) {
      $n = $counts[$b]
      $r = 0.0
      if ($n -gt 0) { $r = 100.0 * $hits[$b] / $n }
      [void]$out.Add(("{0};{1};{2};{3:N2}" -f $b, $n, $hits[$b], $r))
   }
   $dir = Split-Path -Parent $Emit
   if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
   Set-Content -LiteralPath $Emit -Value $out -Encoding ASCII
   Write-Output ("emitted: " + $Emit)
}
exit 0
