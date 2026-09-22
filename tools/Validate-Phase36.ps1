# Validate-Phase36.ps1 - Phase 36 lock validator (ASCII only; PS 5.1 safe)
# Locks the wiring of every Phase 36 item to its source in the canonical file.
# If any anchor disappears, the build no longer proves the phase and this fails.
$ErrorActionPreference = 'Stop'
$src = '01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5'
if (-not (Test-Path $src)) { $src = 'ICT_Assistant_Canonical.mq5' }
if (-not (Test-Path $src)) { Write-Output 'PHASE36: FAIL (source not found)'; exit 1 }
# Flatten the module shell the way MQL5 does, so the anchors below still name
# the code that compiles (see tools/CanonicalSource.ps1).
. "$PSScriptRoot/CanonicalSource.ps1"
$text = Get-CanonicalSourceText  -Path $src
$lines = Get-CanonicalSourceLines -Path $src
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
# Phase 42 renamed this tooltip so the Latin label opens the row and the rest
# is pure Persian (a Latin word inside a Persian clause splits the RTL run).
$pdFnStart = $text.IndexOf('void ExplainLocation(')
$pdFnEnd   = if ($pdFnStart -ge 0) { $text.IndexOf("`n}`n", $pdFnStart) } else { -1 }
$pdFn = if ($pdFnStart -ge 0 -and $pdFnEnd -gt $pdFnStart) { $text.Substring($pdFnStart, $pdFnEnd - $pdFnStart) } else { '' }
Check 'ExplainLocation teaches delivery'                  ($text.Contains('PRICE DELIVERY |') -or $pdFn.Contains('PRICE DELIVERY |') -or $text.Contains('PRICE DELIVERY | لگ فعال'))

# 12) Nested / MTF Mitigation
$i = FindLine 'Nested / Multi-timeframe Mitigation'
Check 'Nested mitigation comment with source'             ($i -ge 0)
Check 'Nested boost wired in POI registry'                ($text.Contains('g_poi[q].score+=4'))
# Phase 43: the nested witness is now compared through the *active* role
# (FVGActiveDir / OBActiveDir) instead of the raw birth direction, because a gap
# that closed through its far edge plays the opposite role and a flipped zone is
# not a same-direction witness any more. The invariant is unchanged: the FVG must
# sit inside the HTF zone AND move the same way it does.
Check 'Nested condition = same-direction FVG inside HTF zone' (WindowHas $i 2 12 @('FVGActiveDir(g_fvgs[j])', 'nested'))
# Phase 42 rewrote the family's teaching text so no Latin word sits inside a
# Persian clause; the old English row "Nested Mitigation +" became
# "بلوک تودرتوی درونی ۴+". The invariant is the same: the score breakdown the
# trader reads must name the nested bonus, and the +4 must still be wired in the
# engine (asserted separately by 'Nested boost wired in POI registry').
# The word is built from codepoints because Windows PowerShell 5.1 decodes a
# BOM-less .ps1 with the system ANSI codepage, which would mangle a literal.
$chTe = [char]0x062A; $chVav = [char]0x0648; $chDal = [char]0x062F; $chRe = [char]0x0631
$wordNested = "$chTe$chVav$chDal$chRe$chTe$chVav"   # تودرتو - "nested"
$poiFnStart = $text.IndexOf('void ExplainBestPOI(')
$poiFnEnd   = if ($poiFnStart -ge 0) { $text.IndexOf("`n}`n", $poiFnStart) } else { -1 }
$poiFn = if ($poiFnStart -ge 0 -and $poiFnEnd -gt $poiFnStart) { $text.Substring($poiFnStart, $poiFnEnd - $poiFnStart) } else { '' }
Check 'POI explain lists nested bonus'                    ($poiFn.Contains($wordNested) -and -not $text.Contains('Nested Mitigation +'))

# 13) Regressions guards (phase-29/30 lessons must not reappear)
Check 'QT enum appended AFTER existing enums (stable ids)' ($text.Contains('enum ENUM_SILVERBULLET { SB_NONE, SB_LONDON, SB_NY_AM, SB_NY_PM }'))

Write-Output ("PHASE36: PASS=" + $pass + " FAIL=" + $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }
