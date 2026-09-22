# Validate-Phase32.ps1
# Locks the phase-32 reverse-risk engine: it must record EVIDENCE, and any real
# percentage must come from the measurement tool on that evidence - never from a
# number the indicator invented.
#
# NOTE: ASCII-only by design (PowerShell 5.1 misreads non-BOM UTF-8 sources).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root '01_CANONICAL_CANDIDATES\ICT_Assistant_Canonical.mq5'
$tool = Join-Path $root 'tools\Report-ReverseRisk.ps1'
if (-not (Test-Path -LiteralPath $src))  { throw "Source not found: $src" }
if (-not (Test-Path -LiteralPath $tool)) { throw "Tool not found: $tool" }
# Flatten the module shell the way MQL5 does (see tools/CanonicalSource.ps1).
. "$PSScriptRoot/CanonicalSource.ps1"
$code = Get-CanonicalSourceText -Path $src
$rep  = Get-Content -Raw -Encoding UTF8 $tool

$script:pass = 0
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
    else     { $script:fail++; Write-Host ("FAIL  {0}  {1}" -f $name, $detail) }
}

Write-Host '--- A) the engine runs per closed bar and can be switched off ---'
$inputOn  = ($code -match 'input bool\s+InpEnableReverseRisk\s+=\s+true;')
$inputCsv = ($code -match 'input bool\s+InpWriteReverseRisk\s+=\s+true;')
Check 'inputs-exist' ($inputOn -and $inputCsv) 'InpEnableReverseRisk / InpWriteReverseRisk'

$fn = ($code -match 'void UpdateReverseRisk\(double curClose, double atrValue, datetime barTime, double curHigh, double curLow\)')
Check 'engine-function-exists' $fn 'UpdateReverseRisk()'

$call = ($code -match 'c0=PROBE_T0; UpdateReverseRisk\(closePrice, atrValue, barTime, highPrice, lowPrice\); PROBE_END\("2s.revRisk",c0\);')
Check 'engine-runs-per-closed-bar' $call 'called in the closed-bar context pipeline (once per bar, with an atomic timer probe)'

$early = ($code -match 'if\(!InpEnableReverseRisk \|\| atrValue<=0\.0 \|\| curClose<=0\.0\) return;')
Check 'engine-fails-safe-without-data' $early 'no ATR / no close -> no row, no claim'

Write-Host ''
Write-Host '--- B) the warning index uses documented weights (a sum, not a probability) ---'
$w25 = ($code -match 'score\+=25;')
$w20 = ($code -match 'score\+=20;')
$w15 = ([regex]::Matches($code, 'score\+=15;')).Count
$w10 = ([regex]::Matches($code, 'score\+=10;')).Count
$wm10 = ($code -match 'score-=10;')
Check 'sweep-against-bias-weight' $w25 '+25: liquidity on the bias side swept and closed back (SFP)'
Check 'fresh-structural-event-weight' $w20 '+20: the character just changed (a young, undecided leg)'
Check 'exhaustion-leg-dol-weights' (($w15 -eq 3) -and ($w10 -eq 2)) ("+15 x3 (exhaustion, leg extreme, draw reached) and +10 x2 (premium/discount late entry) = " + $w15 + "/" + $w10)
Check 'aligned-mtf-reduces-risk' $wm10 '-10: every timeframe agrees with the bias'

$clamp = ($code -match 'if\(score<0\) score=0;') -and ($code -match 'if\(score>100\) score=100;')
Check 'index-is-clamped' $clamp '0..100'

$labels = ($code -match 'g_rrLabel=\(score>=75\)\? "EXTREME" : \(\(score>=50\)\? "HIGH" : \(\(score>=25\)\? "MEDIUM" : "LOW"\)\);')
Check 'labels-are-warning-levels' $labels 'LOW / MEDIUM / HIGH / EXTREME - never a percentage'

$snapshot = ($code -match 'DashRow\("revrisk", StringFormat\("')
Check 'dashboard-row-exists' $snapshot 'compact dashboard shows the read'

$compact = ($code -match 'name=="rr" \|\| name=="revrisk"\)')
Check 'row-is-part-of-the-compact-decision-set' $compact 'it is decision guidance, so COMPACT must not hide it'

Write-Host ''
Write-Host '--- C) the evidence CSV carries everything the measurement needs ---'
$cols = @('"BarTime"','"Bias"','"Price"','"High"','"Low"','"ATR"','"LevelType"','"LevelDistATR"','"LevelState"',
          '"LegProgressPct"','"DOLType"','"DOLDistATR"','"Exhaustion"','"SweptTowardBias"','"EventBarsAgo"',
          '"MTFAligned"','"RiskScore"','"RiskLabel"','"Reasons"')
$missing = @()
foreach ($c in $cols) { if ($code -notmatch [regex]::Escape($c)) { $missing += $c } }
Check 'csv-schema-is-complete' ($missing.Count -eq 0) ("missing: " + ($missing -join ','))

# Phase 46 moved the CSV write into PersistReverseRiskEvidence() and made it run
# after the grade, so the row is filled from the values SAVED for that bar. The
# intent of this check is unchanged: the High/Low of the bar itself reach the file.
$rowHL = ($code -match 'DoubleToString\(g_rrHigh,_Digits\),') -and ($code -match 'DoubleToString\(g_rrLow,_Digits\),') -and
         ($code -match 'g_rrHigh=curHigh;') -and ($code -match 'g_rrLow=curLow;')
Check 'csv-writes-high-and-low' $rowHL 'forward excursion is measured from its own price data, not guessed'

$perSymbol = ($code -match 'DiagOpen\("ICT_Assistant_Canonical_ReverseRisk_"\+_Symbol\+"_"\+ChartTfCode\(\)\+"\.csv"\)')
Check 'csv-is-per-symbol' $perSymbol 'symbols never mix inside one file'
# Phase 47: two live charts of the same symbol used to share one file, so bars of
# two chart timeframes were mixed inside every measurement read from this ledger.
$perTf = ($code -match 'ChartTfCode\(\)')
Check 'csv-is-per-timeframe' $perTf 'chart timeframes never mix inside one file'

$reasons = ($code -match 'g_rrReasons=why;')
Check 'row-carries-the-reasons' $reasons 'every added weight is reported in words'

Write-Host ''
Write-Host '--- D) the nearest level is searched across every registry ---'
$cover = @('g_liquidity','g_obs','g_fvgs','g_sd','g_rangeHigh','g_trendlines')
$missingCov = @()
foreach ($c in $cover) { if ($code.IndexOf($c, $code.IndexOf('void UpdateReverseRisk')) -lt 0) { $missingCov += $c } }
Check 'level-search-covers-all-registries' ($missingCov.Count -eq 0) ("checked: " + ($cover -join ', '))

$levelState = ($code -match 'g_rrLevelState=RRLiqStateName\(g_liquidity\[i\]\.state\);')
Check 'level-state-is-reported' $levelState 'FRESH / SWEPT / ACCEPTED decides whether the level is still a target'

$legProg = ($code -match 'g_rrLegProg=\(g_leg\.dir==DIR_BEAR\? \(1\.0-pos\) : pos\)\*100\.0;')
Check 'leg-progress-is-direction-aware' $legProg '"how far gold has gone" is measured along the leg'

$dol = ($code -match 'g_rrDolDist=\(\(g_currentDOL\.direction==DIR_BULL\)\? \(g_currentDOL\.price-curClose\)')
Check 'distance-to-draw-is-reported' $dol 'how much of the move is still owed'

Write-Host ''
Write-Host '--- E) the measurement tool: real rates only, with sample counts ---'
$minN = ($rep -match '\$MinSamples\s*=\s*10')
Check 'tool-has-a-minimum-sample-size' $minN 'buckets below it are never shown as a rate'

$insufficient = ($rep -match "'insufficient-n'")
Check 'tool-marks-thin-buckets' $insufficient 'no rate is printed without enough samples'

# Phase 46 replaced the single adverse test with a target-vs-stop RACE: the old
# one-condition metric could not separate (measured: label LOW 29.2% vs HIGH
# 29.3%), so it ranked nothing. The tool must now walk the forward bars itself.
$fwd = ($rep -match '\$hitStop = \$\(if \(\$r\.Bias -eq .BULL.\) \{ \$b\.Low') -and
       ($rep -match '\$hitTgt  = \$\(if \(\$r\.Bias -eq .BULL.\) \{ \$b\.High')
Check 'tool-measures-the-forward-move' $fwd 'the forward path is walked bar by bar through High/Low, not guessed'

# The definition sentence wraps over two comment lines, so it is matched in two
# pieces rather than as one span (the earlier single-span form failed on the
# line break, not on the wording).
$def = ($rep -match 'did price travel \+TargetATR') -and ($rep -match 'BEFORE travelling')
Check 'tool-states-its-definition' $def 'the reported win rate has an explicit definition'

# Both legs of the race must flip with the bias (a tool that only handles the
# bullish case would report a one-sided edge), and NEUTRAL bars must be skipped.
$tgtOk  = ($rep -match '\$target = \$r\.Price \+ \$\(if \(\$r\.Bias -eq .BULL.\)')
$stopOk = ($rep -match '\$stop\s+= \$r\.Price \+ \$\(if \(\$r\.Bias -eq .BULL.\)')
$neutral = ($rep -match 'if \(\$r\.Bias -ne .BULL. -and \$r\.Bias -ne .BEAR.\) \{ continue \}')
Check 'tool-handles-both-bias-directions' ($tgtOk -and $stopOk -and $neutral) `
      ("target flips={0}, stop flips={1}, neutral rows skipped={2}" -f $tgtOk, $stopOk, $neutral)

$snap = ($rep -match 'the win rate was') -and ($rep -match 'do not trust a rate here')
Check 'tool-reports-the-latest-situation' $snap 'current read + its measured historical rate (or an honest refusal)'

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ("RESULT: PASS=" + $script:pass + " FAIL=" + $script:fail)
    exit 0
} else {
    Write-Host ("RESULT: PASS=" + $script:pass + " FAIL=" + $script:fail)
    exit 1
}
