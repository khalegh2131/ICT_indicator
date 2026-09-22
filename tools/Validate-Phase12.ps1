# =====================================================================
# Validate-Phase12.ps1  --  Phase 12 offline verifier
#
# A) RULE CHECK: every new rule is re-implemented here from the rule text
#    only, then compared against fixture expectations. Nothing is imported
#    from the indicator.
# B) NON-FUNCTION TEST: deliberately wrong fixtures must be rejected.
# C) SOURCE PROOF: read the canonical source and prove the invariants that
#    the acceptance criteria depend on, plus a guard for the bidi-digit
#    percent lookalike that once broke every new format string.
#
# Read-only. No build. Output on stdout only.
# =====================================================================
param(
   [string]$Source   = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5",
   [string]$Fixtures = "D:/ICT_indicator/05_TESTS_AND_VALIDATION"
)

$ErrorActionPreference = "Stop"
$pass = 0
$fail = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
   if ($ok) { $script:pass++; "PASS  {0}  {1}" -f $name, $detail }
   else     { $script:fail++; "FAIL  {0}  {1}" -f $name, $detail }
}

function ReadRows([string]$path) {
   if (-not (Test-Path $path)) { throw "fixture not found: $path" }
   $out = @()
   $first = $true
   foreach ($ln in (Get-Content -LiteralPath $path -Encoding UTF8)) {
      $t = $ln.Trim()
      if ($t.Length -eq 0) { continue }
      if ($first) { $first = $false; if ($t -match '^[A-Za-z]') { continue } }
      $out += ,($t -split ',')
   }
   return $out
}
function B([string]$s) { return ($s.Trim().ToUpper() -eq "TRUE") }

# ---------------------------------------------------------------- rules
function EvalImpliedGap([double]$c1close, [double]$c3open) {
   if ($c3open -eq $c1close) { return @{ dir="NONE"; top=0.0; bottom=0.0 } }
   $dir = if ($c3open -gt $c1close) { "BULLISH" } else { "BEARISH" }
   return @{ dir=$dir; top=[Math]::Max($c1close,$c3open); bottom=[Math]::Min($c1close,$c3open) }
}

function EvalObClass([int]$structId, [int]$liqId, [bool]$violated, [bool]$flipped, [bool]$retest) {
   # validity needs a displacement, which the fixture guarantees by construction
   $state = "OB_VALID"
   if ($violated) { $state = "OB_BROKEN" }
   if ($violated -and $flipped -and $retest) {
      if ($liqId -ne -1) { $state = "OB_BREAKER" } else { $state = "OB_MITIGATION" }
   }
   $kind = if ($structId -eq -1) { "STANDALONE" } else { "CORE" }
   if ($state -eq "OB_MITIGATION") { $kind = "MITIGATION" }
   return @{ state=$state; kind=$kind }
}

function EvalRange([double]$height, [double]$maxHeight, [int]$hiT, [int]$loT, [int]$minT) {
   if ($height -le 0.0) { return $false }
   if ($height -gt $maxHeight) { return $false }
   if ($hiT -lt $minT) { return $false }
   if ($loT -lt $minT) { return $false }
   return $true
}

function EvalModel([bool]$mss,[bool]$sweep,[bool]$disp,[bool]$fvg,[bool]$ob,
                   [bool]$zone,[bool]$leg,[int]$pref) {
   $m2022  = ($mss -and $sweep -and $disp -and $fvg)
   $mBfo   = ($disp -and $fvg -and $ob)
   $mSweep = ($sweep -and $zone)
   $mOte   = ($leg -and $zone)
   if ($pref -gt 0) {
      switch ($pref) {
         1 { if ($m2022)  { return "ICT2022" } }
         2 { if ($mBfo)   { return "BOS_FVG_OB" } }
         3 { if ($mSweep) { return "SWEEP_ENTRY" } }
         4 { if ($mOte)   { return "OTE_ONLY" } }
      }
      return "NONE"
   }
   if ($m2022)  { return "ICT2022" }
   if ($mBfo)   { return "BOS_FVG_OB" }
   if ($mSweep) { return "SWEEP_ENTRY" }
   if ($mOte)   { return "OTE_ONLY" }
   return "NONE"
}

function EvalQuality([bool[]]$flags, [int]$min) {
   $q = 0
   foreach ($f in $flags) { if ($f) { $q++ } }
   return @{ score=$q; ready=($q -ge $min) }
}

function EvalPoiScore([string]$kind, [bool]$aligned, [bool]$extreme, [int]$ageBars, [int]$decayBars) {
   $bonus = 0
   switch ($kind.Trim().ToUpper()) {
      "BREAKER"    { $bonus = 12 }
      "FVG"        { $bonus = 8 }
      "OB"         { $bonus = 6 }
      "TRENDLINE"  { $bonus = 5 }
      "RANGE"      { $bonus = 5 }
      "MITIGATION" { $bonus = 4 }
      "REJECTION"  { $bonus = 3 }
   }
   $decay = 0
   if ($decayBars -gt 0) { $decay = [Math]::Floor($ageBars / $decayBars) }
   if ($decay -gt 10) { $decay = 10 }
   $s = 20 + $bonus
   if ($aligned) { $s += 10 }
   if ($extreme) { $s += 6 }
   return ($s - $decay)
}

function EvalIpda([int]$days, [int]$copied) { return ($copied -ge $days) }

# ============================================================== A) rules
"=== A) RULE CHECKS ==="
foreach ($r in (ReadRows (Join-Path $Fixtures "phase12_fvg_implied.fixture.csv"))) {
   $g = EvalImpliedGap ([double]$r[0]) ([double]$r[1])
   $ok = ($g.dir -eq $r[2].Trim().ToUpper()) -and
         ([Math]::Abs($g.top - [double]$r[3]) -lt 0.0001) -and
         ([Math]::Abs($g.bottom - [double]$r[4]) -lt 0.0001)
   Check ("impliedgap[" + $r[0] + "->" + $r[1] + "]") $ok ("dir=" + $g.dir + " top=" + $g.top + " bottom=" + $g.bottom)
}

foreach ($r in (ReadRows (Join-Path $Fixtures "phase12_ob_class.fixture.csv"))) {
   $o = EvalObClass ([int]$r[0]) ([int]$r[1]) (B $r[2]) (B $r[3]) (B $r[4])
   $ok = ($o.state -eq $r[5].Trim().ToUpper()) -and ($o.kind -eq $r[6].Trim().ToUpper())
   Check ("obclass[s" + $r[0] + "/l" + $r[1] + "/v" + $r[2] + "/r" + $r[4] + "]") $ok ("state=" + $o.state + " kind=" + $o.kind)
}

foreach ($r in (ReadRows (Join-Path $Fixtures "phase12_range.fixture.csv"))) {
   $got = EvalRange ([double]$r[0]) ([double]$r[1]) ([int]$r[2]) ([int]$r[3]) ([int]$r[4])
   Check ("range[h" + $r[0] + "/max" + $r[1] + "/t" + $r[2] + "," + $r[3] + "]") ($got -eq (B $r[5])) ("got=" + $got)
}

foreach ($r in (ReadRows (Join-Path $Fixtures "phase12_model.fixture.csv"))) {
   $got = EvalModel (B $r[0]) (B $r[1]) (B $r[2]) (B $r[3]) (B $r[4]) (B $r[5]) (B $r[6]) ([int]$r[7])
   Check ("model[pref" + $r[7] + "]") ($got -eq $r[8].Trim().ToUpper()) ("got=" + $got)
}

foreach ($r in (ReadRows (Join-Path $Fixtures "phase12_quality.fixture.csv"))) {
   $flags = @((B $r[0]),(B $r[1]),(B $r[2]),(B $r[3]),(B $r[4]),(B $r[5]),(B $r[6]),(B $r[7]),(B $r[8]),(B $r[9]))
   $q = EvalQuality $flags ([int]$r[10])
   Check ("quality[min" + $r[10] + "]") ($q.ready -eq (B $r[11])) ("score=" + $q.score + " ready=" + $q.ready)
}

foreach ($r in (ReadRows (Join-Path $Fixtures "phase12_poi.fixture.csv"))) {
   $got = EvalPoiScore $r[0] (B $r[1]) (B $r[2]) ([int]$r[3]) ([int]$r[4])
   Check ("poi[" + $r[0] + "/age" + $r[3] + "]") ($got -eq [int]$r[5]) ("got=" + $got + " expected=" + $r[5])
}

foreach ($r in (ReadRows (Join-Path $Fixtures "phase12_ipda.fixture.csv"))) {
   $got = EvalIpda ([int]$r[0]) ([int]$r[1])
   Check ("ipda[" + $r[0] + "d/copied" + $r[1] + "]") ($got -eq (B $r[2])) ("got=" + $got)
}

# ==================================================== B) non-function test
"=== B) NON-FUNCTION TESTS (wrong fixtures must be rejected) ==="
$bad = @()
foreach ($r in (ReadRows (Join-Path $Fixtures "phase12_bad_obclass.fixture.csv"))) {
   $o = EvalObClass ([int]$r[0]) ([int]$r[1]) (B $r[2]) (B $r[3]) (B $r[4])
   if (($o.state -ne $r[5].Trim().ToUpper()) -or ($o.kind -ne $r[6].Trim().ToUpper())) { $bad += "ob" }
}
$badObTotal = (ReadRows (Join-Path $Fixtures "phase12_bad_obclass.fixture.csv")).Count
Check "selftest(obclass bad fixture)" ($bad.Count -eq $badObTotal) ("caught " + $bad.Count + " of " + $badObTotal)

$badM = 0
$rowsM = ReadRows (Join-Path $Fixtures "phase12_bad_model.fixture.csv")
foreach ($r in $rowsM) {
   $got = EvalModel (B $r[0]) (B $r[1]) (B $r[2]) (B $r[3]) (B $r[4]) (B $r[5]) (B $r[6]) ([int]$r[7])
   if ($got -ne $r[8].Trim().ToUpper()) { $badM++ }
}
Check "selftest(model bad fixture)" ($badM -eq $rowsM.Count) ("caught " + $badM + " of " + $rowsM.Count)

$badP = 0
$rowsP = ReadRows (Join-Path $Fixtures "phase12_bad_poi.fixture.csv")
foreach ($r in $rowsP) {
   $got = EvalPoiScore $r[0] (B $r[1]) (B $r[2]) ([int]$r[3]) ([int]$r[4])
   if ($got -ne [int]$r[5]) { $badP++ }
}
Check "selftest(poi bad fixture)" ($badP -eq $rowsP.Count) ("caught " + $badP + " of " + $rowsP.Count)

# ========================================================= C) source proof
"=== C) SOURCE PROOF ==="
if (-not (Test-Path $Source)) { throw "source not found: $Source" }
# The canonical indicator is now a shell plus one module per strategy family.
# Flatten it exactly the way the MQL5 preprocessor does, so these anchors are
# still checked against the code that actually compiles.
. "$PSScriptRoot/CanonicalSource.ps1"
$src   = Get-CanonicalSourceText  -Path $Source
$lines = Get-CanonicalSourceLines -Path $Source
$nl = ($lines -join "`n")

# C1 - a lookalike percent sign inside a format string silently breaks substitution.
#      This guard exists because it actually happened while writing phase 12.
$badFmt = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
   if ($lines[$i] -match 'StringFormat' -and $lines[$i].Contains([char]0x066A)) { $badFmt += ($i + 1) }
}
Check "format-specifiers-are-ascii" ($badFmt.Count -eq 0) ("lines with U+066A inside StringFormat: " + $badFmt.Count)

# C2 - Standalone order blocks must now be reachable: the call is outside the
#      structure-event branch and gated on a displacement.
$c2 = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
   if ($lines[$i] -match 'DetectOB\(o,h,l,c,') {
      $from = [Math]::Max(0, $i - 6)
      if ((($lines[$from..$i]) -join "`n") -match 'if\(dispId!=-1\)') { $c2 = $true }
   }
}
$c2b = ($nl -match 'o\.isStandalone = \(structureEventId==-1\);')
Check "standalone-is-reachable" ($c2 -and $c2b) ("gated on dispId=" + $c2 + " ; isStandalone from structureEventId=" + $c2b)

# C3 - Mitigation Block is an independent state, produced without a sweep.
$mitAssign = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
   if ($lines[$i] -match '=\s*OB_MITIGATION\s*;') { $mitAssign += ($i + 1) }
}
$mitNoSweep = $false
if ($mitAssign.Count -ge 1) {
   $from = [Math]::Max(0, $mitAssign[0] - 20)
   $mitNoSweep = ((($lines[$from..($mitAssign[0] - 1)]) -join "`n") -match 'liquidityEventId==-1')
}
Check "mitigation-block-independent" (($mitAssign.Count -eq 1) -and $mitNoSweep) ("assigned at line(s) " + ($mitAssign -join ",") + " ; requires no sweep=" + $mitNoSweep)

# C4 - new concepts each have a call site (detection actually runs)
$calls = @{
   "MarkExtremeOrderBlocks" = 'MarkExtremeOrderBlocks\([^v]'
   "BuildTrendlines"        = 'BuildTrendlines\('
   "UpdateRangeLiquidity"   = 'UpdateRangeLiquidity\('
   "UpdateIPDAReferenceLevels" = 'UpdateIPDAReferenceLevels\('
   "UpdateHtfInternalStructure" = 'UpdateHtfInternalStructure\('
   "UpdatePOIRegistry"      = 'UpdatePOIRegistry\('
   "UpdateTrendPhase"       = 'UpdateTrendPhase\('
   "DetectMicroFVG"         = 'DetectMicroFVG\('
}
foreach ($k in $calls.Keys) {
   $n = ([regex]::Matches($src, $calls[$k])).Count
   Check ("called:" + $k) ($n -ge 2) ("occurrences (definition + call site) = " + $n)
}

# C5 - enum members were APPENDED, never inserted: old values must keep their order
$liq = [regex]::Match($src, 'enum ENUM_LIQ_TYPE\s*\{([^}]*)\}').Groups[1].Value
$ob  = [regex]::Match($src, 'enum ENUM_OB_STATE\s*\{([^}]*)\}').Groups[1].Value
$liqOk = ($liq -match 'LIQ_PDH') -and ($liq.IndexOf('LIQ_PDH') -lt $liq.IndexOf('LIQ_SESSION_L')) -and
         ($liq.IndexOf('LIQ_SESSION_L') -lt $liq.IndexOf('LIQ_RANGE_H'))
$obOk  = ($ob.Trim().StartsWith('OB_VALID')) -and ($ob.IndexOf('OB_INVALID') -lt $ob.IndexOf('OB_MITIGATION'))
Check "enums-are-append-only" ($liqOk -and $obOk) ("LIQ order preserved=" + $liqOk + " ; OB order preserved=" + $obOk)

# C6 - internal structure must be computed on the owner timeframe, not the chart one
$iuStart = $src.IndexOf("void UpdateHtfInternalStructure(")
$iuEnd   = $src.IndexOf("void UpdateTrendPhase(", $iuStart)
$iuOk = ($iuStart -gt 0) -and ($iuEnd -gt $iuStart) -and
        ($src.Substring($iuStart, $iuEnd - $iuStart) -match 'CopyRatesAsOf\(_Symbol, InpHTF')
Check "internal-structure-on-owner-tf" $iuOk ("UpdateHtfInternalStructure reads InpHTF = " + $iuOk)

# C7 - the implied-gap helper really takes the timeframe (9 parameters, as documented)
$sig = [regex]::Match($src, 'void AppendFVG\(([^)]*)\)').Groups[1].Value
$sigCount = ($sig -split ',').Count
Check "appendfvg-signature" ($sigCount -eq 9) ("parameter count = " + $sigCount)

# C8 - micro gaps are derived only from chained displacements
$microOk = ($nl -match 'if\(DisplacementChained\(dispId, dDir\)\)\s*\r?\n\s*DetectMicroFVG')
Check "micro-only-from-chained-displacement" $microOk ("guard present = " + $microOk)

# C9 - a range-liquidity level is a level, not a dimensionless zone: the POI must
#      carry a band, otherwise top=bottom and the render gate (top>bottom) drops it
#      while FindBestPOI still returns it as "best opportunity".
$c9band = ($nl -match 'double rband=\(atrValue>0\.0\)\? atrValue\*0\.10') -and
          ($nl -match 'AddPOI\(g_liquidity\[i\]\.id, POIK_RANGE,[\s\S]{0,200}?price\+rband, g_liquidity\[i\]\.price-rband')
Check "range-poi-has-band" $c9band ("band applied to POIK_RANGE = " + $c9band)

# C10 - every diagnostic ledger either creates its header or repairs a headerless
#       leftover file. The reversal ledger was found with data rows and no header,
#       which made stale pre-build rows look like current evidence.
$c10phase = ($nl -match 'ICT_Assistant_Canonical_Phase12_Diag\.csv') -and
            ($nl -match '"POICount","BestPOIKind","BestPOIScore"') -and
            ($nl -match '"EntryModel","ModelReason","Quality","QualityMin","SetupStatus"')
$c10rev   = ($nl -match 'string firstKey=FileReadString\(handle\);') -and
            ($nl -match 'FileDelete\("ICT_Assistant_Canonical_Reversal_Diag_"\+ChartTfCode\(\)\+"\.csv",FILE_COMMON\);')
Check "diag-headers-self-heal" ($c10phase -and $c10rev) ("phase12 header=" + $c10phase + " ; reversal self-heal=" + $c10rev)

# C11 - the build/load stamp exists and is recorded both at attach and inside the
#       ledgers, so "which build wrote this row" is answerable without guesswork.
$c11stamp = ($nl -match 'PersistLoadStamp\(\);') -and
            ($nl -match 'g_buildStamp=TimeToString\(TimeLocal\(\)') -and
            (( [regex]::Matches($src, 'g_buildStamp\)').Count) -ge 1)
# Phase 47 appended one more column (ChartTF) after the stamp in the reversal
# ledger, so the stamp is no longer the last argument of FileWrite. The property
# under test is that a ledger row still carries the stamp, not that it ends there.
$c11rows  = ([regex]::Matches($src, ',\s*\r?\n\s*g_buildStamp[,)]').Count) -ge 1
Check "build-stamp-recorded" ($c11stamp -and $c11rows) ("stamp at attach=" + $c11stamp + " ; stamp inside ledger rows=" + $c11rows)

# C12 - the phase-12 ledger is written from BOTH pipeline branches (history rebuild
#       and live closed bar), otherwise the ledger would be empty after attach.
$c12 = ([regex]::Matches($src, 'PersistPhase12Diagnostics\(').Count) -ge 3
Check "phase12-ledger-called-twice" $c12 ("occurrences (definition + 2 call sites) = " + ([regex]::Matches($src, 'PersistPhase12Diagnostics\(').Count))

# C13 - rule check for the range-POI band: width must be exactly 2 x band
foreach ($r in (ReadRows (Join-Path $Fixtures "phase12_rangepoi.fixture.csv"))) {
   $atr = [double]$r[0]; $frac = [double]$r[1]; $want = [double]$r[2]
   $band = if ($atr -gt 0.0) { $atr * $frac } else { 0.0 }
   $width = [Math]::Max($atr + $band, $atr - $band) - [Math]::Min($atr + $band, $atr - $band)
   Check ("rangepoi[atr" + $atr + "]") ([Math]::Abs($width - $want) -lt 0.0001) ("width=" + $width + " expected=" + $want)
}

""
"==== RESULT ===="
"PASS=$pass  FAIL=$fail"
if ($fail -gt 0) { "RESULT: FAILED"; exit 1 } else { "RESULT: all phase 12 rule and source checks passed"; exit 0 }
