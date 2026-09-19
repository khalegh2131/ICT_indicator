# =====================================================================
# Validate-PerfPhase24.ps1  --  Phase 24 offline verifier (indicator speed)
#
# WHY
# ---
# The real measured number from the terminal journal was:
#   ICT PHASE13 | rebuild 600 bars in 19531 ms
# i.e. ~32 ms of work for every closed bar of the initial history rebuild.
# On top of that, MQL5 documents that every indicator attached to one symbol
# runs in ONE shared thread, so that cost is felt by the whole chart.
#
# The Phase 24 rules, all traceable to the official documentation:
#   R1  Timeseries/indicator data must not be copied on every OnCalculate
#       call. MQL5 "Timeseries and Indicators Access": "if timeseries and
#       indicator values need to be copied often, for example at each call of
#       OnCalculate() in indicators, one should better use ... arrays, because
#       operations of memory allocation for dynamic arrays require additional
#       time." -> copy only when a new closed bar exists.
#   R2  The closed-bar analysis path must not touch slow timeseries
#       accessors (iTime/iVolume/iClose...) in loops: read the cached array
#       instead.
#   R3  iVolume() must not be called in a loop; CopyTickVolume copies the
#       whole window once.
#   R4  A per-tick diagnostics function must not build strings every tick
#       (allocation in the hot path) before it knows something changed.
#   R5  The cost of every rebuild stage must be measurable
#       (GetMicrosecondCount probe) instead of guessed.
#
# This checker proves the source wiring of R1..R5; only a chart reload can
# prove the resulting milliseconds.
# =====================================================================

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src  = Join-Path $root '01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5'
$code = Get-Content -Raw -Encoding UTF8 $src

$pass = 0
$fail = 0
function Check($name, $ok, $detail) {
   if ($ok) { $script:pass++; Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
   else     { $script:fail++; Write-Host ("FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red }
}

# body of a top-level function: from "RET NAME(" to the next "\n}"
function BodyOf([string]$code, [string]$name, [string]$ret = 'void') {
   $sig = $ret + ' ' + $name + '('
   $i = $code.IndexOf($sig)
   if ($i -lt 0) { return '' }
   $j = $code.IndexOf("`n}", $i)
   if ($j -lt 0) { return '' }
   return $code.Substring($i, $j - $i)
}
function CountOf([string]$text, [string]$pattern) {
   return ([regex]::Matches($text, $pattern)).Count
}

# ---------------------------------------------------------------------
# R1 -- copies are gated behind "a new closed bar exists"
# ---------------------------------------------------------------------
$oncalc = BodyOf $code 'OnCalculate' 'int'
Check 'oncalculate-body-found' ($oncalc.Length -gt 500) ("length = {0}" -f $oncalc.Length)

$guardIdx  = $oncalc.IndexOf('if(!isNewBar && !firstRebuild)')
$copyIdx   = $oncalc.IndexOf('CopyOpen(_Symbol,PERIOD_CURRENT,0,need,o)')
Check 'series-copies-are-gated' ($guardIdx -ge 0 -and $copyIdx -gt $guardIdx) `
      ("guard at {0}, first CopyOpen at {1}" -f $guardIdx, $copyIdx)

$guardBlock = ''
if ($guardIdx -ge 0 -and $copyIdx -gt $guardIdx) { $guardBlock = $oncalc.Substring($guardIdx, $copyIdx - $guardIdx) }
Check 'flat-ticks-return-early' ($guardBlock -match 'return rates_total;') `
      'the no-new-bar path returns without copying or analysing'

Check 'copies-happen-once' (([regex]::Matches($oncalc, 'CopyOpen\(')).Count -eq 1) `
      'a single copy site per series inside OnCalculate'

Check 'copy-failure-retries-next-tick' (([regex]::Matches($oncalc, 'lastProcessedBarTime=0; return 0;')).Count -ge 4) `
      'each failed copy clears the bar stamp so the next tick retries'

# ---------------------------------------------------------------------
# R2/R3 -- closed-bar analysis path uses cached time, no iVolume loop
# ---------------------------------------------------------------------
$analyze = BodyOf $code 'AnalyzeClosedBar'
Check 'analyze-body-found' ($analyze.Length -gt 500) ("length = {0}" -f $analyze.Length)
$slow = CountOf $analyze 'iTime\(|iClose\(|iOpen\(|iHigh\(|iLow\(|iVolume\(|iTickVolume\('
Check 'analyze-path-has-no-timeseries-accessors' ($slow -eq 0) `
      ("slow timeseries calls inside AnalyzeClosedBar = {0}" -f $slow)
Check 'analyze-path-uses-time-cache' (([regex]::Matches($analyze, 'BarTime\(')).Count -ge 6) `
      ("BarTime() reads in AnalyzeClosedBar = {0}" -f ([regex]::Matches($analyze, 'BarTime\(')).Count)

$totalIVolume = CountOf $code 'iVolume\('
Check 'no-ivolume-loops' ($totalIVolume -eq 0) ("iVolume( occurrences in the whole file = {0}" -f $totalIVolume)

$profile = BodyOf $code 'UpdateProfile'
Check 'profile-uses-one-volume-copy' ($profile -match 'CopyTickVolume\(' -and $profile -notmatch 'iVolume\(') `
      'UpdateProfile copies the volume window once'

$rebuilIdx = $code.IndexOf('for(int shift=maxScan; shift>=1; shift--)')
$rebuildLoop = ''
if ($rebuilIdx -ge 0) { $rebuildLoop = $code.Substring($rebuilIdx, 1200) }
Check 'rebuild-loop-has-no-itme' ($rebuildLoop.Length -gt 0 -and $rebuildLoop -notmatch 'iTime\(') `
      'the rebuild loop reads BarTime(shift) instead of calling iTime() three times per bar'

# ---------------------------------------------------------------------
# R4 -- per-tick diagnostics build no strings before the change gate
# ---------------------------------------------------------------------
$p14 = BodyOf $code 'PersistPhase14Diagnostics'
$hashIdx = $p14.IndexOf('long sig=0;')
$strIdx  = $p14.IndexOf('IntegerToString(')
Check 'per-tick-diagnostics-gate-is-numeric' ($hashIdx -ge 0 -and ($strIdx -lt 0 -or $strIdx -gt $hashIdx)) `
      ("integer hash gate at {0}, first IntegerToString at {1}" -f $hashIdx, $strIdx)

# ---------------------------------------------------------------------
# R5 -- measurable stages
# ---------------------------------------------------------------------
Check 'microsecond-probe-exists' ($code -match '#define PROBE_T0' -and $code -match 'GetMicrosecondCount\(\)') `
      'GetMicrosecondCount based probe (documented MQL5 measurement method)'
Check 'probe-is-off-by-default' ($code -match 'bool\s+g_probeOn=false;') `
      'the probe costs nothing unless a rebuild is being measured'
Check 'probe-is-enabled-only-for-the-rebuild' (([regex]::Matches($code, 'g_probeOn=InpLogPerfOnRebuild;')).Count -eq 1 -and
                                              ([regex]::Matches($code, 'g_probeOn=false;')).Count -ge 1) `
      'enabled once around the rebuild loop and cleared right after'
Check 'profile-line-is-printed' ($code -match 'ICT PHASE24 \| profile') `
      'the rebuild journal prints the per-stage breakdown'

# ---------------------------------------------------------------------
# R6 -- witness CSVs keep their rows but stop open/close-cycling per bar
# ---------------------------------------------------------------------
$witness = @('PersistPhase15Diagnostics', 'PersistPhase12Diagnostics', 'PersistReversalDiagnostics', 'PersistReplayDiagnostics')
$witnessOk = 0
$witnessDetail = @()
foreach ($fn in $witness) {
   $b = BodyOf $code $fn
   # the normal path must go through the shared handle; a single FileClose is
   # allowed for the header self-heal, which has to close before FileDelete
   $closes = ([regex]::Matches($b, 'FileClose\(')).Count
   $ok = ($b.Length -gt 200) -and ($b -match 'DiagOpen\(') -and ($b -notmatch 'FileOpen\(') -and ($closes -le 1)
   if ($ok) { $witnessOk++; $witnessDetail += ($fn + '=ok(' + $closes + ')') } else { $witnessDetail += ($fn + '=no(' + $closes + ')') }
}
Check 'witness-files-reuse-one-handle' ($witnessOk -eq $witness.Count) ($witnessDetail -join ' ')
Check 'held-handles-are-released' (([regex]::Matches($code, 'DiagHoldRelease\(\);')).Count -ge 2) `
      'released after the rebuild loop and in OnDeinit'

# every measured stage must actually be wrapped (sampled: the two heaviest names)
$ctxStages = ([regex]::Matches($code, 'PROBE_END\("2[a-p]\.')).Count
Check 'context-stages-are-instrumented' ($ctxStages -ge 14) `
      ("instrumented context sub-stages = {0}" -f $ctxStages)

Write-Host ''
Write-Host '==== RESULT ===='
Write-Host ("PASS={0}  FAIL={1}" -f $pass, $fail)
if ($fail -gt 0) { Write-Host 'RESULT: FAILED'; exit 1 }
Write-Host 'RESULT: all phase 24 rule and source checks passed'
exit 0
