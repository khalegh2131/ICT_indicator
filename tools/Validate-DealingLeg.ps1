# Validate-DealingLeg.ps1  (Phase 10 independent check)
# Reads ICT_Assistant_Canonical_Leg_Diag.csv (written by the indicator) and
# recomputes, from the RAW pivot anchors, every number the panel/Explain shows:
#   range, EQ, OTE band (62/79%), golden (70.5%), leg size in ATR, risk, real R:R.
# This is the acceptance test for #43 / #45 / #46 / #66: the printed levels must
# equal a manual fib drawn on the same two pivots.
# Read-only: it never writes into MT5 folders.

param(
   [string]$CsvPath = "$env:APPDATA\MetaQuotes\Terminal\Common\Files\ICT_Assistant_Canonical_Leg_Diag.csv"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CsvPath)) {
   Write-Host "NO DATA YET: $CsvPath"
   Write-Host "Reload the chart (Remove -> Navigator Refresh -> Add) once, then run again."
   exit 2
}

$raw = Get-Content -LiteralPath $CsvPath -Encoding UTF8
if ($raw.Count -lt 2) {
   Write-Host "CSV has no data row yet (only header)."
   exit 2
}

# The indicator writes FILE_UNICODE CSV with ';' separator.
function Split-Row([string]$line) {
   $line.Trim().TrimStart([char]0xFEFF).Split(';')
}

$header = Split-Row $raw[0]
$cols   = @{}
for ($i = 0; $i -lt $header.Count; $i++) { $cols[$header[$i].Trim()] = $i }

$row = Split-Row $raw[$raw.Count - 1]
function F([string]$name) { [double]::Parse(($row[$cols[$name]] -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture) }
function S([string]$name) { $row[$cols[$name]] }

$fails = 0
function Check([string]$label, [bool]$ok, [string]$detail) {
   if ($ok) { Write-Host ("PASS  {0}  {1}" -f $label, $detail) }
   else     { Write-Host ("FAIL  {0}  {1}" -f $label, $detail); $script:fails++ }
}

Write-Host "=== Leg diagnostics row ==="
Write-Host ("symbol={0} chartTF={1} snapshot={2} legValid={3} reject={4}" -f (S 'Symbol'), (S 'ChartTF'), (S 'Time'), (S 'LegValid'), (S 'Reject'))

if ((S 'LegValid') -ne '1') {
   Write-Host "Leg is not valid right now - reject reason above. No math to verify."
   exit 0
}

$dir        = (S 'LegDir')
$startPrice = F 'StartPrice'
$endPrice   = F 'EndPrice'
$low        = F 'Low'
$high       = F 'High'
$range      = F 'Range'
$sizeATR    = F 'SizeATR'
$atr        = F 'ATR'
$eq         = F 'EQ'
$oteLow     = F 'OTELow'
$oteHigh    = F 'OTEHigh'
$golden     = F 'Golden'
$oteLowIn   = F 'OTELowInput'
$oteHighIn  = F 'OTEHighInput'
$goldenIn   = F 'GoldenInput'
$minLegATR  = F 'MinLegATRInput'
$close      = F 'AnalysisClose'

# --- اصلاح ابزار (یافتهٔ فاز ۱۳) ---------------------------------------------------
# نسخهٔ قبلی این ابزار با تلورانس range*1e-7 کار می‌کرد، در حالی که نویسندهٔ CSV
# هر قیمت را با DoubleToString(...,_Digits) می‌نویسد؛ پس همین گِردکردن باعث
# شکست ۷ چک روی دادهٔ زنده می‌شد (نه خطای محاسبه). اینجا تلورانس از **دقت واقعی
# نوشته‌شده** استخراج می‌شود: بیشترین رقم اعشار در ستون‌های قیمت = گام گِردکردن.
# جهت هم با DirToStr نوشته می‌شود و «BULLISH/BEARISH» است، نه «BULL/BEAR».
function Decimals([string]$s) {
   $t = $s.Trim()
   $i = $t.IndexOf('.')
   if ($i -lt 0) { return 0 }
   return ($t.Length - $i - 1)
}
$wp = 0
foreach ($nm in @('Low','High','EQ','OTELow','OTEHigh','Golden','StartPrice','EndPrice','ATR')) {
   $d = Decimals (S $nm)
   if ($d -gt $wp) { $wp = $d }
}
$ulp = [Math]::Pow(10, -$wp)
$tol = [Math]::Max($range * 1e-9, 2.0 * $ulp)
$isBull = ($dir -eq 'BULL' -or $dir -eq 'BULLISH')
$isBear = ($dir -eq 'BEAR' -or $dir -eq 'BEARISH')
Write-Host ("write precision: {0} decimal(s), ulp={1}, price tolerance={2}" -f $wp, $ulp, $tol)

Write-Host "=== 1) anchors / ordering (#43) ==="
Check "range = high-low" ([Math]::Abs($range - ($high - $low)) -le $tol) ("range={0}" -f $range)
Check "low < high"      ($low -lt $high)                                       ("low={0} high={1}" -f $low, $high)
if ($isBull) {
   Check "bull leg: start pivot is the LOW"  ([Math]::Abs($startPrice - $low) -le $tol)  ("start={0} low={1}" -f $startPrice, $low)
   Check "bull leg: end pivot is the HIGH"   ([Math]::Abs($endPrice - $high) -le $tol)   ("end={0} high={1}" -f $endPrice, $high)
} elseif ($isBear) {
   Check "bear leg: start pivot is the HIGH" ([Math]::Abs($startPrice - $high) -le $tol) ("start={0} high={1}" -f $startPrice, $high)
   Check "bear leg: end pivot is the LOW"    ([Math]::Abs($endPrice - $low) -le $tol)    ("end={0} low={1}" -f $endPrice, $low)
} else {
   Check "leg direction is BULL or BEAR" $false ("dir={0}" -f $dir)
}
Check "leg size >= minLegATR*ATR" (($minLegATR -le 0) -or ($atr -le 0) -or ($sizeATR -ge $minLegATR - $tol)) `
      ("sizeATR={0} minInput={1}" -f $sizeATR, $minLegATR)
if ($atr -gt 0) {
   # sizeATR=range/ATR است، ولی هر دو ورودی گِردشده‌اند؛ تلورانس را تحلیلی می‌سازیم:
   # خطای نسبی range و ATR را روی همان نسبت منتقل می‌کنیم (گِردکردن sizeATR هم اضافه می‌شود).
   $tolSizeATR = 2.0 * $ulp * $sizeATR * (1.0 / [Math]::Max($range, $ulp) + 1.0 / [Math]::Max($atr, $ulp)) + $ulp
   Check "sizeATR = range/ATR" ([Math]::Abs($sizeATR - ($range / $atr)) -le $tolSizeATR) `
         ("sizeATR={0} range/ATR={1} tol={2:N4}" -f $sizeATR, [Math]::Round($range / $atr, 4), $tolSizeATR)
}

Write-Host "=== 2) EQ / premium-discount (#45) ==="
$eqExpect = $low + $range * 0.5
Check "EQ = low + range/2" ([Math]::Abs($eq - $eqExpect) -le $tol) ("written={0} expected={1}" -f $eq, $eqExpect)
$side = if ($close -ge $eq) { 'PREMIUM' } else { 'DISCOUNT' }
Check "side label matches close vs EQ" ((S 'Side') -eq $side) ("close={0} eq={1} label={2}" -f $close, $eq, (S 'Side'))

Write-Host "=== 3) OTE band + golden, recomputed from raw pivots (#46) ==="
if ($isBull) {
   $oteLowExpect  = $high - $range * $oteHighIn
   $oteHighExpect = $high - $range * $oteLowIn
   $goldenExpect  = $high - $range * $goldenIn
} else {
   $oteLowExpect  = $low + $range * $oteLowIn
   $oteHighExpect = $low + $range * $oteHighIn
   $goldenExpect  = $low + $range * $goldenIn
}
Check "OTE low boundary (79% side)"  ([Math]::Abs($oteLow  - $oteLowExpect)  -le $tol) ("written={0} manual-fib={1}" -f $oteLow,  $oteLowExpect)
Check "OTE high boundary (62% side)" ([Math]::Abs($oteHigh - $oteHighExpect) -le $tol) ("written={0} manual-fib={1}" -f $oteHigh, $oteHighExpect)
Check "golden 70.5%"                 ([Math]::Abs($golden  - $goldenExpect)  -le $tol) ("written={0} manual-fib={1}" -f $golden,  $goldenExpect)
Check "OTE band ordered"             ($oteLow -lt $oteHigh)                              ("lowBound={0} highBound={1}" -f $oteLow, $oteHigh)
Check "golden inside OTE band"       ($golden -ge $oteLow - $tol -and $golden -le $oteHigh + $tol) ("golden={0} band=[{1},{2}]" -f $golden, $oteLow, $oteHigh)
# برعکسِ عددی: درصد ریتریس هر مرز باید همان ورودی ۶۲/۷۹ باشد.
# یافتهٔ فاز ۱۳: نسخهٔ قبلی فقط فرمول لگ صعودی را داشت و روی لگ نزولی هم همان را
# حساب می‌کرد؛ نتیجه همیشه ~۴۱٪ انحراف می‌داد. فرمول هر جهت درست شد و آستانه
# هم از گِردکردن نوشتن می‌آید، نه از یک عدد دلبخواه.
if ($isBull) {
   $pctFar  = [Math]::Abs(($high - $oteLow)  / $range - $oteHighIn) * 100
   $pctNear = [Math]::Abs(($high - $oteHigh) / $range - $oteLowIn)  * 100
} else {
   $pctFar  = [Math]::Abs(($oteHigh - $low) / $range - $oteHighIn) * 100
   $pctNear = [Math]::Abs(($oteLow  - $low) / $range - $oteLowIn)  * 100
}
$pctTol = 100.0 * (2.0 * $ulp) / [Math]::Max($range, $ulp)
Check "band boundaries really are 62/79 percent retracement" ($pctFar -le $pctTol -and $pctNear -le $pctTol) `
      ("deviation far={0:N4}% near={1:N4}% (tol={2:N4}%)" -f $pctFar, $pctNear, $pctTol)

Write-Host "=== 4) SL / real R:R (#66) ==="
$status = S 'SetupStatus'
Write-Host ("setupStatus={0} zoneSource={1}" -f $status, (S 'ZoneSource'))
if ($status -eq 'READY') {
   $entry = F 'Entry'; $sl = F 'SL'; $tp3 = F 'TP3'; $risk = F 'Risk'; $rr = F 'RR'
   Check "SL is not zero" ($sl -ne 0) ("sl={0}" -f $sl)
   Check "risk = |entry-sl| > 0" ($risk -gt 0 -and [Math]::Abs($risk - [Math]::Abs($entry - $sl)) -le $tol) ("risk={0}" -f $risk)
   Check "R:R = |tp3-entry|/risk (not the input constant)" ([Math]::Abs($rr - ([Math]::Abs($tp3 - $entry) / $risk)) -le 0.01) ("rr={0} recomputed={1}" -f $rr, [Math]::Round([Math]::Abs($tp3 - $entry) / $risk, 4))
   Check "SL on the correct side of entry" (($isBull -and $sl -lt $entry) -or ($isBear -and $sl -gt $entry)) ("entry={0} sl={1}" -f $entry, $sl)
   Check "TP3 beyond entry in trade direction" (($isBull -and $tp3 -gt $entry) -or ($isBear -and $tp3 -lt $entry)) ("entry={0} tp3={1}" -f $entry, $tp3)
   Check "chain of proof recorded" ((S 'ChainSweep') -ne '-1' -and (S 'ChainEvent') -ne '-1' -and (S 'ChainDisp') -ne '-1') `
         ("sweep={0} event={1} displacement={2}" -f (S 'ChainSweep'), (S 'ChainEvent'), (S 'ChainDisp'))
} else {
   Write-Host "Setup is not READY, so entry/SL/RR are intentionally not active (no READY claim to verify)."
}

Write-Host ""
if ($fails -eq 0) { Write-Host "RESULT: all phase-10 leg checks passed (0 mismatches)"; exit 0 }
Write-Host ("RESULT: {0} check(s) FAILED" -f $fails)
exit 1
