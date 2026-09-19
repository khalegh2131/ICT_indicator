# Validate-Phase34.ps1
# Locks the phase-33/34 sourced audit: every event/member that has an enum, an explain
# text or an input must actually be PRODUCED by the engine. The failure this guards
# against is the one found on 2026-09-19: 8 Wyckoff events had enum + Chinese-wall
# explain text but were never pushed, so phases A/D/E were unreachable.
#
# NOTE: ASCII-only by design (PowerShell 5.1 misreads non-BOM UTF-8 sources).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root '01_CANONICAL_CANDIDATES\ICT_Assistant_Canonical.mq5'
if (-not (Test-Path -LiteralPath $src)) { throw "Source not found: $src" }
$code = Get-Content -Raw -Encoding UTF8 $src

$script:pass = 0
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
    else     { $script:fail++; Write-Host ("FAIL  {0}  {1}" -f $name, $detail) }
}

Write-Host '--- A) Wyckoff: every declared event must be produced ---'
foreach ($ev in @('WE_SC','WE_BC','WE_AR','WE_ST','WE_SPRING','WE_UPTHRUST','WE_SOS','WE_SOW','WE_LPS','WE_LPSY','WE_TEST','WE_ABSORPTION','WE_PS','WE_PSY')) {
    $n = ([regex]::Matches($code, [regex]::Escape("PushWyck($ev"))).Count
    Check ("wyckoff-" + $ev) ($n -ge 1) ("PushWyck call sites = " + $n)
}

Write-Host ''
Write-Host '--- B) Wyckoff: the phase ladder is a state machine, not window geometry ---'
Check 'range-state-struct'    ($code -match 'struct WyckRangeState')                 'live structure state (PS/AR/ST/shakeout/SOS/LPS)'
Check 'reset-on-new-cycle'    ($code -match 'void WyckResetRange\(string why\)')     'range is reset, so a finished range cannot live forever'
Check 'phase-a-needs-AR'      ($code -match 'if\(!g_wyckRange\.hasAR\)')             'Phase A while AR is missing'
Check 'phase-a-needs-ST'      ($code -match 'else if\(!g_wyckRange\.hasST\)')         'Phase A ends with ST (source: "With the Test this phase ends")'
Check 'phase-c-needs-shakeout' ($code -match 'if\(g_wyckRange\.hasShakeout\)')       'Phase C only after a shakeout'
Check 'phase-e-needs-beyond'  ($code -match 'g_wyckRange\.barsBeyond>=InpWyckoffPhaseE_Bars') 'Phase E only when price STAYS outside the structure'
Check 'spring-requires-range' ($code -match 'if\(g_wyckRange\.hasST\)')              'Spring/UTAD only inside a confirmed range (was: any wick under a 60-bar low)'
Check 'climax-volume-optional' ($code -match 'input bool\s+InpWyckoffClimaxRequireVolume\s+=\s+false;') 'source: a climax may arrive without climactic volume (Selling Exhaustion)'
Check 'volume-ratio-reported' ($code -match 'climaxVolRatio')                        'volume ratio is evidence, not a hidden gate'
Check 'no-per-bar-iVolume-loop' (-not ($code -match 'void UpdateWyckoff[\s\S]{0,3000}?iVolume\(')) 'one CopyTickVolume per closed bar'

Write-Host ''
Write-Host '--- C) Al Brooks: H1/H2 counted, not inverted; EMA20 is alive ---'
Check 'ema-handle-created'   ($code -match 'g_brooksEmaHandle = iMA\(')              'InpBrooks_EMA20_Period was a dead input'
Check 'ema-handle-released'  ($code -match 'IndicatorRelease\(g_brooksEmaHandle\)')  'handle released in OnDeinit'
Check 'always-in-is-state'   ($code -match 'bi\.alwaysIn=ai;')                      'Always-In is a state (EMA side + slope), not "3 same-colour bars"'
Check 'always-in-short'      ($code -match 'bool\s+alwaysInShort;')                 'the bearish state used to be recomputed at the display site'
Check 'h1-h2-bar-count'      ($code -match 'if\(h\[i\]>h\[i\+1\]\) hAtt\+\+;')       'H1 = first bar whose high exceeds the prior bar high (nexusfi / Brooks course)'
Check 'l1-l2-bar-count'      ($code -match 'if\(l\[i\]<l\[i\+1\]\) lAtt\+\+;')       'L1/L2 mirror existed nowhere before'
Check 'signal-bar-context'   ($code -match 'bi\.bullSignal=\(bullBody && closesNearHigh') 'signal bar needs opposite-leg context + close near extreme'
Check 'follow-through-vs-signal' ($code -match 'bi\.followThrough=\(bi\.isTrendBar && bi\.isEntryBar\);') 'measured against the signal bar, not any prior bar'
Check 'no-reverse-h2-hack'   (-not ($code -match 'bool pull1=\(l\[shift\+1\]<l\[shift\+2\]\);')) 'the inverted "two lower lows = H2" rule is gone'

Write-Host ''
Write-Host '--- D) Supply/Demand: role is one source of truth and flips stay alive ---'
Check 'kind-from-entry-leg'  ($code -match 'ENUM_SD_KIND SDKindFor\(bool preUp, bool exitUp\)') 'RBR/RBD/DBD/DBR need the approach leg (was: continuation and reversal indistinguishable)'
Check 'single-role-function' ($code -match 'bool SDIsSupplyKind\(ENUM_SD_KIND k\)')   'RBD/DBD = supply, RBR/DBR = demand in exactly one place'
Check 'no-inverted-role'     (-not ($code -match 'kind==SDK_DBR\)\s*;?\s*//?\s*supply')) 'DBR is demand, not supply'
Check 'live-role-field'      ($code -match 'bool\s+roleSupply;')                     'display/lifecycle read the LIVE role'
Check 'flip-keeps-tracking'  ($code -match 'g_sd\[i\]\.roleSupply=!roleSupply;')     'a flipped zone is tracked in its new role (was: abandoned)'
Check 'broken-state-used'    ($code -match 'if\(breaksNow\) g_sd\[i\]\.state=SDS_BROKEN;') 'SDS_BROKEN was referenced but never assigned'
Check 'base-range-is-input'  ($code -match 'input double InpSD_BaseMaxRangeATR\s+=') 'the 1.5-ATR base cap was hard-coded'

Write-Host ''
Write-Host '--- E) Auction Market Theory: IB / TPO / day types / open types / nodes ---'
Check 'ib-input'      ($code -match 'input int\s+InpProfileIB_Minutes\s+=\s+60;')    'Initial Balance = first hour of the session'
Check 'ib-computed'   ($code -match 'd\.ibHi=MathMax\(d\.ibHi,g_winCacheH\[i\]\);')  'IB high/low actually assigned (ibHigh/ibLow were dead struct fields)'
Check 'tpo-profile'   ($code -match 'tpoAt\[rr\]\+=1;')                              'TPO = one count per bar per price row (time, not volume)'
Check 'tpo-va-cqg'    ($code -match 'g_profileDaily\.tpoVah=')                       'TPO value area uses the same two-row CQG rule'
Check 'day-type'      ($code -match 'uint AMTDayType\(const AMTDay &d, double atr\)') 'trend / normal variation / normal / neutral / non-trend'
Check 'day-type-neutral' ($code -match 'if\(extUp && extDn && d\.close<=d\.ibHi && d\.close>=d\.ibLo\) return 4;') 'neutral day: both IB sides exceeded, close back inside'
Check 'open-type'     ($code -match 'uint AMTOpenType\(const AMTDay &cur, const AMTDay &prev\)') 'drive / test-drive / reject / auction'
Check 'hvn-lvn'       ($code -match 'g_profileDaily\.hvn\[g_profileDaily\.hvnCount\+\+\]') 'HVN/LVN nodes detected on row volume'
Check 'naked-poc'     ($code -match 'bool touched;')                                 'Naked/Virgin POC history with touch test'
Check 'balance-note'  ($code -match 'BALANCE|IMBALANCE')                             'acceptance vs rejection of value'
Check 'cache-has-open-close' ($code -match 'double\s+g_winCacheO\[\];')              'day type needs open/close of the day, not only H/L'

Write-Host ''
Write-Host '--- F) RTM: real registry instead of a note string ---'
Check 'rtm-enum'      ($code -match 'enum ENUM_RTM_EVENT')                           'compression/expansion/trap/momentum/engulf/rejection'
Check 'rtm-registry'  ($code -match 'RTMObj\s+g_rtm\[\];')                           'events are stored with ids'
Check 'rtm-trap'      ($code -match 'PushRTM\(RTM_TRAP')                             'trap entry has an id and is clickable'
Check 'rtm-momentum'  ($code -match 'PushRTM\(RTM_MOMENTUM')                         'momentum candle'
Check 'rtm-engulf'    ($code -match 'PushRTM\(RTM_ENGULF')                           'engulfing'
Check 'rtm-rejection' ($code -match 'PushRTM\(RTM_REJECTION')                        'rejection'
Check 'rtm-explain-per-object' ($code -match 'void ExplainRTMEvent\(const RTMObj &e\)') 'click on an event explains that event'
Check 'rtm-draw-gated' ($code -match 'if\(InpEnableRTM && InpDrawRTMObjects\)')       'chart stays clean by default'
Check 'rtm-capped'    ($code -match 'if\(n>=MathMax\(1,InpRTM_MaxEvents\)\)')         'registry is capped (no unbounded growth)'

Write-Host ''
Write-Host '--- G) teaching text: the wrong H1/H2 wording must be gone ---'
Check 'no-wrong-h1-text' (-not ($code -match 'H1/H2: .{0,80}H1')) 'the old "first pullback = H1" explanation is removed'
Check 'brooks-explain-uses-state' ($code -match 'ExplainBrooks\(\)[\s\S]{0,2500}?g_brooksInfo\.alwaysIn') 'the panel reads the same single source as the dashboard'
Check 'wyckoff-explain-structure' ($code -match 'void ExplainWyckoff\(const WyckoffObj &w\)') 'per-event Wyckoff explanation still present'

Write-Host ''
Write-Host ("RESULT: PASS={0} FAIL={1}" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
