<#
  Validate-Phase46.ps1  --  locks the A+/A/B+/B signal grade

  What is proven, and how:
    S1 wiring   -- the grade module is included, computed on the closed bar after
                   exhaustion, and its CSV evidence row is written AFTER the grade
                   (writing it inside the reverse-risk function made every grade
                   column one bar stale - a false witness).
    S2 weights  -- every coefficient in 31_SignalGrade.mqh is compared NUMERICALLY
                   with 05_TESTS_AND_VALIDATION/grade_coefficients.fixture.csv,
                   which tools/Fit-SignalGrade.ps1 generated from the measured
                   evidence file. Nothing here is compared against a hand list.
    S3 rules    -- the family-code prefix rules are re-implemented from the rule
                   text and run over the fixture of REAL level strings, then the
                   same prefix chain is asserted in the MQL5 source.
    S4 ordering -- the measured win% per grade must be strictly decreasing from
                   A+ to C and A+ must sit above the baseline. A grade that does
                   not order anything is a failure, not a warning.
    R1 runtime  -- if the evidence CSV already carries the phase-46 columns, the
                   family, the score and the grade of every row are recomputed
                   here from the recorded features and must match exactly.
                   Before a chart reload the columns do not exist yet -> PENDING,
                   which is honest, rather than a green tick on nothing.

  NOTE: ASCII-only by design (PowerShell 5.1 misreads non-BOM UTF-8 sources).
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src  = Join-Path $root '01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5'
$coefFix = Join-Path $root '05_TESTS_AND_VALIDATION/grade_coefficients.fixture.csv'
$famFix  = Join-Path $root '05_TESTS_AND_VALIDATION/level_family.fixture.csv'

$pass = 0; $fail = 0; $pend = 0
function Check($name, $ok, $detail) {
   if ($ok) { $script:pass++ ; Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
   else     { $script:fail++ ; Write-Host ("FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red }
}
function Pend($name, $detail) { $script:pend++ ; Write-Host ("PEND  {0}  {1}" -f $name, $detail) -ForegroundColor Yellow }
function Num([string]$s) { return [double]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture) }
# Persian is addressed by CODEPOINT, never as a literal in this file: a .ps1
# without a UTF-8 BOM is decoded with the system ANSI codepage by Windows
# PowerShell 5.1, so a literal would silently become mojibake and the check
# would fail for a reason that has nothing to do with the indicator.
$wRiskWord = -join @([char]0x0631,[char]0x06CC,[char]0x0633,[char]0x06A9)

. "$PSScriptRoot/CanonicalSource.ps1"
$code = Get-CanonicalSourceText -Path $src

# returns the body of a function whose signature line starts with $prefix
function Get-Body([string]$text, [string]$prefix) {
   $i = $text.IndexOf($prefix)
   if ($i -lt 0) { return '' }
   $open = $text.IndexOf('{', $i)
   if ($open -lt 0) { return '' }
   $j = $text.IndexOf("`n}", $open)
   if ($j -lt 0) { return $text.Substring($open) }
   return $text.Substring($open, $j - $open)
}

# ---------------------------------------------------------------------
# S1) wiring
# ---------------------------------------------------------------------
$shell = [System.IO.File]::ReadAllText($src)
Check 'grade-module-is-included' ($shell -match '(?m)^\s*#include\s+"modules/31_SignalGrade\.mqh"\s*$') `
      'the shell includes modules/31_SignalGrade.mqh'

# The CHECK must look at the CALL site, not at the definition (the definition of
# UpdateContextForClosedBar lives in module 14 and has no exhaustion call next to it).
$call = $code.IndexOf('UpdateSignalGrade();')
$passOrder = $false
$orderDetail = 'grade call site not found'
if ($call -ge 0) {
   $from = [math]::Max(0, $call - 500)
   $before = $code.Substring($from, $call - $from)
   $after  = $code.Substring($call, [math]::Min(200, $code.Length - $call))
   $pCtx = $before.LastIndexOf('UpdateContextForClosedBar')
   $pExh = $before.LastIndexOf('UpdateExhaustion')
   $pRs  = $after.IndexOf('PersistReverseRiskEvidence')
   $passOrder = ($pCtx -ge 0 -and $pExh -gt $pCtx -and $pRs -gt 0)
   $orderDetail = ("context at -{0}, exhaustion at -{1}, evidence row at +{2}" -f ($call-$from-$pCtx), ($call-$from-$pExh), $pRs)
}
Check 'grade-runs-after-exhaustion-and-the-row-is-written-after-the-grade' $passOrder $orderDetail

$rrBody = Get-Body $code 'void UpdateReverseRisk'
Check 'reverse-risk-function-no-longer-writes-the-row' `
      (($rrBody.Length -gt 0) -and ($rrBody.IndexOf('DiagOpen') -lt 0)) `
      'the CSV write is no longer inside UpdateReverseRisk()'

Check 'grade-columns-are-declared-in-the-evidence-header' `
      ($code -match '"LevelFamily","Grade","GradeScore","GradeWinPct","GradeN"') `
      'the five grade columns are appended at the END of the evidence header so old readers keep working'
Check 'grade-fields-are-written' `
      (($code -match 'g_gradeFam,') -and ($code -match 'DoubleToString\(g_gradeScore,3\),') -and ($code -match 'g_gradeN,?\s*\r?\n?\s*ChartTfCode\(\)\)')) `
      'the row writes the family code, the fitted score and the sample count (phase 47 appended one more column after them)'
Check 'grade-leads-the-strip' `
      ($code -match 'string txt=StringFormat\("GRADE: %s') `
      'GRADE opens the corner strip (Latin-led labels first, Persian after)'
Check 'strip-width-follows-the-text' `
      ($code -match 'int need=\(int\)\(StringLen\(txt\)\*InpExplainFontSize\*0\.62\)\+24;') `
      'the strip is no longer clipped at a fixed 640 px: its width is derived from the row length'

# ---------------------------------------------------------------------
# S2) coefficients -- source vs generated fixture
# ---------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $coefFix)) { throw "coefficient fixture missing: $coefFix" }
$fixLines = [System.IO.File]::ReadAllLines($coefFix, [System.Text.Encoding]::UTF8)

$bodies = @{}
foreach ($fn in 'GradeLiftF1','GradeLiftF2','GradeLiftF3','GradeLiftF4','GradeLiftF7') {
   $bodies[$fn] = Get-Body $code ('double ' + $fn + '(')
}
$featOf = @{ F1 = 'GradeLiftF1'; F2 = 'GradeLiftF2'; F3 = 'GradeLiftF3'; F4 = 'GradeLiftF4'; F7 = 'GradeLiftF7' }
$m5 = [regex]::Match($code, 'double GradeLiftF5\(bool aligned\)\s*\{\s*return aligned\?\s*(-?[0-9.]+)\s*:\s*(-?[0-9.]+);')
$m6 = [regex]::Match($code, 'double GradeLiftF6\(bool swept\)\s*\{\s*return swept\?\s*(-?[0-9.]+)\s*:\s*(-?[0-9.]+);')

$bad = @(); $checked = 0
foreach ($ln in $fixLines) {
   $t = $ln.Trim()
   if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
   $p = $t.Split(';')
   if ($p.Length -lt 3 -or $p[0] -eq 'feature') { continue }
   if ($p[0] -notin @('F1','F2','F3','F4','F5','F6','F7')) { continue }
   $key = $p[1]; $want = Num $p[2]
   $got = $null
   if ($p[0] -eq 'F5') {
      if (-not $m5.Success) { $bad += 'GradeLiftF5 pattern'; continue }
      $got = if ($key -eq 'mtftrue') { Num $m5.Groups[1].Value } else { Num $m5.Groups[2].Value }
   } elseif ($p[0] -eq 'F6') {
      if (-not $m6.Success) { $bad += 'GradeLiftF6 pattern'; continue }
      $got = if ($key -eq 'swepttrue') { Num $m6.Groups[1].Value } else { Num $m6.Groups[2].Value }
   } else {
      $fn = $featOf[$p[0]]
      $m = [regex]::Match($bodies[$fn], ('if\(\w=="' + [regex]::Escape($key) + '"\)\s*return\s+(-?[0-9.]+);'))
      if (-not $m.Success) { $bad += ($fn + ' missing key ' + $key); continue }
      $got = Num $m.Groups[1].Value
   }
   $checked++
   if ([math]::Abs($got - $want) -gt 0.0005) { $bad += ('{0} {1}: source={2} fitted={3}' -f $p[0], $key, $got, $want) }
}
Check 'every-fitted-coefficient-matches-the-source' ($bad.Count -eq 0) `
      ("compared {0} coefficients; mismatches: {1}" -f $checked, (($bad | Select-Object -First 4) -join ' | '))
Check 'coefficient-count-is-not-empty' ($checked -ge 25) ("coefficients compared = $checked")

# ---------------------------------------------------------------------
# S3) family-code rules -- fixture of REAL level strings
# ---------------------------------------------------------------------
function Get-FamilyFromRule([string]$s) {
   $t = $s.ToUpper()
   if ($t.StartsWith('LIQ'))              { return 'famLIQ' }
   if ($t.StartsWith('OB '))              { return 'famOB' }
   if ($t.StartsWith('BREAKER'))          { return 'famBREAKER' }
   if ($t.StartsWith('MITIGATION'))       { return 'famMITIG' }
   if ($t.StartsWith('VOLUME IMBALANCE')) { return 'famFVGVI' }
   if ($t.StartsWith('FVG'))              { return 'famFVG' }
   if ($t.StartsWith('S/D'))              { return 'famSD' }
   if ($t.StartsWith('TRENDLINE'))        { return 'famTL' }
   return 'famOTHER'
}
$famCases = 0; $famBad = @()
foreach ($ln in ([System.IO.File]::ReadAllLines($famFix, [System.Text.Encoding]::UTF8))) {
   $t = $ln.Trim()
   if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
   $p = $t.Split(';')
   if ($p.Length -lt 2) { continue }
   $famCases++
   $got = Get-FamilyFromRule $p[0].Trim()
   if ($got -ne $p[1].Trim()) { $famBad += ("{0} -> {1} expected {2}" -f $p[0], $got, $p[1]) }
}
Check 'family-rule-matches-the-real-level-strings' ($famBad.Count -eq 0) `
      ("cases = $famCases; mismatches: " + (($famBad | Select-Object -First 3) -join ' | '))
Check 'family-fixture-has-enough-cases' ($famCases -ge 20) ("cases = $famCases")

$mqlChain = Get-Body $code 'string RRLevelFamilyCode('
$order = @()
foreach ($m in [regex]::Matches($mqlChain, 'StringFind\(u,"([^"]+)"\)==0\)\s*return "([a-zA-Z]+)";')) {
   $order += ($m.Groups[1].Value + '=' + $m.Groups[2].Value)
}
$wantOrder = @('LIQ=famLIQ', 'OB =famOB', 'BREAKER=famBREAKER', 'MITIGATION=famMITIG',
               'VOLUME IMBALANCE=famFVGVI', 'FVG=famFVG', 'S/D=famSD', 'TRENDLINE=famTL')
Check 'mql5-family-prefix-order-matches-the-fitted-rule' (($order -join ',') -eq ($wantOrder -join ',')) `
      ("source order: " + ($order -join ','))

# ---------------------------------------------------------------------
# S4) thresholds and the measured ordering
# ---------------------------------------------------------------------
$tbl = @{}
$grades = New-Object System.Collections.ArrayList
$baseline = 0.0
foreach ($ln in $fixLines) {
   $t = $ln.Trim()
   if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
   $p = $t.Split(';')
   if ($p[0] -eq 'threshold') { $tbl[$p[1]] = Num $p[2] }
   elseif ($p[0] -eq 'grade') { [void]$grades.Add([pscustomobject]@{ G = $p[1]; Win = Num $p[2]; N = [int]$p[3] }) }
   elseif ($p[0] -eq 'baseline') { $baseline = Num $p[2] }
}
$badT = @()
foreach ($g in 'A+','A','B+','B') {
   $wantTxt = $tbl[$g].ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
   $m = [regex]::Match($code, ('if\(s>=' + [regex]::Escape($wantTxt) + '\) return "' + [regex]::Escape($g) + '";'))
   if (-not $m.Success) { $badT += ($g + ' threshold ' + $wantTxt) }
}
Check 'grade-thresholds-match-the-fitted-quantiles' ($badT.Count -eq 0) ("checked 4 thresholds; missing: " + ($badT -join ', '))

$badW = @()
foreach ($r in $grades) {
   # \s+ on both sides of 'return': the source aligns the values with extra spaces.
   $mw = [regex]::Match($code, ('if\(g=="' + [regex]::Escape($r.G) + '"\)\s+return\s+(-?[0-9.]+);'))
   $mn = [regex]::Match($code, ('if\(g=="' + [regex]::Escape($r.G) + '"\)\s+return\s+([0-9]+);'))
   if (-not $mw.Success) { $badW += ($r.G + ' win missing'); continue }
   if ([math]::Abs((Num $mw.Groups[1].Value) - $r.Win) -gt 0.05) { $badW += ($r.G + ' win ' + $mw.Groups[1].Value + ' vs ' + $r.Win) }
   if ($mn.Success -and [int]$mn.Groups[1].Value -ne $r.N) { $badW += ($r.G + ' n ' + $mn.Groups[1].Value + ' vs ' + $r.N) }
}
Check 'measured-win-and-sample-count-match-the-fit' ($badW.Count -eq 0) ("checked " + $grades.Count + " grades; mismatches: " + ($badW -join ' | '))

# the measured numbers must come from the fitter, not from the fixture alone
$fnBody = Get-Body $code 'void UpdateSignalGrade'
Check 'grade-guard-and-neutral-path-exist' `
      (($fnBody -match 'InpEnableSignalGrade') -and ($fnBody -match 'g_htfBias==DIR_NONE')) `
      'the grade is switchable and stays undetermined when no directional bias exists'

$winSeq = @($grades | Where-Object { $_.G -ne 'C' } | ForEach-Object { $_.Win })
$mono = $true
for ($i = 1; $i -lt $winSeq.Count; $i++) { if ($winSeq[$i] -ge $winSeq[$i-1]) { $mono = $false } }
$cWin = ($grades | Where-Object { $_.G -eq 'C' }).Win
Check 'measured-win-decreases-monotonically-from-A-plus-to-C' ($mono -and ($winSeq[-1] -gt $cWin)) `
      ("sequence = " + ($winSeq -join ' > ') + ' > ' + $cWin)
Check 'top-grade-sits-clearly-above-the-baseline' (($winSeq[0] - $baseline) -ge 15.0) `
      ("A+ {0}% vs baseline {1}% (delta {2})" -f $winSeq[0], $baseline, [math]::Round($winSeq[0]-$baseline,1))
Check 'grade-now-leads-the-strip-and-the-old-index-follows' `
      (($code.IndexOf('GRADE: %s') -ge 0) -and ($code.IndexOf('GRADE: %s') -lt $code.IndexOf('BIAS: %s')) -and
       ($code.Contains($wRiskWord))) `
      'GRADE precedes BIAS in the corner strip, and the uncalibrated risk index is kept only as a secondary field'

# ---------------------------------------------------------------------
# R1) runtime agreement (PENDING until the chart is reloaded)
# ---------------------------------------------------------------------
$filesDir = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$csvPath = ''
if (Test-Path -LiteralPath $filesDir) {
   $cand = @(Get-ChildItem -LiteralPath $filesDir -Filter 'ICT_Assistant_Canonical_ReverseRisk_*.csv' -ErrorAction SilentlyContinue)
   if ($cand.Count -gt 0) { $csvPath = ($cand | Sort-Object LastWriteTime -Descending)[0].FullName }
}

function Bucket-Dist([double]$v) { if ($v -lt 0.25) { return 'distLt025' } elseif ($v -lt 0.5) { return 'dist025to05' } elseif ($v -lt 1.0) { return 'dist05to1' } else { return 'distGt1' } }
function Bucket-Leg([double]$v)  { if ($v -lt 50.0) { return 'legLt50' } elseif ($v -lt 85.0) { return 'leg50to85' } else { return 'legGte85' } }
function Bucket-Dol([double]$v)  { if ($v -le 0.0) { return 'dolNone' } elseif ($v -le 0.5) { return 'dolLe05' } elseif ($v -le 1.0) { return 'dol05to1' } else { return 'dolGt1' } }
function Lift-Of([string]$feat, [string]$key) {
   foreach ($ln in $script:fixLines) {
      $t = $ln.Trim(); if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
      $p = $t.Split(';')
      if ($p.Length -ge 3 -and $p[0] -eq $feat -and $p[1] -eq $key) { return (Num $p[2]) }
   }
   return 0.0
}

if ($csvPath -eq '') {
   Pend 'runtime-grade-agreement' 'no reverse-risk CSV found yet'
} else {
   $lines = Get-Content -LiteralPath $csvPath -Encoding Unicode
   $rows = 0; $withGrade = 0; $misFam = 0; $misGrade = 0; $misScore = 0; $samples = @()
   foreach ($ln in $lines) {
      $p = $ln -split ';'
      if ($p.Count -lt 19) { continue }
      if ($p[1] -notmatch 'BULL|BEAR') { continue }
      $rows++
      if ($p.Count -lt 24) { continue }
      $withGrade++
      $famWant = Get-FamilyFromRule $p[6]
      if ($famWant -ne $p[19]) { $misFam++ }
      $dist = 0.0; $leg = 0.0; $dol = 0.0
      [void][double]::TryParse($p[7], [ref]$dist); [void][double]::TryParse($p[9], [ref]$leg); [void][double]::TryParse($p[11], [ref]$dol)
      $s = (Lift-Of 'F1' $famWant) + (Lift-Of 'F2' (Bucket-Dist $dist)) + (Lift-Of 'F3' (Bucket-Leg $leg)) +
           (Lift-Of 'F4' (Bucket-Dol $dol)) +
           (Lift-Of 'F5' $(if ($p[15] -eq 'true') { 'mtftrue' } else { 'mtffalse' })) +
           (Lift-Of 'F6' $(if ($p[13] -eq 'true') { 'swepttrue' } else { 'sweptfalse' })) +
           (Lift-Of 'F7' ('exh' + $p[12]))
      $recScore = 0.0; [void][double]::TryParse($p[21], [ref]$recScore)
      if ([math]::Abs($s - $recScore) -gt 0.002) { $misScore++ }
      $g = if ($s -ge $tbl['A+']) { 'A+' } elseif ($s -ge $tbl['A']) { 'A' } elseif ($s -ge $tbl['B+']) { 'B+' } elseif ($s -ge $tbl['B']) { 'B' } else { 'C' }
      if ($g -ne $p[20]) { $misGrade++ }
      if ($samples.Count -lt 3) { $samples += ("{0}: fam {1} score {2}/{3} grade {4}/{5}" -f $p[0], $p[19], $s, $p[21], $g, $p[20]) }
   }
   if ($withGrade -eq 0) {
      Pend 'runtime-grade-agreement' ("CSV has {0} bias rows but none with the phase-46 columns yet (needs one chart reload)" -f $rows)
   } else {
      Check 'runtime-family-recomputes-identically' ($misFam -eq 0) ("rows with grade columns = $withGrade; family mismatches = $misFam")
      Check 'runtime-score-recomputes-identically' ($misScore -eq 0) ("score mismatches = $misScore")
      Check 'runtime-grade-recomputes-identically' ($misGrade -eq 0) ("grade mismatches = $misGrade | e.g. " + ($samples -join ' ; '))
   }
}

Write-Host ''
Write-Host '==== RESULT ===='
Write-Host ("PASS={0}  FAIL={1}  PENDING={2}" -f $pass, $fail, $pend)
if ($fail -gt 0) { Write-Host 'RESULT: FAILED'; exit 1 }
Write-Host 'RESULT: PASSED'
exit 0
