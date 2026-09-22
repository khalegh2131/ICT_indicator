# Validate-Phase29.ps1
# Locks the phase-29 structure/OB corrections. Every rule traces to an English source
# (no guessing): the reported question was "FVG is real and correct now - what about
# BOS and OB?".
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

Write-Host '--- A) CHoCH flips the owner direction (LuxAlgo - Market Structure) ---'
# "A break of structure (BOS) ... This structure only can occur after a CHoCH."
# So a CHoCH must move the owner direction; otherwise the next break can never be a
# BOS and the bias (H4 included) locks to the first break of the loaded history.
$bullFlip = ($code -match 'e\.type = EVT_MSS;\s*//[^\r\n]*\r?\n\s*trendDir = DIR_BULL;')
$bearFlip = ($code -match 'e\.type = EVT_MSS;\s*//[^\r\n]*\r?\n\s*trendDir = DIR_BEAR;')
Check 'bull-choch-always-flips-owner' $bullFlip 'trendDir = DIR_BULL is unconditional after the MSS promotion'
Check 'bear-choch-always-flips-owner' $bearFlip 'trendDir = DIR_BEAR is unconditional after the MSS promotion'

$oldGuard = ($code -match 'else if\(trendDir==DIR_NONE\)')
Check 'old-conditional-flip-is-gone' (-not $oldGuard) ("old 'else if(trendDir==DIR_NONE)' still present = " + $oldGuard)

$bullCount = ([regex]::Matches($code, 'trendDir = DIR_BULL;')).Count
$bearCount = ([regex]::Matches($code, 'trendDir = DIR_BEAR;')).Count
Check 'owner-flip-happens-exactly-once-per-side' (($bullCount -eq 1) -and ($bearCount -eq 1)) `
      ("bull = " + $bullCount + " , bear = " + $bearCount)

# The HTF call passes disp/liq = -1 by design, so the unconditional flip is what makes
# the H4 bias able to reverse at all.
$htfCall = ($code -match 'EvaluateStructureBreak\(hClose, 0, true, g_swingsHTF, g_htfBias, -1, -1, htfRates\[0\]\.time\);')
Check 'htf-call-still-passes-no-disp-liq' $htfCall 'H4 evaluation stays displacement-free, so it depends on the unconditional flip'

Write-Host ''
Write-Host '--- B) pivot confirmation only on CLOSED right-side bars (no-repaint input) ---'
# IsConfirmedPivotHigh reads shift-1 .. shift-right. With pivotShift = shift + right - 1
# the newest right bar is index shift-1, which in live mode (shift = 1) is the still
# forming bar 0 -> the pivot could be registered and then invalidated inside the bar.
$pivotFixed = ($code -match 'int pivotShift = shift \+ InpSwingRight;')
$pivotOld   = ($code -match 'int pivotShift = shift \+ InpSwingRight - 1;')
Check 'ltf-pivot-uses-only-closed-right-bars' $pivotFixed 'pivotShift = shift + InpSwingRight'
Check 'old-off-by-one-pivot-is-gone' (-not $pivotOld) ("old 'shift + InpSwingRight - 1' still present = " + $pivotOld)

$htfPivot = ($code -match 'int pivotShift = InpSwingRight;')
Check 'htf-pivot-variant-unchanged' $htfPivot 'H4 uses the last closed bar as index 0 (was already correct)'

$guard = ($code -match 'if\(shift-right < 0 \|\| shift\+left >= total\) return false;')
Check 'pivot-guard-untouched' $guard 'bounds guard inside IsConfirmedPivotHigh/low'

Write-Host ''
Write-Host '--- C) order-block registry has no duplicate zones (same class of bug fixed for FVG) ---'
# Two consecutive displacement candles in one strong move both reach the same opposite
# candle, so both produced the same StableZoneId: two stacked boxes, a double OB count
# and wasted InpMaxOB slots.
$dedupAnchor = ($code -match 'if\(g_obs\[i\]\.id!=o\.id\) continue;')
Check 'ob-dedup-loop-exists' $dedupAnchor 'existing zone with the same StableZoneId is merged, not re-appended'

$dedupBeforePush = $false
$iDedup = $code.IndexOf('if(g_obs[i].id!=o.id) continue;')
$iPush  = $code.IndexOf('int n=ArraySize(g_obs); ArrayResize(g_obs,n+1); g_obs[n]=o;')
if (($iDedup -ge 0) -and ($iPush -gt $iDedup)) { $dedupBeforePush = $true }
Check 'ob-dedup-runs-before-append' $dedupBeforePush ("dedup@" + $iDedup + " push@" + $iPush)

$weakens = ($code -match 'if\(g_obs\[i\]\.structureEventId==-1 && o\.structureEventId!=-1\)') -and `
           ($code -match 'if\(g_obs\[i\]\.liquidityEventId==-1 && o\.liquidityEventId!=-1\)') -and `
           ($code -match 'if\(g_obs\[i\]\.state==OB_INVALID && o\.state==OB_VALID\) g_obs\[i\]\.state=OB_VALID;')
Check 'ob-dedup-only-strengthens-metadata' $weakens 'Core / sweep / valid can only be added, never removed'

$dedupCounter = (($code -match 'long\s+g_obsDeduped\s*=\s*0;') -and ($code -match 'g_obsDeduped\+\+;') -and ($code -match '"ICT PHASE29 \| OB dedup merged %d'))
Check 'ob-dedup-is-observable' $dedupCounter 'counter + journal line (evidence, not a claim)'

$fvgDedup = ($code -match 'if\(g_fvgs\[i\]\.id==id\) return;\s*//')
Check 'fvg-dedup-still-intact' $fvgDedup 'AppendFVG regression anchor'

Write-Host ''
Write-Host '--- D) OB origin candle + invalidation rules (LuxAlgo - Bullish/bearish Order Block) ---'
# "Step back to the last opposite candle" - the search depth is a rule of the concept,
# not a hardcoded literal: a slow rally has several same-coloured candles before the
# displacement and the old fixed 6 found no block there.
$lookbackInput = ($code -match 'input int\s+InpOB_LookbackBars\s*=\s*6;')
Check 'ob-lookback-is-an-input' $lookbackInput 'InpOB_LookbackBars'

$lookbackUsed = ($code -match 'int lookback\s+= \(InpOB_LookbackBars>0\)\? InpOB_LookbackBars : 1;') -and `
                ($code -match 'if\(backLimit>lookback\) backLimit=lookback;')
Check 'ob-lookback-is-applied' $lookbackUsed 'search depth comes from the input'

$hardcoded = ($code -match 'if\(backLimit>6\) backLimit=6;')
Check 'old-hardcoded-lookback-is-gone' (-not $hardcoded) ("old 'backLimit>6' still present = " + $hardcoded)

$lastOpposite = ($code -match 'bool opposite = dispDown \? \(close\[idx\] > open\[idx\]\) : \(close\[idx\] < open\[idx\]\);')
Check 'ob-is-the-last-opposite-candle' $lastOpposite 'colour of the origin candle opposes the displacement'

$decisiveClose = ($code -match 'if\(g_obs\[i\]\.direction==DIR_BULL && curClose < g_obs\[i\]\.bottom\) violated = true;') -and `
                 ($code -match 'if\(g_obs\[i\]\.direction==DIR_BEAR && curClose > g_obs\[i\]\.top\)    violated = true;')
Check 'ob-invalidation-is-a-decisive-close' $decisiveClose 'close through the whole zone, not a wick'

$breakerChain = ($code -match 'g_obs\[i\]\.state==OB_BROKEN && g_obs\[i\]\.polarityFlipped &&\s*\r?\n\s*g_obs\[i\]\.liquidityEventId!=-1 &&\s*\r?\n\s*g_obs\[i\]\.brokenTime>0 && curBarTime>g_obs\[i\]\.brokenTime')
Check 'breaker-needs-sweep-and-separate-retest-bar' $breakerChain 'failed OB + stop hunt + retest from the other side, on a later bar'

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ("RESULT: PASS=" + $script:pass + " FAIL=" + $script:fail)
    exit 0
} else {
    Write-Host ("RESULT: PASS=" + $script:pass + " FAIL=" + $script:fail)
    exit 1
}
