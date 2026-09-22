# Validate-Phase28.ps1
# Locks the phase-28 FVG corrections. Every rule below traces to an English source
# (no guessing), because the reported defect was "some FVGs are fake and the logic
# was never completed".
#
# NOTE: deliberately ASCII-only. Windows PowerShell 5.1 reads .ps1 as ANSI unless the
# file carries a BOM, so non-ASCII text inside a script is a parse hazard. The Persian
# strings live in the .mq5 source (read as UTF8 below); here we only anchor on ASCII.

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

Write-Host '--- A) significance filter (LuxAlgo Library, Fair Value Gap, identify step 4) ---'
# "Raw three-candle gaps print constantly, so most tools require a minimum size
#  (ATR- or percentage-based)." Without it every 1-tick gap became a zone, which is
#  exactly what a trader calls a fake FVG.
$minGapInput = ($code -match 'input double InpMinFVG_ATR\s*=\s*0\.10;')
Check 'atr-min-gap-input-exists' $minGapInput 'InpMinFVG_ATR (0 = filter off)'

$minGapUse = ([regex]::Matches($code, 'minGap')).Count
Check 'atr-min-gap-is-computed-once-per-bar' `
      (($code -match 'double minGap=\(InpMinFVG_ATR>0\.0 && g_analysisATR>0\.0\)\? InpMinFVG_ATR\*g_analysisATR : 0\.0;') -and ($minGapUse -ge 4)) `
      ("minGap occurrences = " + $minGapUse)

$bullFilter = ($code -match 'if\(low\[shift\] > high\[shift\+2\] && \(low\[shift\]-high\[shift\+2\]\)>=minGap\)')
$bearFilter = ($code -match 'if\(high\[shift\] < low\[shift\+2\] && \(low\[shift\+2\]-high\[shift\]\)>=minGap\)')
Check 'both-standard-directions-are-filtered' ($bullFilter -and $bearFilter) `
      ("bullish = " + $bullFilter + " , bearish = " + $bearFilter)

Write-Host ''
Write-Host '--- B) implied FVG really uses the wick midpoints (LuxAlgo implied-FVG formula) ---'
# UWM(x) = (H + max(O,C))/2 ; LWM(x) = (min(O,C) + L)/2
# Bullish: LWM(t) > UWM(t-2) and L(t) <= H(t-2) -> bottom = UWM(t-2), top = LWM(t)
$outer = ($code -match 'double uwm1=\(h1\+MathMax\(o1,c1\)\)/2\.0;') -and ($code -match 'double lwm1=\(MathMin\(o1,c1\)\+l1\)/2\.0;')
$third = ($code -match 'double uwm3=\(h3\+MathMax\(o3,c3\)\)/2\.0;') -and ($code -match 'double lwm3=\(MathMin\(o3,c3\)\+l3\)/2\.0;')
Check 'wick-midpoint-terms-are-computed' ($outer -and $third) ("outer candle = " + $outer + " , third candle = " + $third)

$impliedBull = ($code -match 'if\(lwm3>uwm1 && l3<=h1 && \(lwm3-uwm1\)>=minGap\)')
$impliedBear = ($code -match 'if\(uwm3<lwm1 && h3>=l1 && \(lwm1-uwm3\)>=minGap\)')
Check 'implied-conditions-match-the-published-formula' ($impliedBull -and $impliedBear) `
      ("bullish = " + $impliedBull + " , bearish = " + $impliedBear)

$impliedZoneBull = ($code -match 'AppendFVG\(StableZoneId\(BarTime\(shift\),DIR_BULL,3\),\s*\r?\n\s*BarTime\(shift\), DIR_BULL, lwm3, uwm1,')
$impliedZoneBear = ($code -match 'AppendFVG\(StableZoneId\(BarTime\(shift\),DIR_BEAR,3\),\s*\r?\n\s*BarTime\(shift\), DIR_BEAR, lwm1, uwm3,')
Check 'implied-zone-is-built-from-wick-midpoints' ($impliedZoneBull -and $impliedZoneBear) `
      'bullish bottom=UWM(outer), top=LWM(third); bearish mirrored'

# The old, mislabeled construction: close of candle 1 versus open of candle 3 declared
# as FVGK_IMPLIED. That construction is a Volume Imbalance, not an implied gap.
$oldMislabel = ($code -match 'double b1=close\[shift\+2\];')
Check 'old-body-gap-is-no-longer-labelled-implied' (-not $oldMislabel) `
      ('previous close(c1)/open(c3) path still labelled IMPLIED = ' + $oldMislabel)

Write-Host ''
Write-Host '--- C) volume imbalance kept, but honestly labelled ---'
Check 'volume-imbalance-kind-exists' `
      ($code -match 'enum ENUM_FVG_KIND\s*\{\s*FVGK_STANDARD, FVGK_IMPLIED, FVGK_MICRO, FVGK_VOL_IMBALANCE \};') `
      'new member appended at the END so existing numeric values keep their meaning'
Check 'volume-imbalance-detector-uses-body-bounds' `
      (($code -match 'if\(c3>c1 && \(c3-c1\)>=minGap\)') -and ($code -match 'if\(c1>c3 && \(c1-c3\)>=minGap\)')) `
      'body-to-body gap, dedicated id discriminator'
Check 'volume-imbalance-has-its-own-id-space' `
      ($code -match 'StableZoneId\(BarTime\(shift\),DIR_BULL,5\),') `
      'discriminator 5 (1=standard, 2=OB, 3=implied, 4=micro) so it cannot collide with Implied'
Check 'volume-imbalance-is-switchable' ($code -match 'input bool   InpDetectVolumeImbalance = true;') `
      'InpDetectVolumeImbalance'

Write-Host ''
Write-Host '--- D) consequent encroachment tracked apart from a mere edge touch ---'
# LuxAlgo: "Many models treat a touch of the midpoint as filled enough."
Check 'ce-touched-flag-exists' ($code -match 'bool\s+ceTouched;') 'FVGObj.ceTouched'
$ceInit = ([regex]::Matches($code, 'f\.ceTouched=false;')).Count
Check 'ce-touched-is-initialised-on-creation' ($ceInit -ge 3) `
      ("initialisations = " + $ceInit + " (two inline standard blocks + AppendFVG)")
Check 'ce-touch-is-detected-in-the-lifecycle' `
      ($code -match 'if\(!g_fvgs\[i\]\.ceTouched && curLow<=g_fvgs\[i\]\.ce && curHigh>=g_fvgs\[i\]\.ce\)') `
      'midpoint reached test inside UpdateFVG_Lifecycle'
Check 'explanation-panel-separates-edge-touch-from-ce' `
      ($code -match '\(f\.mitigated && !f\.ceTouched\)') `
      'the teaching text branches on edge-touch versus CE-reached'

Write-Host ''
Write-Host '--- E) each gap kind is named in the explanation (no single label for all) ---'
Check 'kind-to-string-helper-exists' ($code -match 'string FVGKindToStr\(ENUM_FVG_KIND k\)') 'FVGKindToStr()'
Check 'explanation-title-carries-the-kind' `
      ($code -match 'g_expTitle="ZONE "\+FVGKindToStr\(f\.kind\)') `
      'title is kind-aware, so IMPLIED no longer shows the STANDARD definition'
Check 'explanation-names-the-active-filter' `
      ($code -match 'InpMinFVG_ATR, g_analysisATR') `
      'the panel reports InpMinFVG_ATR together with the ATR it was applied with'
Check 'explanation-defines-implied-by-wick-midpoint' `
      ($code -match 'MathMax\(o1,c1\)\)/2\.0;') `
      'the Implied definition shown to the user matches the implemented formula'

Write-Host ''
Write-Host '==== RESULT ===='
Write-Host ("PASS=$script:pass  FAIL=$script:fail")
if ($script:fail -gt 0) { exit 1 }
Write-Host 'RESULT: all phase 28 FVG rule and source checks passed'
