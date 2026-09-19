# =====================================================================
# Validate-ReversalGate.ps1  --  Phase 11 offline verifier
#
# Two independent jobs:
#   A) RULE CHECK  : re-derive the reversal decision from raw fixture rows
#                    (bias / protected level / closed HTF bar) and compare
#                    with the expected column. Nothing is imported from the
#                    indicator; this is a second implementation of the same
#                    rule, written from the rule text, not from the code.
#   B) SOURCE PROOF: read the canonical source and prove the invariants that
#                    acceptance criterion 3 of Phase 11 depends on.
#
# Read-only. No build. No writes except stdout.
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
   $lines = Get-Content -LiteralPath $path -Encoding UTF8
   $out = @()
   $first = $true
   foreach ($ln in $lines) {
      $t = $ln.Trim()
      if ($t.Length -eq 0) { continue }
      if ($first) { $first = $false; if ($t -match '^[A-Za-z]') { continue } }  # header
      $out += ,($t -split ',')
   }
   return $out
}

function ParseTs([string]$s) {
   return [datetime]::ParseExact($s.Trim(), "yyyy.MM.dd HH:mm", [Globalization.CultureInfo]::InvariantCulture)
}

# ---------------------------------------------------------------------
# The rule, restated independently of the indicator source
# ---------------------------------------------------------------------
function EvalReversal([string]$bias, [string]$levelSide, [double]$levelPrice,
                      [datetime]$levelTime, [datetime]$htfBarTime, [double]$htfClose) {
   # no owner bias -> nothing can be confirmed
   if ($bias.Trim().ToUpper() -eq "NONE") { return @{ ok=$false; dir="NONE"; why="no H4 owner bias" } }
   # the hostile guard is the level that a reversal must close through
   $guardIsHigh = ($bias.Trim().ToUpper() -eq "BEAR")
   $sideIsHigh  = ($levelSide.Trim().ToUpper() -eq "HIGH")
   # the guard must be the level on the side that opposes the bias
   if ($sideIsHigh -ne $guardIsHigh) { return @{ ok=$false; dir="NONE"; why="guard side does not oppose bias" } }
   # a level born on/after the evaluated bar cannot be broken by that bar
   if ($htfBarTime -le $levelTime) { return @{ ok=$false; dir="NONE"; why="level not older than evaluated bar" } }
   if ($guardIsHigh) {
      if ($htfClose -gt $levelPrice) { return @{ ok=$true; dir="BULLISH"; why="closed above protected HIGH" } }
   } else {
      if ($htfClose -lt $levelPrice) { return @{ ok=$true; dir="BEARISH"; why="closed below protected LOW" } }
   }
   return @{ ok=$false; dir="NONE"; why="closed bar did not pass the protected level" }
}

function EvalSmr([bool]$sweep, [bool]$disp, [bool]$zone, [bool]$ctx, [int]$minScore) {
   $score = 0
   if ($sweep) { $score++ }
   if ($disp)  { $score++ }
   if ($zone)  { $score++ }
   if ($ctx)   { $score++ }
   return @{ score=$score; smr = ($score -ge $minScore); max=4 }
}

# =====================================================================
"=== A) RULE CHECK: reversal gate"
# =====================================================================
$okRows = ReadRows (Join-Path $Fixtures "phase11_reversal_ok.fixture.csv")
foreach ($r in $okRows) {
   $bias = $r[0]; $side = $r[1]; $price = [double]$r[2]
   $lt = ParseTs $r[3]; $bt = ParseTs $r[4]; $close = [double]$r[5]
   $expOk = ($r[6].Trim().ToUpper() -eq "TRUE"); $expDir = $r[7].Trim().ToUpper()
   $res = EvalReversal $bias $side $price $lt $bt $close
   $gotDir = $res.dir
   Check ("reversal[" + $bias.Trim() + "/" + $side.Trim() + "/" + $close + "]") `
         (($res.ok -eq $expOk) -and ($gotDir -eq $expDir)) `
         ("expected ok=" + $expOk + " dir=" + $expDir + " -> got ok=" + $res.ok + " dir=" + $gotDir + " (" + $res.why + ")")
}

"=== A2) SMR score threshold"
$smrRows = ReadRows (Join-Path $Fixtures "phase11_smr_ok.fixture.csv")
foreach ($r in $smrRows) {
   $dir = $r[0].Trim().ToUpper()
   $sw = ($r[1].Trim().ToUpper() -eq "TRUE"); $dp = ($r[2].Trim().ToUpper() -eq "TRUE")
   $zn = ($r[3].Trim().ToUpper() -eq "TRUE"); $cx = ($r[4].Trim().ToUpper() -eq "TRUE")
   $min = [int]$r[5]; $exp = ($r[6].Trim().ToUpper() -eq "TRUE")
   $res = EvalSmr $sw $dp $zn $cx $min
   Check ("smr[" + $dir + "]/min" + $min) ($res.smr -eq $exp) `
         ("expected " + $exp + " -> got " + $res.smr + " (score " + $res.score + "/4)")
}

"=== A3) NON-FUNCTION TEST: a deliberately wrong fixture MUST fail"
$badRows = ReadRows (Join-Path $Fixtures "phase11_reversal_bad.fixture.csv")
$badCaught = 0
$badTotal = $badRows.Count
foreach ($r in $badRows) {
   $res = EvalReversal $r[0] $r[1] ([double]$r[2]) (ParseTs $r[3]) (ParseTs $r[4]) ([double]$r[5])
   $expOk = ($r[6].Trim().ToUpper() -eq "TRUE"); $expDir = $r[7].Trim().ToUpper()
   if (($res.ok -ne $expOk) -or ($res.dir -ne $expDir)) { $badCaught++ }
}
Check "self-test(bad fixture is rejected)" ($badCaught -eq $badTotal) `
      ("caught " + $badCaught + " of " + $badTotal + " wrong expectations")

# =====================================================================
"=== B) SOURCE PROOF: Phase 11 invariants"
# =====================================================================
if (-not (Test-Path $Source)) { throw "source not found: $Source" }
$src = Get-Content -LiteralPath $Source -Raw -Encoding UTF8
$lines = Get-Content -LiteralPath $Source -Encoding UTF8

# B1 -- acceptance criterion 3: nothing outside the structure engine writes the bias
$assign = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
   if ($lines[$i] -match 'g_htfBias\s*=(?!=)') { $assign += ($i + 1) }
}
Check "bias-single-writer" ($assign.Count -eq 1) `
      ("assignments to g_htfBias found at line(s): " + ($assign -join ", ") + " (only the declaration is allowed)")

# B2 -- the two protected ids are now READ, not only written
$readHigh = ([regex]::Matches($src, 'g_htfProtectedHighId')).Count
$readLow  = ([regex]::Matches($src, 'g_htfProtectedLowId')).Count
Check "protected-ids-are-read" (($readHigh -ge 3) -and ($readLow -ge 3)) `
      ("g_htfProtectedHighId x" + $readHigh + " , g_htfProtectedLowId x" + $readLow + " (write + read + snapshot)")

# B3 -- the confirmed-reversal state has exactly ONE producer and it is gated
$revAssign = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
   # only an assignment whose RIGHT-HAND SIDE is the state itself counts as a producer
   if ($lines[$i] -match '=\s*EXH_REVERSAL_CONFIRMED\s*;') { $revAssign += ($i + 1) }
}
$gateNearby = $false
if ($revAssign.Count -ge 1) {
   $start = [Math]::Max(0, $revAssign[0] - 25)
   $window = ($lines[$start..($revAssign[0] - 2)] -join "`n")
   $gateNearby = ($window -match 'reversalFresh')
}
Check "reversal-state-is-gated" (($revAssign.Count -eq 1) -and $gateNearby) `
      ("EXH_REVERSAL_CONFIRMED assigned at line(s): " + ($revAssign -join ", ") + " ; guarded by reversalFresh=" + $gateNearby)

# B4 -- the external-break event type exists and is emitted
$evtUse = ([regex]::Matches($src, 'EVT_EXTERNAL_BREAK')).Count
Check "external-break-event-exists" ($evtUse -ge 4) `
      ("EVT_EXTERNAL_BREAK token count = " + $evtUse + " (enum + string + emit + id)")

# B5 -- the snapshot is taken BEFORE the structure evaluation (ordering matters)
$snapIdx = $src.IndexOf("g_reversal.snapBias")
$evalIdx = $src.IndexOf("EvaluateStructureBreak(hClose, 0, true")
Check "snapshot-before-structure-eval" (($snapIdx -gt 0) -and ($evalIdx -gt 0) -and ($snapIdx -lt $evalIdx)) `
      ("snapshot offset " + $snapIdx + " < HTF evaluate offset " + $evalIdx)

# B6 -- exhaustion must not mention writing the bias anywhere in its body
$exhStart = $src.IndexOf("void UpdateExhaustion(")
$exhEnd   = $src.IndexOf("OnCalculate", $exhStart)
$exhBody  = $src.Substring($exhStart, $exhEnd - $exhStart)
$writesBias = ($exhBody -match 'g_htfBias\s*=(?!=)')
Check "exhaustion-never-writes-bias" (-not $writesBias) `
      ("UpdateExhaustion body contains a bias assignment: " + $writesBias)

# =====================================================================
""
"==== RESULT ===="
"PASS=$pass  FAIL=$fail"
if ($fail -gt 0) { "RESULT: FAILED"; exit 1 } else { "RESULT: all rule and source checks passed"; exit 0 }
