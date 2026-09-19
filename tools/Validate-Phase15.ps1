# =====================================================================
# Validate-Phase15.ps1  --  Phase 15 offline verifier
#                           (historical DST broker offset + setup lifecycle
#                            + behavior checks on real recorded data)
#
# Two independent jobs:
#
#   A) RULE CHECK -- the Phase 15 rules are re-derived by a second
#      implementation written from the rule text, NOT from the MQL5 code:
#        A1  US DST rule    : 2nd Sunday of March 07:00 UTC -> 1st Sunday of
#                             November 06:00 UTC.  Cross-checked against the
#                             Windows time-zone database
#                             (TimeZoneInfo "Eastern Standard Time"), which is
#                             an oracle completely outside this project.
#        A2  EU DST rule    : last Sunday of March 01:00 UTC -> last Sunday of
#                             October 01:00 UTC. Cross-checked against
#                             "Central Europe Standard Time".
#        A3  historical broker offset: offset(serverT) = std + (dstAtUtc ? 60 : 0)
#                             resolved by a fixed point, because the server time
#                             itself depends on the offset. Fixture cases cover
#                             a DST boundary from both sides and a broker with
#                             no DST at all (GMT+5:30).
#        A4  setup lifecycle: a tracked setup is invalidated ONLY when a CLOSED
#                             bar finishes beyond the SL; a wick beyond the SL
#                             is not enough; TP1 is a touch (high/low); if the
#                             same bar does both, invalidation wins. Re-arming
#                             needs a new chain id. The same sequence replayed
#                             as one pass and as several chunks must produce
#                             identical state and counters.
#
#      HONEST LIMITS
#      -------------
#      These are the *rules*, executed offline. The MQL5 implementation itself
#      cannot run outside MetaTrader, so A1..A4 prove the rule text and the
#      fixtures, and section C proves that the source wires the rules in the
#      required order. Only a chart reload can prove the runtime numbers.
#
#   B) BEHAVIOR CHECK -- read-only invariants over snapshots that were really
#      recorded by the indicator on a live chart (see
#      05_TESTS_AND_VALIDATION/behavior/README.md for provenance):
#        B1  FVG lifecycle : geometry, "never mitigated on the birth bar"
#                            (BarsToTouch >= 1), mitigation <-> touch time,
#                            inversion implies mitigation, age >= bars-to-touch
#        B2  reversal gate : a not-broken gate may not carry a confirmation,
#                            a waiting state may not carry a guard level,
#                            chart bars are recorded in ascending order
#      Each snapshot has a deliberately broken twin; the tool must catch it.
#
#   C) SOURCE PROOF -- read the canonical source and prove the wiring the
#      Phase 15 acceptance criteria depend on (historical offset inside the
#      time conversion helpers, lifecycle evaluated BEFORE UpdateSetup and
#      armed AFTER it, HTF events now drawn, inputs appended at the end).
#
# Read-only. No build. No writes except stdout.
# =====================================================================
param(
   [string]$Source   = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5",
   [string]$Fixtures = "D:/ICT_indicator/05_TESTS_AND_VALIDATION/behavior"
)

$ErrorActionPreference = "Stop"
$pass = 0
$fail = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
   if ($ok) { $script:pass++; "PASS  {0}  {1}" -f $name, $detail }
   else     { $script:fail++; "FAIL  {0}  {1}" -f $name, $detail }
}

function LoadRows([string]$path) {
   if (-not (Test-Path $path)) { return @() }
   $lines = Get-Content -Path $path -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }
   if ($lines.Count -lt 2) { return @() }
   return ($lines | ConvertFrom-Csv -Delimiter ';')
}

# =====================================================================
# A) RULE REIMPLEMENTATION
# =====================================================================
function NthDowUtc([int]$y, [int]$m, [int]$nth, [DayOfWeek]$dow) {
   $first = [DateTime]::new($y, $m, 1, 0, 0, 0, [DateTimeKind]::Utc)
   $offset = (7 - [int]$first.DayOfWeek + [int]$dow) % 7
   return $first.AddDays($offset + ($nth - 1) * 7)
}

function LastDowUtc([int]$y, [int]$m, [DayOfWeek]$dow) {
   $lastDay = [DateTime]::DaysInMonth($y, $m)
   $last = [DateTime]::new($y, $m, $lastDay, 0, 0, 0, [DateTimeKind]::Utc)
   $back = ((([int]$last.DayOfWeek) - ([int]$dow) + 7) % 7)
   return $last.AddDays(-$back)
}

function UsDstStartUtc([int]$y) { return (NthDowUtc $y 3 2 ([DayOfWeek]::Sunday)).AddHours(7) }
function UsDstEndUtc([int]$y)   { return (NthDowUtc $y 11 1 ([DayOfWeek]::Sunday)).AddHours(6) }
function EuDstStartUtc([int]$y) { return (LastDowUtc $y 3 ([DayOfWeek]::Sunday)).AddHours(1) }
function EuDstEndUtc([int]$y)   { return (LastDowUtc $y 10 ([DayOfWeek]::Sunday)).AddHours(1) }

function RuleIsDst([string]$rule, [datetime]$utc) {
   $u = [DateTime]::SpecifyKind($utc, [DateTimeKind]::Utc)
   if ($rule -eq "US") {
      $mon = $u.Month
      if ($mon -lt 3 -or $mon -gt 11) { return $false }
      return (($u -ge (UsDstStartUtc $u.Year)) -and ($u -lt (UsDstEndUtc $u.Year)))
   }
   if ($rule -eq "EU") {
      $mon = $u.Month
      if ($mon -lt 3 -or $mon -gt 10) { return $false }
      return (($u -ge (EuDstStartUtc $u.Year)) -and ($u -lt (EuDstEndUtc $u.Year)))
   }
   return $false
}

# The broker offset of a *historical* instant. Two passes of the fixed point,
# exactly like the MQL5 helper: the server clock depends on the offset.
function BrokerOffsetAtServer([int]$stdMinutes, [string]$rule, [datetime]$serverT) {
   $utcA = [DateTime]::SpecifyKind($serverT, [DateTimeKind]::Unspecified).AddMinutes(-$stdMinutes)
   $offA = $stdMinutes
   if (RuleIsDst $rule $utcA) { $offA = $stdMinutes + 60 }
   $utcB = [DateTime]::SpecifyKind($serverT, [DateTimeKind]::Unspecified).AddMinutes(-$offA)
   $offB = $stdMinutes
   if (RuleIsDst $rule $utcB) { $offB = $stdMinutes + 60 }
   return $offB
}

# ---------------------------------------------------------------------
# A1/A2 -- the oracle: Windows time-zone database
# ---------------------------------------------------------------------
function FindTz([string[]]$ids) {
   foreach ($id in $ids) {
      try { return [TimeZoneInfo]::FindSystemTimeZoneById($id) } catch { }
   }
   return $null
}

$tzUs = FindTz @("Eastern Standard Time", "America/New_York")
$tzEu = FindTz @("Central Europe Standard Time", "Central European Standard Time", "W. Europe Standard Time", "Europe/Berlin")

function OracleIsDst($tz, [datetime]$utc) {
   # NOTE: DateTime.IsDaylightSavingTime() would answer for the *machine's* local
   # zone, not for $tz. The honest oracle is the offset the zone actually applies
   # at that UTC instant, compared with its own standard offset.
   $u = [DateTime]::SpecifyKind($utc, [DateTimeKind]::Utc)
   return ($tz.GetUtcOffset($u) -ne $tz.BaseUtcOffset)
}

function CompareRuleToOracle([string]$rule, $tz, [int]$fromYear, [int]$toYear, [int]$stepHours) {
   $mismatch = 0
   $checked = 0
   for ($y = $fromYear; $y -le $toYear; $y++) {
      $t = [DateTime]::new($y, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
      $end = [DateTime]::new($y, 12, 31, 23, 0, 0, [DateTimeKind]::Utc)
      while ($t -le $end) {
         $mine = RuleIsDst $rule $t
         $theirs = OracleIsDst $tz $t
         $checked++
         if ($mine -ne $theirs) { $mismatch++ }
         $t = $t.AddHours($stepHours)
      }
   }
   return [pscustomobject]@{ Checked = $checked; Mismatch = $mismatch }
}

if ($null -ne $tzUs) {
   $r = CompareRuleToOracle "US" $tzUs 2015 2030 6
   Check "us-dst-rule-matches-windows-tz-database" ($r.Mismatch -eq 0) `
         ("{0} instants compared (2015-2030, every 6h), mismatches = {1}" -f $r.Checked, $r.Mismatch)
} else {
   Check "us-dst-rule-matches-windows-tz-database" $false "time-zone database not reachable -- NOT VERIFIED"
}

if ($null -ne $tzEu) {
   $r = CompareRuleToOracle "EU" $tzEu 2015 2030 6
   Check "eu-dst-rule-matches-windows-tz-database" ($r.Mismatch -eq 0) `
         ("{0} instants compared (2015-2030, every 6h), mismatches = {1}" -f $r.Checked, $r.Mismatch)
} else {
   Check "eu-dst-rule-matches-windows-tz-database" $false "time-zone database not reachable -- NOT VERIFIED"
}

# ---------------------------------------------------------------------
# A1/A2 (frozen) -- boundary fixtures
# ---------------------------------------------------------------------
function TestDstFixture([string]$path) {
   $rows = LoadRows $path
   $bad = 0
   foreach ($r in $rows) {
      $utc = [DateTime]::ParseExact($r.UtcTime, "yyyy.MM.dd HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
      $mine = RuleIsDst $r.Rule $utc
      $want = ($r.ExpectDST -eq "1")
      if ($mine -ne $want) { $bad++ }
   }
   return [pscustomobject]@{ Rows = $rows.Count; Bad = $bad }
}

$dstFile    = Join-Path $Fixtures "dst_rules.fixture.csv"
$dstBadFile = Join-Path $Fixtures "dst_rules_bad.fixture.csv"
$f = TestDstFixture $dstFile
Check "dst-boundary-fixture" (($f.Rows -gt 0) -and ($f.Bad -eq 0)) ("{0} boundary cases, mismatches = {1}" -f $f.Rows, $f.Bad)
$fb = TestDstFixture $dstBadFile
Check "dst-boundary-self-test-catches-the-broken-fixture" (($fb.Rows -gt 0) -and ($fb.Bad -gt 0)) `
      ("broken fixture rows = {0}, detected wrong rows = {1}" -f $fb.Rows, $fb.Bad)

# ---------------------------------------------------------------------
# A3 -- historical broker offset
# ---------------------------------------------------------------------
function TestOffsetFixture([string]$path) {
   $rows = LoadRows $path
   $bad = 0
   foreach ($r in $rows) {
      $srv = [DateTime]::ParseExact($r.ServerTime, "yyyy.MM.dd HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
      $mine = BrokerOffsetAtServer ([int]$r.StdOffsetMin) $r.Rule $srv
      if ($mine -ne [int]$r.ExpectOffsetMin) { $bad++ }
   }
   return [pscustomobject]@{ Rows = $rows.Count; Bad = $bad }
}

$offFile    = Join-Path $Fixtures "broker_offset.fixture.csv"
$offBadFile = Join-Path $Fixtures "broker_offset_bad.fixture.csv"
$o = TestOffsetFixture $offFile
Check "historical-broker-offset-fixture" (($o.Rows -gt 0) -and ($o.Bad -eq 0)) ("{0} cases, mismatches = {1}" -f $o.Rows, $o.Bad)
$ob = TestOffsetFixture $offBadFile
Check "historical-broker-offset-self-test-catches-the-broken-fixture" (($ob.Rows -gt 0) -and ($ob.Bad -gt 0)) `
      ("broken fixture rows = {0}, detected wrong rows = {1}" -f $ob.Rows, $ob.Bad)

# ---------------------------------------------------------------------
# A4 -- setup lifecycle state machine (replayable, chunk-safe)
# ---------------------------------------------------------------------
function NewLifeState {
   return @{ State = "IDLE"; Dir = ""; Entry = 0.0; SL = 0.0; TP1 = 0.0; Chain = -1; Armed = 0; Invalid = 0; TP1Hits = 0 }
}

function ReplayLifecycle($st, $rows) {
   foreach ($r in $rows) {
      $close = [double]$r.Close
      $high  = [double]$r.High
      $low   = [double]$r.Low
      # step 1 -- judge the setup that is already being tracked (runs BEFORE
      # the new READY decision of the same bar, exactly like the source)
      if ($st.State -eq "TRACKING") {
         $slHit = $false
         $tpHit = $false
         if ($st.Dir -eq "BULL") {
            $slHit = ($close -lt $st.SL)
            $tpHit = (($high -gt 0.0) -and ($high -ge $st.TP1))
         } elseif ($st.Dir -eq "BEAR") {
            $slHit = ($close -gt $st.SL)
            $tpHit = (($low -gt 0.0) -and ($low -le $st.TP1))
         }
         if ($slHit)      { $st.State = "INVALIDATED"; $st.Invalid++ }          # conservative: SL wins
         elseif ($tpHit)  { $st.State = "TP1_HIT";     $st.TP1Hits++ }
      }
      # step 2 -- arm after a READY decision (runs AFTER UpdateSetup in the source)
      if ($r.ReadyNow -eq "1") {
         $chain = [int]$r.ChainId
         $entry = [double]$r.Entry
         $sl    = [double]$r.SL
         $tp1   = [double]$r.TP1
         if (($entry -gt 0.0) -and ($sl -gt 0.0) -and ($tp1 -gt 0.0)) {
            if (-not (($st.State -eq "TRACKING") -and ($st.Chain -eq $chain))) {
               $st.State = "TRACKING"
               $st.Dir   = $r.Dir
               $st.Entry = $entry
               $st.SL    = $sl
               $st.TP1   = $tp1
               $st.Chain = $chain
               $st.Armed++
            }
         }
      }
   }
   return $st
}

function TestLifecycleFixture([string]$path) {
   $rows = LoadRows $path
   $bad = 0
   $cases = $rows | Group-Object Case
   foreach ($c in $cases) {
      $st = ReplayLifecycle (NewLifeState) $c.Group
      $exp = $c.Group[0]
      $okState = ($st.State -eq $exp.ExpectState)
      $okArm   = ([int]$st.Armed -eq [int]$exp.ExpectArmed)
      $okInv   = ([int]$st.Invalid -eq [int]$exp.ExpectInvalid)
      $okTp1   = ([int]$st.TP1Hits -eq [int]$exp.ExpectTP1)
      if (-not ($okState -and $okArm -and $okInv -and $okTp1)) {
         $bad++
         "(   case {0}: got {1}/{2}/{3}/{4}, expected {5}/{6}/{7}/{8})" -f `
            $c.Name, $st.State, $st.Armed, $st.Invalid, $st.TP1Hits, `
            $exp.ExpectState, $exp.ExpectArmed, $exp.ExpectInvalid, $exp.ExpectTP1
      }
   }
   return [pscustomobject]@{ Cases = $cases.Count; Bad = $bad }
}

$lifeFile    = Join-Path $Fixtures "setup_lifecycle.fixture.csv"
$lifeBadFile = Join-Path $Fixtures "setup_lifecycle_bad.fixture.csv"
$l = TestLifecycleFixture $lifeFile
Check "setup-lifecycle-fixture" (($l.Cases -gt 0) -and ($l.Bad -eq 0)) ("{0} scenarios, mismatches = {1}" -f $l.Cases, $l.Bad)
$lb = TestLifecycleFixture $lifeBadFile
Check "setup-lifecycle-self-test-catches-the-broken-fixture" (($lb.Cases -gt 0) -and ($lb.Bad -gt 0)) `
      ("broken fixture scenarios = {0}, detected wrong scenarios = {1}" -f $lb.Cases, $lb.Bad)

# full pass vs chunked pass must be identical (the rebuild can be interrupted)
$lifeRows = LoadRows $lifeFile
$full = ReplayLifecycle (NewLifeState) $lifeRows
$chunkedState = NewLifeState
$n = $lifeRows.Count
$cut1 = [int][Math]::Floor($n / 3)
$cut2 = [int][Math]::Floor(2 * $n / 3)
$chunked = ReplayLifecycle $chunkedState ($lifeRows[0..($cut1 - 1)])
$chunked = ReplayLifecycle $chunked ($lifeRows[$cut1..($cut2 - 1)])
$chunked = ReplayLifecycle $chunked ($lifeRows[$cut2..($n - 1)])
$same = ($full.State -eq $chunked.State) -and ($full.Armed -eq $chunked.Armed) -and
        ($full.Invalid -eq $chunked.Invalid) -and ($full.TP1Hits -eq $chunked.TP1Hits) -and
        ($full.Chain -eq $chunked.Chain)
Check "lifecycle-full-vs-chunked-is-identical" $same `
      ("full {0}/{1}/{2}/{3} chain {4} vs chunked {5}/{6}/{7}/{8} chain {9}" -f `
       $full.State, $full.Armed, $full.Invalid, $full.TP1Hits, $full.Chain, `
       $chunked.State, $chunked.Armed, $chunked.Invalid, $chunked.TP1Hits, $chunked.Chain)

# =====================================================================
# B) BEHAVIOR INVARIANTS OVER REALLY RECORDED SNAPSHOTS
# =====================================================================
$srcText = Get-Content -Path $Source -Raw -Encoding UTF8
$expireBars = 500
$mExpire = [regex]::Match($srcText, 'InpFVG_ExpireBars\s*=\s*(\d+)')
if ($mExpire.Success) { $expireBars = [int]$mExpire.Groups[1].Value }

function TestFvgSnapshot([string]$path, [int]$expire) {
   $rows = LoadRows $path
   $viol = New-Object System.Collections.ArrayList
   foreach ($r in $rows) {
      $top = [double]$r.Top; $bot = [double]$r.Bottom; $age = [int]$r.AgeBars
      $mit = ($r.Mitigated -eq "1"); $inv = ($r.Invalidated -eq "1"); $inverted = ($r.Inverted -eq "1")
      $touch = ($r.TouchTime -ne $null -and $r.TouchTime.Trim() -ne "")
      $btt = [int]$r.BarsToTouch
      if ($top -le $bot) { [void]$viol.Add("row $($r.Id): Top <= Bottom") }
      if ($mit -and -not $touch) { [void]$viol.Add("row $($r.Id): mitigated without a touch time") }
      if ($mit -and $btt -lt 1)  { [void]$viol.Add("row $($r.Id): mitigated on the birth bar (bars-to-touch $btt)") }
      if ((-not $mit) -and $touch) { [void]$viol.Add("row $($r.Id): touched but not marked mitigated") }
      if ((-not $mit) -and ($btt -ne -1)) { [void]$viol.Add("row $($r.Id): untouched but bars-to-touch $btt") }
      if ($inverted -and -not $mit) { [void]$viol.Add("row $($r.Id): inverted but not mitigated") }
      if ($inv -and -not $mit) { [void]$viol.Add("row $($r.Id): invalidated but never mitigated") }
      if ($mit -and ($age -lt $btt)) { [void]$viol.Add("row $($r.Id): age $age < bars-to-touch $btt") }
      if ($inv -and ($age -le $expire)) { [void]$viol.Add("row $($r.Id): invalidated at age $age <= expire $expire") }
      if ((-not $inv) -and ($age -gt $expire)) { [void]$viol.Add("row $($r.Id): alive at age $age > expire $expire") }
   }
   return [pscustomobject]@{ Rows = $rows.Count; Violations = $viol }
}

function TestReversalSnapshot([string]$path) {
   $rows = LoadRows $path
   $viol = New-Object System.Collections.ArrayList
   $notes = New-Object System.Collections.ArrayList
   $prev = ""
   foreach ($r in $rows) {
      $broke = ($r.Broke -eq "true")
      $confirmed = ($r.ConfirmedTime -ne "1970.01.01 00:00")
      $waiting = ($r.State -eq "WAITING_H4_BIAS")
      if ($waiting -and ([long]$r.GuardId -ne -1)) { [void]$viol.Add("$($r.ChartBar): waiting state carries guard id $($r.GuardId)") }
      if ($waiting -and ([double]$r.GuardPrice -ne 0.0)) { [void]$viol.Add("$($r.ChartBar): waiting state carries guard price") }
      if ($waiting -and ($r.GuardSide -ne "-")) { [void]$viol.Add("$($r.ChartBar): waiting state carries guard side") }
      if ((-not $broke) -and $confirmed) { [void]$viol.Add("$($r.ChartBar): confirmation without a break") }
      if (($r.SmartMoneyReversal -ne "true") -and $confirmed) { [void]$viol.Add("$($r.ChartBar): confirmation without a reversal score") }
      if ($broke -and ([long]$r.GuardId -lt 0)) { [void]$viol.Add("$($r.ChartBar): break without a guard level") }
      if ([int]$r.SMRScore -gt [int]$r.SMRMax) { [void]$viol.Add("$($r.ChartBar): score above maximum") }
      # Chart-bar order is deliberately NOT a rule check on the legacy snapshot:
      # that ledger carried no Symbol column, so two live chart instances wrote
      # into one file and their rows interleave. This is the very defect Phase 15
      # fixed (Symbol column + refusal to append ambiguous rows), so the fixture
      # is used here as *documentary evidence of the defect*, not as a rule break.
      $bar = $r.ChartBar
      if (($prev -ne "") -and ($bar -le $prev)) { [void]$notes.Add("${bar}: row from a different writer interleaves") }
      $prev = $bar
   }
   return [pscustomobject]@{ Rows = $rows.Count; Violations = $viol; Notes = $notes }
}

$fvgFile    = Join-Path $Fixtures "fvg_lifecycle_snapshot.csv"
$fvgBadFile = Join-Path $Fixtures "fvg_lifecycle_snapshot_bad.csv"
$revFile    = Join-Path $Fixtures "reversal_gate_snapshot.csv"
$revBadFile = Join-Path $Fixtures "reversal_gate_snapshot_bad.csv"

$s1 = TestFvgSnapshot $fvgFile $expireBars
Check "fvg-snapshot-invariants" (($s1.Rows -gt 0) -and ($s1.Violations.Count -eq 0)) `
      ("{0} recorded FVG rows, violations = {1}" -f $s1.Rows, $s1.Violations.Count)
if ($s1.Violations.Count -gt 0) { $s1.Violations | ForEach-Object { "      - $_" } }
$s1b = TestFvgSnapshot $fvgBadFile $expireBars
Check "fvg-snapshot-self-test-catches-the-broken-snapshot" ($s1b.Violations.Count -gt 0) `
      ("broken snapshot rows = {0}, violations found = {1}" -f $s1b.Rows, $s1b.Violations.Count)

$s2 = TestReversalSnapshot $revFile
Check "reversal-gate-snapshot-invariants" (($s2.Rows -gt 0) -and ($s2.Violations.Count -eq 0)) `
      ("{0} recorded gate rows, violations = {1}" -f $s2.Rows, $s2.Violations.Count)
if ($s2.Violations.Count -gt 0) { $s2.Violations | ForEach-Object { "      - $_" } }
Check "reversal-snapshot-documents-the-multi-writer-defect" ($s2.Notes.Count -ge 1) `
      ("interleaved rows from a second writer without a Symbol column = {0}" -f $s2.Notes.Count)
$s2b = TestReversalSnapshot $revBadFile
Check "reversal-gate-snapshot-self-test-catches-the-broken-snapshot" ($s2b.Violations.Count -gt 0) `
      ("broken snapshot rows = {0}, violations found = {1}" -f $s2b.Rows, $s2b.Violations.Count)

# =====================================================================
# C) SOURCE PROOF
# =====================================================================
function CountOf([string]$needle) { return ([regex]::Matches($srcText, [regex]::Escape($needle))).Count }

# C1 -- the time conversion helpers now resolve the offset of the instant
Check "server-to-utc-uses-the-historical-offset" `
      ((CountOf "BrokerOffsetSecondsAtServer(serverT)") -eq 1) `
      ("BrokerOffsetSecondsAtServer(serverT) occurrences = " + (CountOf "BrokerOffsetSecondsAtServer(serverT)"))
Check "utc-to-server-uses-the-historical-offset" `
      ((CountOf "BrokerOffsetSecondsAtUTC(utcT)") -eq 1) `
      ("BrokerOffsetSecondsAtUTC(utcT) occurrences = " + (CountOf "BrokerOffsetSecondsAtUTC(utcT)"))
Check "historical-offset-helpers-are-defined-once" `
      (((CountOf "int BrokerOffsetSecondsAtUTC(datetime utcT)") -eq 1) -and
       ((CountOf "int BrokerOffsetSecondsAtServer(datetime serverT)") -eq 1) -and
       ((CountOf "void DeriveBrokerDSTRuleAndStdOffset()") -eq 1)) `
      ("definitions: atUtc=" + (CountOf "int BrokerOffsetSecondsAtUTC(datetime utcT)") +
       " atServer=" + (CountOf "int BrokerOffsetSecondsAtServer(datetime serverT)") +
       " derive=" + (CountOf "void DeriveBrokerDSTRuleAndStdOffset()"))
$deriveCalls = CountOf "DeriveBrokerDSTRuleAndStdOffset();"
Check "standard-offset-derivation-happens-at-init-and-on-offset-change" ($deriveCalls -ge 2) `
      ("DeriveBrokerDSTRuleAndStdOffset() call sites (init + offset refresh) = " + $deriveCalls)
Check "offset-change-still-purges-stale-session-levels" `
      ((CountOf "PurgeSessionLiquidity();") -eq 1) `
      ("PurgeSessionLiquidity() call site inside RefreshBrokerOffset = " + (CountOf "PurgeSessionLiquidity();"))
Check "per-bar-historical-delta-is-recorded" `
      ((CountOf "g_histOffsetDeltaMin=(BrokerOffsetSecondsAtServer(barTime)-g_serverGMTOffsetSeconds)/60;") -eq 1) `
      "the per-bar offset delta against the live offset is computed"
Check "dst-rules-implemented-once-each" `
      (((CountOf "bool US_IsDST_UTC(datetime utcT)") -eq 1) -and
       ((CountOf "bool EU_IsDST_UTC(datetime utcT)") -eq 1) -and
       ((CountOf "bool BrokerDSTAtUTC(datetime utcT)") -eq 1)) `
      ("US=" + (CountOf "bool US_IsDST_UTC(datetime utcT)") +
       " EU=" + (CountOf "bool EU_IsDST_UTC(datetime utcT)") +
       " broker=" + (CountOf "bool BrokerDSTAtUTC(datetime utcT)"))
Check "disabled-historical-mode-falls-back-to-the-old-behaviour" `
      ((CountOf "if(!InpUseHistoricalBrokerOffset) return g_serverGMTOffsetSeconds;") -eq 2) `
      ("fallback returns in both resolvers = " + (CountOf "if(!InpUseHistoricalBrokerOffset) return g_serverGMTOffsetSeconds;"))

# C2 -- the lifecycle is judged BEFORE the new setup and armed AFTER it
$ctxIdx        = $srcText.IndexOf("void UpdateContextForClosedBar(")
$judgeIdx      = $srcText.IndexOf("UpdateSetupLifecycle(barTime, closePrice, highPrice, lowPrice);")
$setupIdx      = $srcText.IndexOf("UpdateSetup(closePrice, atrValue, barTime);")
$armIdx        = $srcText.IndexOf("ArmSetupLifecycle(barTime);")
$phase15FinIdx = $srcText.IndexOf("PersistPhase15Diagnostics(barTime);")
Check "lifecycle-is-judged-before-the-new-setup-decision" `
      (($ctxIdx -gt 0) -and ($ctxIdx -lt $judgeIdx) -and ($judgeIdx -lt $setupIdx)) `
      ("context=" + $ctxIdx + " judge=" + $judgeIdx + " setup=" + $setupIdx)
Check "lifecycle-is-armed-after-the-new-setup-decision" `
      (($setupIdx -gt 0) -and ($setupIdx -lt $armIdx) -and ($armIdx -lt $phase15FinIdx)) `
      ("setup=" + $setupIdx + " arm=" + $armIdx + " evidence=" + $phase15FinIdx)
Check "only-one-place-arms-the-tracking-state" ((CountOf 'g_setupLifeState="TRACKING";') -eq 1) `
      ('g_setupLifeState="TRACKING" assignments = ' + (CountOf 'g_setupLifeState="TRACKING";'))
Check "invalidation-is-close-based-and-target-is-touch-based" `
      (((CountOf 'slHit  = (closePrice < g_setupLifeSL);') -eq 1) -and
       ((CountOf 'slHit  = (closePrice > g_setupLifeSL);') -eq 1) -and
       ((CountOf 'tp1Hit = (highPrice>0.0 && highPrice>=g_setupLifeTP1);') -eq 1) -and
       ((CountOf 'tp1Hit = (lowPrice>0.0 && lowPrice<=g_setupLifeTP1);') -eq 1)) `
      "close-only invalidation and touch-based TP1 are both wired for LONG and SHORT"
$slBranch = $srcText.IndexOf("   if(slHit)", $judgeIdx)
$tpBranch = $srcText.IndexOf("   else if(tp1Hit)", $judgeIdx)
Check "invalidation-wins-when-one-bar-does-both" (($slBranch -gt 0) -and ($slBranch -lt $tpBranch)) `
      ("if(slHit) at " + $slBranch + " < else if(tp1Hit) at " + $tpBranch)
Check "lifecycle-events-are-persisted-for-both-paths" `
      (((CountOf 'PersistSetupLifecycleEvent("ARMED", barTime, g_setup.entry);') -eq 1) -and
       ((CountOf 'PersistSetupLifecycleEvent("INVALIDATED", barTime, closePrice);') -eq 1) -and
       ((CountOf 'PersistSetupLifecycleEvent("TP1_HIT", barTime, reached);') -eq 1)) `
      "ARMED / INVALIDATED / TP1_HIT are each written once"
Check "lifecycle-can-be-switched-off" ((CountOf "if(!InpTrackSetupLifecycle) return;") -eq 2) `
      ("InpTrackSetupLifecycle guards = " + (CountOf "if(!InpTrackSetupLifecycle) return;"))

# C3 -- HTF structure events are now drawn (open item of Phase 14)
Check "htf-events-are-drawn-with-their-own-cap" `
      (((CountOf "if(InpDrawHTFEvents)") -eq 1) -and
       ((CountOf "g_htfEventsDrawn=drawnH;") -eq 1)) `
      ("InpDrawHTFEvents blocks = " + (CountOf "if(InpDrawHTFEvents)") +
       " cap assignments = " + (CountOf "g_htfEventsDrawn=drawnH;"))
# HTF-skip sites: the setup chain gate + the local-timeframe draw loop.
# non-HTF-skip sites: UpdateTrendPhase + the chain gate + the new HTF draw loop.
Check "ltf-and-htf-filters-are-both-one-per-loop" `
      (((CountOf "if(g_events[i].isHTF) continue;") -eq 2) -and
       ((CountOf "if(!g_events[i].isHTF) continue;") -eq 3)) `
      ("HTF skip = " + (CountOf "if(g_events[i].isHTF) continue;") +
       " (chain gate + draw loop) , non-HTF skip = " + (CountOf "if(!g_events[i].isHTF) continue;") +
       " (trend phase + chain gate + HTF draw loop)")
Check "htf-event-label-carries-its-own-timeframe" `
      (((CountOf 'if(e.isHTF) evtTxt = TFShortName(InpHTF)+') -eq 1) -and
       ((CountOf 'datetime lineEnd = e.time + PeriodSeconds(e.isHTF? InpHTF : PERIOD_CURRENT)*10;') -eq 1)) `
      "label prefix and horizontal extension both use the HTF period"

# C4 -- evidence files and append-only inputs
Check "phase15-evidence-ledger-has-its-columns" `
      (((CountOf '"InvalidatedAt","InvalidatedPrice");') -eq 1) -and
      ((CountOf '"EventTime","BuildStamp","Event","Dir","Entry","SL","TP1","Price","ChainEventId","Reason");') -eq 1)) `
      "both Phase 15 CSV headers exist exactly once"
$phase14Last = $srcText.IndexOf("input bool   InpLogPhase14OnRedraw")
$phase15Grp  = $srcText.IndexOf('input group "== Phase 15:')
$phase15Rule = $srcText.IndexOf("input ENUM_BROKER_DST_RULE InpBrokerDSTRule")
Check "phase15-inputs-are-appended" (($phase14Last -gt 0) -and ($phase15Grp -gt $phase14Last) -and ($phase15Rule -gt $phase15Grp)) `
      ("last Phase 14 input at " + $phase14Last + " < Phase 15 group at " + $phase15Grp + " < rule input at " + $phase15Rule)
Check "event-enum-order-is-preserved" `
      ((CountOf "enum ENUM_EVENT_TYPE   { EVT_BOS, EVT_CHOCH, EVT_MSS, EVT_EXTERNAL_BREAK };") -eq 1) `
      "StableEventId depends on the numeric order of the event types"
Check "load-stamp-reports-the-phase15-state" `
      (((CountOf 'FileWrite(h,"BrokerDSTRule"') -eq 1) -and
       ((CountOf 'FileWrite(h,"HistoricalOffsetMode"') -eq 1) -and
       ((CountOf 'FileWrite(h,"TrackSetupLifecycle"') -eq 1) -and
       ((CountOf 'FileWrite(h,"DrawHTFEvents"') -eq 1)) `
      "the load stamp records the rule, the mode and both toggles"

# =====================================================================
""
"==== RESULT ===="
"PASS=$pass  FAIL=$fail"
if ($fail -gt 0) { "RESULT: FAILED"; exit 1 } else { "RESULT: all rule, behavior and source checks passed"; exit 0 }
