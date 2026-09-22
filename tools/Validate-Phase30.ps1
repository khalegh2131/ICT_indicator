# Validate-Phase30.ps1
# Locks the phase-30 liquidity corrections. Every rule below traces to an English
# source (no guessing); the request was "review the liquidity rules one by one against
# English sources and close each defect with a locking tool and a build witness".
#
# NOTE: deliberately ASCII-only. Windows PowerShell 5.1 reads .ps1 as ANSI unless the
# file carries a BOM, so non-ASCII inside a script is a parse hazard. Persian strings
# live in the .mq5 source (read as UTF8 below); here we anchor only on ASCII.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root '01_CANONICAL_CANDIDATES\ICT_Assistant_Canonical.mq5'
if (-not (Test-Path -LiteralPath $src)) { throw "Source not found: $src" }
# Flatten the module shell the way MQL5 does (see tools/CanonicalSource.ps1).
. "$PSScriptRoot/CanonicalSource.ps1"
$code = Get-CanonicalSourceText -Path $src

$script:pass = 0
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
    else     { $script:fail++; Write-Host ("FAIL  {0}  {1}" -f $name, $detail) }
}

Write-Host '--- A) PDH/PDL/PWH/PWL anchored to New York midnight (LuxAlgo, ICT Time Anchors) ---'
# "The day's high and low are measured from the midnight open" and "Midnight New York
# time (00:00 ET), not midnight UTC, not the 5:00 pm forex rollover" -> the broker daily
# candle boundary (server midnight) is the classic marking error.
$anchorEnum = ($code -match 'enum ENUM_PD_ANCHOR \{ PD_ANCHOR_NY_MIDNIGHT, PD_ANCHOR_NY_1700, PD_ANCHOR_BROKER_DAY \};')
Check 'day-boundary-enum-exists' $anchorEnum 'NY midnight / NY 17:00 / broker candle'

$anchorDefault = ($code -match 'input ENUM_PD_ANCHOR InpPD_Anchor\s*=\s*PD_ANCHOR_NY_MIDNIGHT;')
Check 'default-boundary-is-ny-midnight' $anchorDefault 'source-backed default (ICT "true day")'

$brokerPathKept = ($code -match 'if\(InpPD_Anchor==PD_ANCHOR_BROKER_DAY\)') -and `
                  ($code -match 'if\(PreviousClosedBucket\(barTime, PERIOD_D1, pdh, pdl, tD\)\)')
Check 'broker-candle-path-still-selectable' $brokerPathKept 'old path preserved behind an explicit option'

$nyDay = ($code -match 'if\(!WindowForDayBack\(back, anchorH,0, anchorH,0, barTime, tD, tW, pdh, pdl, cnt\)\)')
Check 'ny-day-window-is-used' $nyDay 'same DST-aware window machinery as the killzones'

$anchorH = ($code -match 'int anchorH=\(InpPD_Anchor==PD_ANCHOR_NY_1700\)\? 17 : 0;')
Check 'rollover-17-option-wired' $anchorH 'NY 17:00 boundary is the forex rollover day'

$weekHelper = ($code -match 'bool WeekWindowBack\(int anchorH, datetime refBarTime,') -and `
              ($code -match 'startOut=NYWallToServer\(m1.year,m1.mon,m1.day,anchorH,0,0\);') -and `
              ($code -match 'endOut  =NYWallToServer\(m2.year,m2.mon,m2.day,anchorH,0,0\);')
Check 'ny-week-window-is-built' $weekHelper 'PWH/PWL from the NY Monday-anchored week'

$mondayAlign = ($code -match 'int toMonday=\(dow==0\)\? 6 : \(dow-1\);')
Check 'week-is-monday-anchored' $mondayAlign 'NY week root = Monday 00:00 NY'

$weekClosed = ($code -match 'if\(endOut>refBarTime\) continue;\s*// ')
Check 'only-closed-week-is-used' $weekClosed 'an unfinished week is never turned into a level'

Write-Host ''
Write-Host '--- B) no partially covered window may become a "range" (fail-safe, not approximate) ---'
$guardExists = ($code -match 'bool WindowFullyCovered\(datetime startSrv\)')
Check 'coverage-guard-exists' $guardExists 'WindowFullyCovered()'

$guardBody = ($code -match 'return \(g_winCacheT\[copied-1\] <= startSrv\);')
Check 'guard-compares-oldest-cached-bar' $guardBody 'oldest cached bar must be older than the window start'

$iGuardDef = $code.IndexOf('bool WindowFullyCovered(datetime startSrv)')
$iGuardUse = $code.IndexOf('if(!allowOpenWindow && !WindowFullyCovered(startOut)) return false;')
if ($iGuardDef -lt 0) { $iGuardDef = [int]::MaxValue }
Check 'guard-is-defined-before-first-use' ($iGuardDef -lt $iGuardUse) ("def@" + $iGuardDef + " use@" + $iGuardUse)

$guardInSessions = ($code -match 'if\(!allowOpenWindow && !WindowFullyCovered\(startOut\)\) return false;')
Check 'session-and-day-windows-use-the-guard' $guardInSessions 'sessions, PDH/PDL and PWH/PWL share it'

$weekGuard = ($code -match 'if\(!WindowFullyCovered\(startOut\)\) continue;\s*// ')
Check 'week-window-uses-the-guard' $weekGuard 'no truncated weekly range'

Write-Host ''
Write-Host '--- C) trendline liquidity side comes from the SLOPE (LuxAlgo, Trendline Liquidity) ---'
# "below a rising support line sit stops from trendline buyers ... forming a diagonal
# band of sell-side interest" and "the mirror image above a falling one".
$slopeRule = ($code -match 'if\(wantHigh \? !\(b\.price < a\.price\) : !\(b\.price > a\.price\)\)')
Check 'wrong-slope-lines-are-rejected' $slopeRule 'lower highs = buy-side above, higher lows = sell-side below'

$slopeReject = ($code -match 'g_trendlineReject="[^"]*"')
Check 'slope-rejection-is-reported' $slopeReject 'reason text set (observable in the diag CSV)'

Write-Host ''
Write-Host '--- D) trendline needs respected touches (LuxAlgo step 1) ---'
# "Find a clean line with three or more respected touches on a widely watched timeframe"
$minTouchInput = ($code -match 'input int\s+InpTrendlineMinTouches\s*=\s*3;')
Check 'min-touches-input-exists' $minTouchInput 'InpTrendlineMinTouches = 3'

$minTouchUse = ($code -match 'if\(tl\.touches < MathMax\(2,InpTrendlineMinTouches\)\)')
Check 'min-touches-is-enforced' $minTouchUse 'never below 2 (the two anchors themselves)'

Write-Host ''
Write-Host '--- E) trendline SWEEP (poke through + close back) is detected and registered ---'
# LuxAlgo Trendline Liquidity step 4: "a sharp poke through the line that stalls quickly
# and reclaims it suggests a sweep of trendline liquidity". LuxAlgo Liquidity Sweep
# step 3: "a trade through the level followed by a close back inside the prior range".
$tlSweepFn = ($code -match 'long DetectTrendlineSweep\(double barHigh, double barLow, double barClose, datetime t, ENUM_DIRECTION &outDir\)')
Check 'trendline-sweep-function-exists' $tlSweepFn 'same axis rule as the horizontal sweep engine'

$tlSweepRule = ($code -match 'bool sweptHere = g_trendlines\[i\]\.isHigh \? \(barHigh > lvl && barClose < lvl\)\s*\r?\n\s*: \(barLow  < lvl && barClose > lvl\);')
Check 'poke-through-plus-close-back' $tlSweepRule 'wick beyond the line, close back on the origin side'

$tlReg = ($code -match 'long id=AddLiquidity\(g_trendlines\[i\]\.isHigh\? LIQ_TRENDLINE_H : LIQ_TRENDLINE_L,')
Check 'swept-line-becomes-a-liquidity-object' $tlReg 'so it can join the causal event chain'

$tlConsumed = ($code -match 'g_liquidity\[k\]\.state=LSTATE_SWEPT;\s*\r?\n\s*g_liquidity\[k\]\.sweptTime=t;')
Check 'swept-level-is-marked-consumed' $tlConsumed 'cannot be swept twice on the next bar'

$tlTypes = ($code -match 'LIQ_TRENDLINE_H, LIQ_TRENDLINE_L \};')
Check 'trendline-liquidity-types-appended-last' $tlTypes 'enum values of existing members stay stable'

$tlSideMap = ($code -match 'type==LIQ_TRENDLINE_H\);')
Check 'trendline-high-is-buy-side' $tlSideMap 'IsHighSideLiquidity covers the new type'

$tlInChain = ($code -match 'if\(liqId==-1 && tlSweepId!=-1\) \{ liqId=tlSweepId; sweepDir=tlSweepDir; \}')
Check 'trendline-sweep-can-drive-the-event' $tlInChain 'horizontal levels keep priority'

$tlFields = ($code -match 'bool\s+swept;\s*\r?\n\s*datetime\s+sweptTime;\s*\r?\n\s*double\s+sweptPrice;')
Check 'trendline-object-carries-sweep-state' $tlFields 'swept / sweptTime / sweptPrice'

$tlInit = ($code -match 'tl\.swept=false; tl\.sweptTime=0; tl\.sweptPrice=0\.0;')
Check 'sweep-state-is-initialised-at-birth' $tlInit 'uninitialised struct fields would fake a sweep'

$tlObservable = (($code -match 'int tlOk=0, tlInv=0, tlTouch=0, tlSwept=0;') -and `
                 ($code -match '"TrendlineTouches","TrendlineSwept"') -and `
                 ($code -match 'tlOk, tlInv, tlTouch, tlSwept,'))
Check 'sweep-count-is-observable' $tlObservable 'diag header + row carry it (evidence, not a claim)'

# Phase 42 rewrote the family's teaching text: no Latin word may sit inside a
# Persian clause, so the old "LIQ_TRENDLINE_H (Buy-Side)" row became a Persian
# sentence. The invariant is unchanged - the panel must still state (a) the
# sweep rule and (b) which side of the line the liquidity sits on - so the
# check now asserts the content, not the old English spelling.
# Persian is built from codepoints: a .ps1 without a UTF-8 BOM is decoded with
# the system ANSI codepage by Windows PowerShell 5.1, so a literal would turn
# into mojibake and the check would fail for an unrelated reason.
$chSad = [char]0x0633; $chGhaf = [char]0x0642; $chFe = [char]0x0641
$chKaf = [char]0x06A9
$wordCeiling = "$chSad$chGhaf$chFe"   # سقف - "ceiling" = buy-side liquidity
$wordFloor   = "$chKaf$chFe"          # کف  - "floor"  = sell-side liquidity

$tlFnStart = $code.IndexOf('void ExplainTrendline(')
$tlFnEnd   = if ($tlFnStart -ge 0) { $code.IndexOf("`n}`n", $tlFnStart) } else { -1 }
$tlFn = if ($tlFnStart -ge 0 -and $tlFnEnd -gt $tlFnStart) { $code.Substring($tlFnStart, $tlFnEnd - $tlFnStart) } else { '' }

$tlExplain = (($code -match 'if\(g_trendlines\[idx\]\.swept\)\s*\r?\n\s*\{\s*\r?\n\s*ExpAdd\(StringFormat\(') -and `
             ($code -match 'g_trendlines\[idx\]\.sweptTime') -and `
             ($code -match 'g_trendlines\[idx\]\.sweptPrice') -and `
             ($tlFn -match $wordCeiling) -and ($tlFn -match $wordFloor) -and `
             ($code -notmatch 'LIQ_TRENDLINE_H \(Buy-Side\)'))
Check 'panel-explains-the-sweep' $tlExplain 'teaching panel states the rule (further wick + closing back) and the registered level (sweptTime / sweptPrice), and names both sides of the line in Persian'

$tlDraw = ($code -match 'OBJPROP_STYLE,g_trendlines\[i\]\.swept\?STYLE_DASH:STYLE_DOT\);')
Check 'swept-line-is-visually-separated' $tlDraw 'dashed, not deleted (kept as history)'

Write-Host ''
Write-Host '--- F) regression anchors: rules verified correct stay untouched ---'
$sweepRule = ($code -match 'if\(isHighType && barHigh > g_liquidity\[i\]\.price && barClose < g_liquidity\[i\]\.price\)')
$sweepRule2 = ($code -match 'if\(!isHighType && barLow < g_liquidity\[i\]\.price && barClose > g_liquidity\[i\]\.price\)')
Check 'horizontal-sweep-rule-unchanged' ($sweepRule -and $sweepRule2) 'wick through + close back (LuxAlgo Liquidity Sweep)'

$accept = ($code -match 'if\(highSide  && curClose > g_liquidity\[i\]\.price\) g_liquidity\[i\]\.state=LSTATE_INVALID;')
Check 'level-acceptance-rule-unchanged' $accept 'close beyond the level = consumed, kept on chart'

$eqTol = ($code -match 'tol = MathMax\(tol, atrValue\*InpEQ_ToleranceATR\);')
Check 'eqh-eql-tolerance-scales-with-atr' $eqTol 'fixed points alone are meaningless on XAUUSD'

$kzDefaults = (($code -match 'input int\s+InpAsiaStartHourNY\s+=\s+20;') -and `
               ($code -match 'input int\s+InpLondonStartHourNY\s+=\s+2;') -and `
               ($code -match 'input int\s+InpLondonEndHourNY\s+=\s+5;') -and `
               ($code -match 'input int\s+InpNY_KZ_StartHourNY\s+=\s+7;') -and `
               ($code -match 'input int\s+InpNY_KZ_EndHourNY\s+=\s+10;'))
Check 'killzone-defaults-unchanged' $kzDefaults 'Asia 20-00, London 02-05, NY AM 07-10 (NY clock)'

$ipdaAnchor = ($code -match 'int ch=CopyHigh\(_Symbol,PERIOD_D1,1,days,hiArr\);')
Check 'ipda-uses-previous-20-40-60-days' $ipdaAnchor 'starts at bar 1 so today is excluded'

Write-Host ''
Write-Host '--- G) EQH/EQL need separation and an anchor tolerance (LuxAlgo, Equal Highs/lows As Liquidity) ---'
# Step 2: "Require separation: a meaningful pullback between the swings, so they read
# as distinct tests rather than one drawn-out top". Standard implementations pair
# "two consecutive pivots" - two same-side pivots with an opposite pivot in between.
$sepInput = ($code -match 'input double InpEQ_MinSeparationATR\s*=\s*0\.0;')
Check 'eq-separation-input-exists' $sepInput 'InpEQ_MinSeparationATR (0 = structural rule only)'

$sepFn = ($code -match 'bool HasPullbackBetween\(SwingPoint &swings\[\], int i, int j, bool isHigh, double tol, double atrValue\)')
Check 'eq-separation-helper-exists' $sepFn 'HasPullbackBetween()'

$sepUsed = ($code -match 'if\(!HasPullbackBetween\(swings, i, j, isHigh, tol, atrValue\)\) continue;')
Check 'eq-separation-is-enforced' $sepUsed 'a member without a separating pullback is not merged'

$sepOpposite = ($code -match 'if\(swings\[k\]\.isHigh==isHigh\) continue;\s*// ')
Check 'separation-counts-opposite-swings-only' $sepOpposite 'the pullback is an opposite-side confirmed swing'

$sepDepth = ($code -match 'if\(depth>=need\) return true;')
Check 'separation-must-be-deep-enough' $sepDepth 'depth >= max(tolerance, factor x ATR)'

# "two or more swing highs stalling within a few ticks of one another" + "draw a band
# covering the slightly uneven extremes": tolerance is measured against the cluster
# anchor, not against a running extreme (which chained a descending ladder of highs
# into one pool whose two ends were a dollar apart).
$anchorTol = ($code -match 'double anchor = swings\[i\]\.price;') -and `
             ($code -match 'if\(MathAbs\(swings\[j\]\.price-anchor\) > tol\) break;')
Check 'cluster-tolerance-is-anchor-based' $anchorTol 'out of the anchor band ends the cluster'

$chainingGone = ($code -match 'MathAbs\(swings\[j\]\.price-extreme\) > tol')
Check 'old-moving-extreme-chaining-is-gone' (-not $chainingGone) ("old chained comparison still present = " + $chainingGone)

$iSepFn = $code.IndexOf('bool HasPullbackBetween(SwingPoint &swings[]')
$iSepUse = $code.IndexOf('if(!HasPullbackBetween(swings, i, j, isHigh, tol, atrValue)) continue;')
Check 'separation-helper-defined-before-use' (($iSepFn -ge 0) -and ($iSepFn -lt $iSepUse)) ("def@" + $iSepFn + " use@" + $iSepUse)

$eqPanel = ($code -match 'Require separation')
Check 'panel-reports-the-separation-rule' $eqPanel 'teaching panel names the source and the tunable'

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ("RESULT: PASS=" + $script:pass + " FAIL=" + $script:fail)
    exit 0
} else {
    Write-Host ("RESULT: PASS=" + $script:pass + " FAIL=" + $script:fail)
    exit 1
}
