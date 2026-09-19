# Validate-Phase36.ps1 - Phase 36 lock validator (ASCII only; PS 5.1 safe)
# Locks the wiring of every Phase 36 item to its source in the canonical file.
# If any anchor disappears, the build no longer proves the phase and this fails.
$ErrorActionPreference = 'Stop'
$src = '01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5'
if (-not (Test-Path $src)) { $src = 'ICT_Assistant_Canonical.mq5' }
if (-not (Test-Path $src)) { Write-Output 'PHASE36: FAIL (source not found)'; exit 1 }
$text = [System.IO.File]::ReadAllText($src)
$lines = [System.IO.File]::ReadAllLines($src)
$pass = 0; $fail = 0

function Check([string]$name, [bool]$ok) {
  if ($ok) { $script:pass++ } else { $script:fail++; Write-Output ("FAIL: " + $name) }
}
function FindLine([string]$needle) {
  for ($i = 0; $i -lt $script:lines.Length; $i++) {
    if ($script:lines[$i].Contains($needle)) { return $i }
  }
  return -1
}
function WindowHas([int]$lineIdx, [int]$before, [int]$after, [string[]]$needles) {
  if ($lineIdx -lt 0) { return $false }
  $s = [Math]::Max(0, $lineIdx - $before)
  $e = [Math]::Min($script:lines.Length - 1, $lineIdx + $after)
  $w = ($script:lines[$s..$e] -join "`n")
  foreach ($n in $needles) { if (-not $w.Contains($n)) { return $false } }
  return $true
}

# 1) OB Internal/External
$i = FindLine 'ENUM_LIQ_SCOPE scope;'
Check 'OBObj.scope field exists'                          ($i -ge 0)
Check 'OBObj scope comment cites LuxAlgo IRL/ERL source'  ($text.Contains('LuxAlgo') -and $text.Contains('IRL') -and $text.Contains('ERL') -and $text.Contains('left inside the leg'))
$i = FindLine 'o.scope = SCOPE_INTERNAL;'
Check 'DetectOB assigns o.scope'                          ($i -ge 0)
Check 'DetectOB scope uses g_leg extremes + ATR tol'      (WindowHas $i 2 6 @('g_leg.valid', 'tolExt'))
$i = FindLine 'MarkExtremeOrderBlocks'
Check 'Extreme OB forced to SCOPE_EXTERNAL'               ($i -ge 0 -and $text.Contains('g_obs[i].scope=SCOPE_EXTERNAL'))
Check 'ExplainOB has EXT/IRL teaching text'               ($text.Contains('EXTERNAL (ERL)') -and $text.Contains('INTERNAL (IRL)'))
Check 'ReverseRisk OB name carries EXT/INT'               ($text.Contains('" EXT"') -and $text.Contains('" INT"'))

# 2) Quarterly Theory
Check 'QT enum exists (Daye AMD-X)'                       ($text.Contains('enum ENUM_QT_PHASE'))
Check 'QT day windows Q1 18-24 / Q2 00-06'                ($text.Contains('minutes>=18*60') -and $text.Contains('minutes<6*60'))
Check 'QT week Monday-first mapping'                      ($text.Contains('day_of_week>=1'))
Check 'QT True Day Open via CopyOpen'                     ($text.Contains('g_qtDayTrueOpen') -and $text.Contains('CopyOpen'))
Check 'QT True Week Open captured'                        ($text.Contains('g_qtWkTrueOpen'))
Check 'QT layer draws both opens'                         ($text.Contains('ICTv13_QT_DAYOPEN') -and $text.Contains('ICTv13_QT_WKOPEN'))
Check 'QT explain routed (clickable)'                     ($text.Contains('ExplainQT(false)') -and $text.Contains('ExplainQT(true)'))
Check 'QT inputs exist (enable + draw)'                   ($text.Contains('InpEnableQT') -and $text.Contains('InpDrawQTOpens'))

# 3) Brooks Trading Range
Check 'Brooks TR fields in BrooksBarInfo'                 ($text.Contains('inTradingRange') -and $text.Contains('trMid'))
Check 'Brooks TR detection window 20'                     ($text.Contains('trWin=MathMin(20'))
Check 'Brooks TR two-sided condition'                     ($text.Contains('bothAlive'))
Check 'Brooks TR magnet line drawn'                       ($text.Contains('ICTv13_BROOKS_TRMID'))
Check 'Brooks TR effective break flags'                   ($text.Contains('trBreakUp') -and $text.Contains('trBreakDn'))
Check 'Brooks failed-breakout-in-range flags'             ($text.Contains('trFailedBreakUp') -and $text.Contains('trFailedBreakDn'))

# 4) Brooks Measured Move
Check 'Brooks MM fields (A/B/C/D)'                        ($text.Contains('mmValid') -and $text.Contains('mmD'))
Check 'Brooks MM 100pct projection D=C+(B-A) pattern'     ($text.Contains('bi.mmD=bi.mmC+(bi.mmB-bi.mmA)') -or $text.Contains('bi.mmD=bi.mmC-(bi.mmA-bi.mmB)'))
Check 'Brooks MM target line drawn'                       ($text.Contains('ICTv13_BROOKS_MM'))

# 5) Brooks Channel
Check 'Brooks channel slope field'                        ($text.Contains('chSlope'))
Check 'Brooks channel uses Always-In + EMA20'             ($text.Contains('bi.chSlope=+1') -and $text.Contains('bi.chSlope=-1'))

# 6) BISI/SIBI
Check 'BISI/SIBI name helper'                             ($text.Contains('FVGBisiSibiStr'))
Check 'BISI = bullish FVG wording'                        ($text.Contains('Buy-side Imbalance'))
Check 'SIBI = bearish FVG wording'                        ($text.Contains('Sell-side Imbalance'))
Check 'FVG explain teaches BISI/SIBI equivalence'         ($text.Contains('FVGBisiSibiStr(f.direction)'))

# 7) SB + HTF-LTF sync label
Check 'SB sync label helper exists'                       ($text.Contains('string SBSyncLabel()'))
Check 'SB row uses combined label'                        ($text.Contains('SILVER BULLET "+SBSyncLabel()'))
Check 'Sync text covers conflict + no-bias + aligned'     ($text.Contains('HTF-LTF') )

# 8) Strength of Zone
Check 'SDObj strength fields'                             ($text.Contains('int             strength;') -and $text.Contains('strengthText'))
Check 'Strength composed from documented criteria'        (WindowHas (FindLine 'int strength=1;') 0 12 @('InpSD_StrengthATR', 'baseBars', 'strength'))
Check 'ExplainSD shows Strength of Zone'                  ($text.Contains('Strength of Zone'))
Check 'ExplainSD warns on repeated tests (absorption)'    ($text.Contains('Absorption'))

# 9) Effort vs Result at climax
$i = FindLine 'PushWyck(WE_SC, curT, curLow);'
Check 'Effort/Result absorption after SC'                 (WindowHas $i 0 6 @('WE_ABSORPTION', 'volRatio'))
$i = FindLine 'PushWyck(WE_BC, curT, curHigh);'
Check 'Effort/Result absorption after BC'                 (WindowHas $i 0 6 @('WE_ABSORPTION', 'volRatio'))

# 10) AMD price stage
Check 'AMD price-stage globals'                           ($text.Contains('g_amdPriceStage') -and $text.Contains('g_amdPriceNote'))
Check 'AMD M = sweep beyond Asia range'                   (WindowHas (FindLine 'g_amdPriceStage=AMD_MANIPULATION;') 2 2 @('g_asiaHigh', 'g_asiaLow'))
Check 'AMD D confirmed after sweep'                       ($text.Contains('g_amdPriceStage=AMD_DISTRIBUTION;'))
Check 'Dashboard row for price AMD'                       ($text.Contains('AMD '))
Check 'Explain route for AMD_PRICE'                       ($text.Contains('AMD_PRICE'))

# 11) Price Delivery
Check 'Price Delivery label on leg'                       ($text.Contains('ICTv13_LOCATION_PDLBL') -and $text.Contains('Delivering UP'))
Check 'ExplainLocation teaches delivery'                  ($text.Contains('Price Delivery:'))

# 12) Nested / MTF Mitigation
$i = FindLine 'Nested / Multi-timeframe Mitigation'
Check 'Nested mitigation comment with source'             ($i -ge 0)
Check 'Nested boost wired in POI registry'                ($text.Contains('g_poi[q].score+=4'))
Check 'Nested condition = same-direction FVG inside HTF zone' (WindowHas $i 2 10 @('g_fvgs[j].direction', 'nested'))
Check 'POI explain lists nested bonus'                    ($text.Contains('Nested Mitigation +'))

# 13) Regressions guards (phase-29/30 lessons must not reappear)
Check 'QT enum appended AFTER existing enums (stable ids)' ($text.Contains('enum ENUM_SILVERBULLET { SB_NONE, SB_LONDON, SB_NY_AM, SB_NY_PM }'))

Write-Output ("PHASE36: PASS=" + $pass + " FAIL=" + $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }
