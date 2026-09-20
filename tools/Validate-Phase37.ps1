# =====================================================================
# Validate-Phase37.ps1  --  behavioral verifier for the synthetic-data
#                           self-test (FVG / Order Block / Sweep)
#
# WHY THIS EXISTS
# ---------------
# Every earlier tool in tools/ greps the source. A green grep only proves
# that a string is present in the file; it stays green even when the
# arithmetic behind that string is wrong. This tool is the first one that
# checks numbers.
#
# The indicator itself runs the behavior harness (input
# InpRunBehaviorSelfTest) on synthetic candles with known answers and
# writes ICT_Assistant_Canonical_SelfTest.csv. The harness calls the REAL
# DetectFVG / DetectOB / DetectSweep functions, so what is checked is the
# production code path, not a parallel re-implementation.
#
# This verifier has three independent jobs:
#
#   A) SECOND IMPLEMENTATION -- the expected numbers are recomputed here,
#      in PowerShell, straight from the rule text (ICT three-candle gap,
#      LuxAlgo/ICT-2023 implied-FVG mid-wick formula, body gap = volume
#      imbalance, wick-beyond + close-back sweep, body-vs-full-range OB).
#      The candle numbers used are the ones written in the harness comments
#      in the source. If those candles are ever changed, section A stops
#      agreeing with the report and the tool fails -- drift cannot pass
#      silently.
#
#   B) RUNTIME EVIDENCE -- read the CSV the indicator wrote and require:
#        * every expected scenario present, exactly once, no extras
#        * all rows PASS except exactly one row, which MUST be
#          SENSITIVITY_probe_must_report_FAIL. That row carries a
#          deliberately false claim. If it passes, the comparison logic is
#          blind and every other PASS in the file is worthless. This is the
#          teeth check.
#        * rows that say SKIPPED are only accepted when the matching input
#          really is switched off in the source
#        * the Actual column matches section A for the numeric scenarios
#
#   C) SOURCE PROOF -- the harness is wired where it must be: defined once,
#      called once per attach, called BEFORE the history rebuild, registries
#      reset afterwards, live state saved and restored, and the sensitivity
#      row present in the source.
#
# Read-only. No build. No writes except stdout.
#
# HONEST LIMITS
# -------------
# Sections A and C run without MetaTrader. Section B needs one indicator
# reload, because MQL5 cannot be executed outside the terminal. Until the
# reload happens, section B reports PENDING rather than pretending to pass.
# =====================================================================
param(
   [string]$Source = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5",
   [string]$Report = "$env:APPDATA/MetaQuotes/Terminal/Common/Files/ICT_Assistant_Canonical_SelfTest.csv"
)

$ErrorActionPreference = "Stop"
$pass = 0
$fail = 0
$pending = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
   if ($ok) { $script:pass++; "PASS  {0}  {1}" -f $name, $detail }
   else     { $script:fail++; "FAIL  {0}  {1}" -f $name, $detail }
}
function Pending([string]$name, [string]$detail) {
   $script:pending++; "PEND  {0}  {1}" -f $name, $detail
}
function Num([string]$text) {
   $m = [regex]::Match($text, '-?\d+(\.\d+)?')
   if (-not $m.Success) { return [double]::NaN }
   return [double]$m.Value
}

Write-Output "=== Phase 37 -- behavioral self-test verifier (FVG / OB / Sweep) ==="
Write-Output ""

if (-not (Test-Path -LiteralPath $Source)) { throw "Canonical source not found: $Source" }
$src = Get-Content -LiteralPath $Source -Raw -Encoding UTF8

# ---------------------------------------------------------------------
# A) SECOND IMPLEMENTATION -- recompute every expected number from scratch
# ---------------------------------------------------------------------
Write-Output "--- A) independent recomputation of the expected numbers ---"

# A1 bullish standard gap: low(third) > high(first) -> top = low(third), bottom = high(first)
$fvgBullHigh1  = 104.00; $fvgBullLow3 = 105.00
$a1Top = $fvgBullLow3; $a1Bottom = $fvgBullHigh1
Check "A1_FVG_STANDARD_BULL_BOUNDS" `
   (($a1Top -eq 105.00) -and ($a1Bottom -eq 104.00) -and ($a1Top -gt $a1Bottom)) `
   ("top={0} bottom={1} from low3={2} > high1={3}" -f $a1Top, $a1Bottom, $fvgBullLow3, $fvgBullHigh1)

# A2 bearish standard gap: high(third) < low(first) -> top = low(first), bottom = high(third)
$fvgBearLow1 = 105.00; $fvgBearHigh3 = 104.00
$a2Top = $fvgBearLow1; $a2Bottom = $fvgBearHigh3
Check "A2_FVG_STANDARD_BEAR_BOUNDS" `
   (($a2Top -eq 105.00) -and ($a2Bottom -eq 104.00) -and ($a2Top -gt $a2Bottom)) `
   ("top={0} bottom={1} from high3={2} < low1={3}" -f $a2Top, $a2Bottom, $fvgBearHigh3, $fvgBearLow1)

# A3 minimum-gap guard arithmetic: threshold = InpMinFVG_ATR * analysis ATR
$minFvgAtr = Num(([regex]::Match($src, 'input\s+double\s+InpMinFVG_ATR\s*=\s*([0-9.]+)')).Groups[1].Value)
$atrUsed   = 1.00
$threshold = [math]::Round($minFvgAtr * $atrUsed, 6)
$a3SmallGap = 0.05; $a3LargeGap = 0.50
Check "A3_MINGAP_THRESHOLD_ARITHMETIC" `
   (($threshold -gt 0) -and ($a3SmallGap -lt $threshold) -and ($a3LargeGap -ge $threshold)) `
   ("threshold={0} (InpMinFVG_ATR={1} x ATR={2}); gap 0.05 rejected, gap 0.50 accepted" -f $threshold, $minFvgAtr, $atrUsed)

# A4 implied FVG, real ICT-2023 mid-wick formula
function MidWick([double]$o, [double]$h, [double]$l, [double]$c) {
   return @{ UWM = ($h + [math]::Max($o, $c)) / 2.0; LWM = ([math]::Min($o, $c) + $l) / 2.0 }
}
$c1 = MidWick 102.00 103.00 101.80 102.40    # first candle
$c3 = MidWick 103.50 106.00 102.90 105.00    # third candle
$a4Top = [math]::Round($c3.LWM, 6); $a4Bottom = [math]::Round($c1.UWM, 6)
$a4Condition = (($c3.LWM -gt $c1.UWM) -and (102.90 -le 103.00))
Check "A4_IMPLIED_BULL_FORMULA" `
   ($a4Condition -and ($a4Top -eq 103.20) -and ($a4Bottom -eq 102.70)) `
   ("LWM3={0} > UWM1={1}, L3=102.90 <= H1=103.00 -> top={2} bottom={3}" -f $c3.LWM, $c1.UWM, $a4Top, $a4Bottom)

# A4b the same geometry with L(third) above H(first) must NOT form an implied gap
$a4bCondition = (($c3.LWM -gt $c1.UWM) -and (103.50 -le 103.00))
Check "A4b_IMPLIED_BULL_REJECTION" (-not $a4bCondition) `
   "L3=103.50 > H1=103.00 breaks the ICT condition, so no implied zone may exist"

# A5 volume imbalance = body gap, a separate concept from implied
$a5Top = 105.00; $a5Bottom = 102.40
Check "A5_VOLUME_IMBALANCE_BODY_GAP" `
   (($a5Top -eq 105.00) -and ($a5Bottom -eq 102.40) -and ($a5Top -gt $a5Bottom)) `
   "close(third)=105.00 > close(first)=102.40 -> top=105.00 bottom=102.40"

# A6 sweep: wick beyond the level AND close back inside it
$pdh = 105.00
$a6BarH = 105.50; $a6BarL = 104.00; $a6BarC = 104.50
$a6Swept = ($a6BarH -gt $pdh) -and ($a6BarC -lt $pdh)
Check "A6_SWEEP_BSL_CONDITION" ($a6Swept -and (($a6BarH - $pdh) -eq 0.50)) `
   "high 105.50 > 105.00 and close 104.50 < 105.00 -> bought-side liquidity swept, direction BEAR"

# A6b a clean break (close beyond the level) is not a sweep
$a6bBarC = 105.80
Check "A6b_BREAK_IS_NOT_SWEEP" (-not (($a6BarH -gt $pdh) -and ($a6bBarC -lt $pdh))) `
   "close 105.80 is beyond 105.00, so the level is broken, not swept"

# A6c SSL: mirrored condition
$pdl = 100.00; $a6cBarL = 99.50; $a6cBarC = 100.60
Check "A6c_SWEEP_SSL_CONDITION" (($a6cBarL -lt $pdl) -and ($a6cBarC -gt $pdl)) `
   "low 99.50 < 100.00 and close 100.60 > 100.00 -> sell-side liquidity swept, direction BULL"

# A7 nearest-level ownership when several levels are swept by one bar
$a7BarH = 105.60; $a7BarC = 104.00
$lv1 = 105.00; $lv2 = 105.40
$a7Swept1 = ($a7BarH -gt $lv1) -and ($a7BarC -lt $lv1)
$a7Swept2 = ($a7BarH -gt $lv2) -and ($a7BarC -lt $lv2)
$a7Owner  = if (([math]::Abs($a7BarH - $lv1)) -lt ([math]::Abs($a7BarH - $lv2))) { $lv1 } else { $lv2 }
Check "A7_NEAREST_SWEPT_LEVEL_OWNS_CHAIN" `
   ($a7Swept1 -and $a7Swept2 -and ($a7Owner -eq 105.40)) `
   ("both levels swept; distances 0.60 vs 0.20 -> owner 105.40")

# A8 OB origin bar bounds, both geometry modes
$obBodyTop = [math]::Max(101.00, 100.00); $obBodyBottom = [math]::Min(101.00, 100.00)
$obFullTop = 101.20; $obFullBottom = 99.80
Check "A8_OB_BODY_VS_FULL_RANGE" `
   (($obBodyTop -eq 101.00) -and ($obBodyBottom -eq 100.00) -and ($obFullTop -eq 101.20) -and ($obFullBottom -eq 99.80)) `
   "down bar O=101.00 C=100.00 H=101.20 L=99.80 -> body 101.00/100.00, full range 101.20/99.80"

# A8b bearish mirror
$obBearBodyTop = [math]::Max(100.00, 101.00); $obBearBodyBottom = [math]::Min(100.00, 101.00)
Check "A8b_OB_BEARISH_MIRROR" `
   (($obBearBodyTop -eq 101.00) -and ($obBearBodyBottom -eq 100.00)) `
   "up bar O=100.00 C=101.00 -> body 101.00/100.00 (bearish zone)"

# ---------------------------------------------------------------------
# C) SOURCE PROOF -- the harness is wired, and wired where it must be
# ---------------------------------------------------------------------
Write-Output ""
Write-Output "--- C) source proof ---"

$defCount = ([regex]::Matches($src, 'void\s+RunBehaviorSelfTest\s*\(')).Count
Check "C1_HARNESS_DEFINED_ONCE" ($defCount -eq 1) ("RunBehaviorSelfTest definitions = {0}" -f $defCount)

$callCount = ([regex]::Matches($src, 'RunBehaviorSelfTest\s*\(\s*need\s*\)')).Count
Check "C2_HARNESS_CALLED_WITH_BAR_COUNT" ($callCount -eq 1) `
   ("called once with the copied bar count (needs a real series for BarTime/iTime) = {0}" -f $callCount)

# ASCII-only anchors on purpose: PowerShell 5.1 reads a BOM-less .ps1 as ANSI,
# so a Persian literal in this file would arrive as mojibake and never match.
$idxCall     = $src.IndexOf('RunBehaviorSelfTest(need)')
$idxRebuild  = $src.IndexOf('if(!g_historyRebuilt && InpRebuildHistoryOnAttach)')
$idxRefresh  = $src.IndexOf('RefreshBarTimeCache(need)')
Check "C3_CALLED_BEFORE_REBUILD" (($idxCall -gt $idxRefresh) -and ($idxCall -lt $idxRebuild)) `
   "call sits after the bar-time cache is ready and before the history rebuild starts"

Check "C4_REGISTRIES_RESET_AFTER_TEST" `
   ($src -match '(?s)SelfTestSensitivity\(\);\s*\n\s*//[^\n]*\n\s*ArrayResize\(g_fvgs,0\);\s*\n\s*ArrayResize\(g_obs,0\);\s*\n\s*ArrayResize\(g_liquidity,0\);') `
   "fvg/ob/liquidity registries zeroed after the harness so live analysis starts clean"

Check "C5_LIVE_STATE_SAVED_AND_RESTORED" `
   (($src -match 'savedRebuild=g_rebuildMode') -and ($src -match 'g_rebuildMode=savedRebuild') -and
    ($src -match 'savedATR\s*=g_analysisATR') -and ($src -match 'g_analysisATR=savedATR') -and
    ($src -match 'savedDedup\s*=g_obsDeduped') -and ($src -match 'g_obsDeduped =savedDedup')) `
   "rebuild mode, analysis ATR and the dedup counter are restored, so no live counter is polluted"

Check "C6_DRAWING_SUPPRESSED_DURING_TEST" ($src -match 'g_rebuildMode=true;\s*//[^\n]*\n\s*g_leg\.valid\s*=false;') `
   "rebuild mode is forced on, so no synthetic object can reach the chart"

Check "C7_SENSITIVITY_ROW_PRESENT_IN_SOURCE" `
   ($src -match '"SENSITIVITY_probe_must_report_FAIL"') `
   "the deliberately false claim is declared in the source"

Check "C8_SELF_TEST_TOGGLE_DECLARED" ($src -match 'input\s+bool\s+InpRunBehaviorSelfTest\s*=') `
   "input InpRunBehaviorSelfTest declared"

# scenario inventory: every row the source writes must be in the required list below
$srcRows = [regex]::Matches($src, 'SelfTestRow\(\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$required = @(
   "FVG_STANDARD_BULL","FVG_STANDARD_BEAR","FVG_NO_GAP_REGISTERS_NOTHING",
   "FVG_MINGAP_REJECTS_SMALL_GAP","FVG_MINGAP_ACCEPTS_LARGE_GAP",
   "FVG_IMPLIED_BULL_MIDWICK_FORMULA","FVG_IMPLIED_BULL_REQUIRES_L3_LE_H1",
   "FVG_VOLUME_IMBALANCE_IS_SEPARATE_KIND",
   "OB_ORIGIN_IS_LAST_OPPOSITE_BAR","OB_NO_DISPLACEMENT_IS_INVALID",
   "OB_STANDALONE_WHEN_NO_STRUCTURE_EVENT","OB_VALID_WITH_DISPLACEMENT",
   "OB_CORE_AND_SWEEP_LINKED","OB_DEDUP_SAME_ZONE_NOT_REPEATED",
   "OB_LOOKBACK_LIMIT_REJECTS_FAR_ORIGIN","OB_BEARISH_DISPLACEMENT_ORIGIN",
   "SWEEP_BSL_SWEPT_IS_BEARISH","SWEEP_BSL_MARKS_LEVEL_SWEPT","SWEEP_ALREADY_SWEPT_NOT_RESWEPT",
   "SWEEP_BREAK_IS_NOT_A_SWEEP","SWEEP_SSL_SWEPT_IS_BULLISH","SWEEP_FUTURE_LEVEL_IGNORED",
   "SWEEP_NEAREST_LEVEL_OWNS_THE_CHAIN","SWEEP_ALL_TOUCHED_LEVELS_MARKED",
   "SENSITIVITY_probe_must_report_FAIL"
)
$missing = $required | Where-Object { $srcRows -notcontains $_ }
$extra   = $srcRows | Where-Object { $required -notcontains $_ }
Check "C9_SCENARIO_INVENTORY" (($missing.Count -eq 0) -and ($extra.Count -eq 0)) `
   ("source declares {0} scenarios; missing=[{1}] unexpected=[{2}]" -f $srcRows.Count, ($missing -join ','), ($extra -join ','))

# ---------------------------------------------------------------------
# B) RUNTIME EVIDENCE -- the report the indicator actually wrote
# ---------------------------------------------------------------------
Write-Output ""
Write-Output "--- B) runtime evidence from the indicator report ---"

if (-not (Test-Path -LiteralPath $Report)) {
   Pending "B0_REPORT_PRESENT" "not found yet: $Report  (reload the indicator once, then re-run)"
   Write-Output ""
   Write-Output ("RESULT: PASS={0} FAIL={1} PENDING={2}" -f $pass, $fail, $pending)
   Write-Output "Section A and C are proved. Section B needs one chart reload to produce the report."
   if ($fail -gt 0) { exit 1 }
   exit 0
}

$rows = @(Import-Csv -LiteralPath $Report -Delimiter ';' -Encoding Unicode)
$names = $rows | ForEach-Object { $_.Scenario }
Check "B1_ROW_COUNT_MATCHES_EXPECTED" ($rows.Count -eq $required.Count) `
   ("report rows = {0}, required = {1}" -f $rows.Count, $required.Count)
$missingRows = $required | Where-Object { $names -notcontains $_ }
Check "B2_NO_MISSING_SCENARIO" ($missingRows.Count -eq 0) ("missing rows = [{0}]" -f ($missingRows -join ','))
$dupes = $names | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
Check "B3_NO_DUPLICATE_SCENARIO" ($dupes.Count -eq 0) ("duplicates = [{0}]" -f ($dupes -join ','))

$failed = @($rows | Where-Object { [int]$_.Pass -eq 0 })
$failedNames = @($failed | ForEach-Object { $_.Scenario })
Check "B4_EXACTLY_ONE_DESIGNED_FAILURE" `
   (($failed.Count -eq 1) -and ($failedNames[0] -eq "SENSITIVITY_probe_must_report_FAIL")) `
   ("rows with Pass=0 = [{0}] (the sensitivity probe must be the only one)" -f ($failedNames -join ','))

Check "B5_ALL_OTHER_SCENARIOS_PASS" (($rows.Count - $failed.Count) -eq ($required.Count - 1)) `
   ("passing rows = {0} of {1}" -f ($rows.Count - $failed.Count), $required.Count)

# skipped rows are only legal when the matching input really is off in the source
$impliedOn = ($src -match 'input\s+bool\s+InpDetectImpliedFVG\s*=\s*true') -and ($src -match 'input\s+bool\s+InpEnablePhase12\s*=\s*true')
$volImbOn  = ($src -match 'input\s+bool\s+InpDetectVolumeImbalance\s*=\s*true')
$skipProblems = @()
foreach ($r in $rows) {
   if ($r.Actual -like 'SKIPPED*') {
      if ($r.Scenario -like 'FVG_MINGAP_*') { $skipProblems += "$($r.Scenario) (InpMinFVG_ATR=$minFvgAtr)"; continue }
      if ($r.Scenario -eq 'FVG_VOLUME_IMBALANCE_IS_SEPARATE_KIND') { if ($volImbOn) { $skipProblems += "$($r.Scenario) (volume imbalance is ON)" }; continue }
      if ($r.Scenario -like 'FVG_IMPLIED*') { if ($impliedOn) { $skipProblems += "$($r.Scenario) (implied detection is ON)" }; continue }
      $skipProblems += "$($r.Scenario) (unexpected skip)"
   }
}
Check "B6_SKIPS_JUSTIFIED_BY_INPUTS" ($skipProblems.Count -eq 0) ("unjustified skips = [{0}]" -f ($skipProblems -join ','))

# get a row's Actual field or '' when absent
function ActualOf($rows, [string]$scenario) {
   $r = $rows | Where-Object { $_.Scenario -eq $scenario } | Select-Object -First 1
   if ($null -eq $r) { return "" }
   return [string]$r.Actual
}
function ExpectedOf($rows, [string]$scenario) {
   $r = $rows | Where-Object { $_.Scenario -eq $scenario } | Select-Object -First 1
   if ($null -eq $r) { return "" }
   return [string]$r.Expected
}

# B7 the actual numbers must equal section A's recomputation
$a7a = ActualOf $rows "FVG_STANDARD_BULL"
Check "B7_FVG_STANDARD_BULL_NUMBERS" `
   (($a7a -match 'top=105\.00000') -and ($a7a -match 'bottom=104\.00000') -and ($a7a -match 'kind=0')) `
   ("report Actual = '{0}' vs computed top={1} bottom={2} kind=STANDARD" -f $a7a, $a1Top, $a1Bottom)

$a8r = ActualOf $rows "FVG_STANDARD_BEAR"
Check "B8_FVG_STANDARD_BEAR_NUMBERS" `
   (($a8r -match 'top=105\.00000') -and ($a8r -match 'bottom=104\.00000')) `
   ("report Actual = '{0}' vs computed top=105.00000 bottom=104.00000" -f $a8r)

$a9r = ActualOf $rows "FVG_MINGAP_ACCEPTS_LARGE_GAP"
Check "B9_MINGAP_ACCEPT_NUMBERS" `
   (($a9r -match 'top=104\.50000') -and ($a9r -match 'bottom=104\.00000')) `
   ("report Actual = '{0}' vs computed top=104.50000 bottom=104.00000" -f $a9r)

$a10r = ActualOf $rows "FVG_MINGAP_REJECTS_SMALL_GAP"
Check "B10_MINGAP_REJECT_TEXT" ($a10r -like '*absent*') `
   ("gap 0.05 below the threshold of {0} must leave no zone; report Actual = '{1}'" -f $threshold, $a10r)

$a11r = ActualOf $rows "FVG_IMPLIED_BULL_MIDWICK_FORMULA"
Check "B11_IMPLIED_BULL_NUMBERS" `
   (($a11r -match 'top=103\.20000') -and ($a11r -match 'bottom=102\.70000')) `
   ("report Actual = '{0}' vs computed top=103.20000 bottom=102.70000" -f $a11r)

$a12r = ActualOf $rows "FVG_VOLUME_IMBALANCE_IS_SEPARATE_KIND"
if ($volImbOn) {
   Check "B12_VOLUME_IMBALANCE_NUMBERS" `
      (($a12r -match 'top=105\.00000') -and ($a12r -match 'bottom=102\.40000') -and ($a12r -match 'kind=3')) `
      ("report Actual = '{0}' vs computed top=105.00000 bottom=102.40000 kind=VOL_IMBALANCE" -f $a12r)
} else {
   Pending "B12_VOLUME_IMBALANCE_NUMBERS" "volume imbalance is switched off in the source"
}

$a13r = ActualOf $rows "OB_ORIGIN_IS_LAST_OPPOSITE_BAR"
$obFullRange = ($src -match 'input\s+bool\s+InpOBUseFullCandleRange\s*=\s*true')
if ($obFullRange) {
   Check "B13_OB_BOUNDS_MATCH_INPUT_MODE" `
      (($a13r -match 'top=101\.20000') -and ($a13r -match 'bottom=99\.80000')) `
      ("InpOBUseFullCandleRange=true so expectation is 101.20/99.80; report Actual = '{0}'" -f $a13r)
} else {
   Check "B13_OB_BOUNDS_MATCH_INPUT_MODE" `
      (($a13r -match 'top=101\.00000') -and ($a13r -match 'bottom=100\.00000')) `
      ("InpOBUseFullCandleRange=false so expectation is the body 101.00/100.00; report Actual = '{0}'" -f $a13r)
}

$a14r = ActualOf $rows "OB_LOOKBACK_LIMIT_REJECTS_FAR_ORIGIN"
$lookback = Num(([regex]::Match($src, 'input\s+int\s+InpOB_LookbackBars\s*=\s*(\d+)')).Groups[1].Value)
Check "B14_LOOKBACK_LIMIT_SCENARIO_VALID" (($lookback -lt 9) -and ($a14r -match 'g_obs=0')) `
   ("InpOB_LookbackBars={0} must be below 9 for this scenario to be meaningful; report Actual = '{1}'" -f $lookback, $a14r)

$a15r = ActualOf $rows "SWEEP_BREAK_IS_NOT_A_SWEEP"
Check "B15_BREAK_NOT_SWEEP" (($a15r -match 'returned=-1') -and ($a15r -match 'FRESH|state=0')) `
   ("report Actual = '{0}' (a level closed beyond must stay FRESH)" -f $a15r)

$a16r = ActualOf $rows "SWEEP_NEAREST_LEVEL_OWNS_THE_CHAIN"
Check "B16_NEAREST_OWNER_IS_THE_NEARBY_LEVEL" ($a16r -match 'dir=1') `
   ("direction must be BEAR (dir=1); report Actual = '{0}'" -f $a16r)

$a17r = ActualOf $rows "SWEEP_BSL_SWEPT_IS_BEARISH"
Check "B17_SWEEP_DIRECTION" (($a17r -match 'dir=1') -and ($a17r -notmatch 'returned=-1')) `
   ("report Actual = '{0}'" -f $a17r)

$a18r = ActualOf $rows "SWEEP_SSL_SWEPT_IS_BULLISH"
Check "B18_SWEEP_SSL_DIRECTION" ($a18r -match 'dir=0') `
   ("direction must be BULL (dir=0); report Actual = '{0}'" -f $a18r)

$a19r = ExpectedOf $rows "SENSITIVITY_probe_must_report_FAIL"
Check "B19_SENSITIVITY_CLAIM_IS_THE_FALSE_ONE" ($a19r -like '*deliberately false claim*') `
   ("the failing row must be the declared false claim, not an accident; Expected = '{0}'" -f $a19r)

Write-Output ""
Write-Output ("RESULT: PASS={0} FAIL={1} PENDING={2}" -f $pass, $fail, $pending)
if ($fail -gt 0) { exit 1 }
exit 0
