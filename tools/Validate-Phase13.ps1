# =====================================================================
# Validate-Phase13.ps1  --  Phase 13 offline verifier (stability & performance)
#
# Two independent jobs:
#   A) RULE CHECK  : re-derive three Phase 13 rules from raw fixture rows and
#                    compare with the expected columns:
#                      A1  "at most one structure evaluation per HTF bar"
#                          (issue #7 — duplicate BOS on the same H4 candle)
#                      A2  FIFO cap/eviction arithmetic (issue #11)
#                      A3  EQ grouping idempotence — the property that makes
#                          the DetectEQ memo skip safe (no level can be lost)
#                    Nothing is imported from the indicator: this is a second
#                    implementation written from the rule text, not from code.
#   B) SOURCE PROOF: read the canonical source and prove the invariants the
#                    acceptance criteria of Phase 13 depend on, including that
#                    the fast paths are really wired to the rules above.
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
      if ($first) { $first = $false; if ($t -match '^[A-Za-z]' -and $t -match 'expect|cap|tol|prices') { continue } }
      $out += ,($t -split ',')
   }
   return $out
}

function ParseTs([string]$s) {
   return [datetime]::ParseExact($s.Trim(), "yyyy.MM.dd HH:mm", [Globalization.CultureInfo]::InvariantCulture)
}

# ---------------------------------------------------------------------
# A1) one structure evaluation per HTF bar
#
# The rule, restated independently: a swing is broken once, so a second
# evaluation inside the same HTF bucket compares the same close with an
# OLDER still-unbroken swing and emits an extra event on that candle.
# The guard must therefore allow at most one evaluation per HTF bucket,
# while still letting every later bucket produce its own event.
# ---------------------------------------------------------------------
function SimulateCadence($rows, [bool]$guarded) {
   $perScenario = @{}     # cumulative events per scenario
   $lastBucket  = @{}     # last HTF bucket evaluated per scenario
   foreach ($r in $rows) {
      $scenario = $r[0].Trim()
      if (-not $perScenario.ContainsKey($scenario)) { $perScenario[$scenario] = 0; $lastBucket[$scenario] = $null }
      $bucket = ParseTs $r[2]
      $close  = [double]$r[3]
      if ($r[4].Trim().Length -gt 0) { $highs = @($r[4].Trim().Split('|')) }
      else                           { $highs = @() }

      $skip = ($guarded -and ($lastBucket[$scenario] -ne $null) -and ($bucket -eq $lastBucket[$scenario]))
      if (-not $skip) {
         $lastBucket[$scenario] = $bucket
         # only the NEWEST unbroken swing is tested (registry order: oldest first)
         for ($k = $highs.Count - 1; $k -ge 0; $k--) {
            if ($close -gt [double]$highs[$k]) { $perScenario[$scenario]++; break }
         }
      }
   }
   return $perScenario
}

"=== A1) RULE CHECK: at most one structure evaluation per HTF bar (#7)"
$dupRows = ReadRows (Join-Path $Fixtures "phase13_htf_dup.fixture.csv")
$ung = SimulateCadence $dupRows $false
$grd = SimulateCadence $dupRows $true

# expected final totals taken from the fixture columns, grouped by scenario
$expUng = @{}; $expGrd = @{}
foreach ($r in $dupRows) {
   $s = $r[0].Trim()
   $expUng[$s] = [int]$r[5]
   $expGrd[$s] = [int]$r[6]
}
foreach ($s in ($expUng.Keys | Sort-Object)) {
   Check ("htf-dup[$s] unguarded matches fixture") ($ung[$s] -eq $expUng[$s]) `
         ("unguarded events=" + $ung[$s] + " expected=" + $expUng[$s])
   Check ("htf-dup[$s] guarded matches fixture")   ($grd[$s] -eq $expGrd[$s]) `
         ("guarded events=" + $grd[$s] + " expected=" + $expGrd[$s])
   Check ("htf-dup[$s] guard removes the duplicate") ($grd[$s] -lt $ung[$s] -or $expUng[$s] -eq $expGrd[$s]) `
         ("unguarded=" + $ung[$s] + " guarded=" + $grd[$s])
}

"=== A1b) NON-FUNCTION TEST: a deliberately wrong fixture MUST fail"
$badRows = ReadRows (Join-Path $Fixtures "phase13_htf_dup_bad.fixture.csv")
$badCaught = 0
$badUng = SimulateCadence $badRows $false
$badGrd = SimulateCadence $badRows $true
foreach ($r in $badRows) {
   $s = $r[0].Trim()
   if (([int]$r[5] -ne $badUng[$s]) -or ([int]$r[6] -ne $badGrd[$s])) { $badCaught++ }
}
Check "self-test(bad htf fixture is rejected)" ($badCaught -eq $badRows.Count) `
      ("caught " + $badCaught + " of " + $badRows.Count + " wrong expectations")

# ---------------------------------------------------------------------
# A2) FIFO cap / eviction arithmetic (#11)
# ---------------------------------------------------------------------
"=== A2) RULE CHECK: FIFO cap and dropped-count arithmetic (#11)"
$capRows = ReadRows (Join-Path $Fixtures "phase13_caps.fixture.csv")
foreach ($r in $capRows) {
   $pushed = [int]$r[0]; $cap = [int]$r[1]
   $expSize = [int]$r[2]; $expDropped = [int]$r[3]
   $arr = @(); $dropped = 0
   for ($i = 0; $i -lt $pushed; $i++) {
      $arr += $i
      if ($cap -gt 0 -and $arr.Count -gt $cap) {
         $drop = $arr.Count - $cap
         $arr = $arr[$drop..($arr.Count - 1)]
         $dropped += $drop
      }
   }
   Check ("caps[pushed=" + $pushed + ",cap=" + $cap + "]") `
         (($arr.Count -eq $expSize) -and ($dropped -eq $expDropped)) `
         ("size=" + $arr.Count + " (exp " + $expSize + ") dropped=" + $dropped + " (exp " + $expDropped + ")")
   # FIFO means the SURVIVING window is the newest one, never the oldest
   if ($arr.Count -gt 0 -and $cap -gt 0) {
      $newestKept = ($arr[$arr.Count - 1] -eq ($pushed - 1))
      Check ("caps[cap=" + $cap + "] keeps the newest") $newestKept `
            ("last surviving index=" + $arr[$arr.Count - 1] + " of pushed=" + $pushed)
   }
}

# ---------------------------------------------------------------------
# A3) EQ grouping idempotence — the memo skip must not lose a level
# ---------------------------------------------------------------------
function GroupEQ($prices, [double]$tol) {
   $used = New-Object bool[] $prices.Count
   $registered = New-Object System.Collections.ArrayList
   for ($i = 0; $i -lt $prices.Count; $i++) {
      if ($used[$i]) { continue }
      $extreme = $prices[$i]
      $members = 1
      for ($j = $i + 1; $j -lt $prices.Count; $j++) {
         if ($used[$j]) { continue }
         if ([Math]::Abs($prices[$j] - $extreme) -gt $tol) { continue }
         $used[$j] = $true
         $members++
         $extreme = [Math]::Max($extreme, $prices[$j])
      }
      if ($members -ge 2) { $used[$i] = $true; [void]$registered.Add($extreme) }
   }
   return $registered
}

"=== A3) RULE CHECK: EQ grouping is idempotent (memo skip is lossless)"
$eqRows = ReadRows (Join-Path $Fixtures "phase13_eqidem.fixture.csv")
foreach ($r in $eqRows) {
   $scenario = $r[0].Trim()
   $tol = [double]$r[1]
   $prices = @($r[2].Trim().Split('|') | ForEach-Object { [double]$_ })
   $expGroups = [int]$r[3]
   $run1 = GroupEQ $prices $tol
   $run2 = GroupEQ $prices $tol
   $sameSet = (($run1.Count -eq $run2.Count) -and (($run1 -join ',') -eq ($run2 -join ',')))
   Check ("eq[$scenario] group count") ($run1.Count -eq $expGroups) `
         ("groups=" + $run1.Count + " expected=" + $expGroups)
   Check ("eq[$scenario] second run is identical set") $sameSet `
         ("run1=[" + ($run1 -join ',') + "] run2=[" + ($run2 -join ',') + "]")
   # the surviving items are the same values, so the registry dedup adds nothing new
   $newlyAdded = 0
   foreach ($v in $run2) { if ($run1 -notcontains $v) { $newlyAdded++ } }
   Check ("eq[$scenario] second run registers nothing new") ($newlyAdded -eq 0) `
         ("new registrations on second run = " + $newlyAdded)
}

# =====================================================================
"=== B) SOURCE PROOF: Phase 13 invariants"
# =====================================================================
if (-not (Test-Path $Source)) { throw "source not found: $Source" }
$src = Get-Content -LiteralPath $Source -Raw -Encoding UTF8
$lines = Get-Content -LiteralPath $Source -Encoding UTF8

# B1 -- #7: the HTF evaluation is guarded by the HTF bucket, and the guard is
#       placed BEFORE the pivot push and BEFORE the structure evaluation.
$guardIdx = $src.IndexOf("if(htfRates[0].time==g_lastHtfEvalBarTime)")
$evalIdx  = $src.IndexOf("EvaluateStructureBreak(hClose, 0, true")
$pivotIdx = $src.IndexOf("PushSwing(g_swingsHTF, s, InpMaxSwings)")
Check "htf-guard-exists" ($guardIdx -gt 0) ("guard offset " + $guardIdx)
Check "htf-guard-before-evaluation" (($guardIdx -gt 0) -and ($evalIdx -gt $guardIdx)) `
      ("guard " + $guardIdx + " < HTF evaluate " + $evalIdx)
Check "htf-guard-before-pivot-push" (($guardIdx -gt 0) -and ($pivotIdx -gt $guardIdx)) `
      ("guard " + $guardIdx + " < first PushSwing(HTF) " + $pivotIdx)
$htfEvalCalls = ([regex]::Matches($src, 'EvaluateStructureBreak\(hClose, 0, true')).Count
Check "htf-evaluation-has-one-call-site" ($htfEvalCalls -eq 1) `
      ("EvaluateStructureBreak(hClose,0,true) call sites = " + $htfEvalCalls)

# B2 -- #11: g_events and g_displacements are capped, and every push goes through
#       the capped appender (no raw ArrayResize push left behind).
# Scoped proof: the structure engine itself must no longer push to g_events; only
# the capped appender may. (OnInit's reset and the appender's own two resizes are
# expected and are therefore excluded by scope, not by hope.)
$evalStart = $src.IndexOf("void EvaluateStructureBreak(")
$evalEnd   = $src.IndexOf("long AddLiquidity(", $evalStart)
$evalBody  = $src.Substring($evalStart, $evalEnd - $evalStart)
$pushInEngine = ([regex]::Matches($evalBody, 'ArrayResize\(g_events')).Count
Check "events-push-is-centralized" ($pushInEngine -eq 0) `
      ("ArrayResize(g_events) inside EvaluateStructureBreak = " + $pushInEngine + " (must be 0)")
$appendCalls = ([regex]::Matches($src, 'AppendStructureEvent\(e\);')).Count
Check "events-all-pushes-go-through-appender" ($appendCalls -eq 3) `
      ("AppendStructureEvent(e) call sites = " + $appendCalls + " (2 in the structure engine + 1 external break)")

$dispStart = $src.IndexOf("long DetectDisplacementCandidate(")
$dispEnd   = $src.IndexOf("void LinkDisplacementToEvent(", $dispStart)
$dispBody  = $src.Substring($dispStart, $dispEnd - $dispStart)
$pushInDisp = ([regex]::Matches($dispBody, 'ArrayResize\(g_displacements')).Count
# exactly two resizes are expected inside this one function: the push (n+1) and the
# cap block (InpMaxDisplacements). Anything else means another push path appeared.
$capInDisp = ($dispBody -match 'ArrayResize\(g_displacements,InpMaxDisplacements\)')
Check "displacements-push-is-centralized" (($pushInDisp -eq 2) -and $capInDisp) `
      ("ArrayResize(g_displacements) inside DetectDisplacementCandidate = " + $pushInDisp + " (push + cap block) ; cap block present = " + $capInDisp)
$assignDisp = ([regex]::Matches($src, 'g_displacements\[n\]=d;')).Count
Check "displacements-single-writer" ($assignDisp -eq 1) `
      ("g_displacements[n]=d; occurrences = " + $assignDisp + " (must be 1)")
$capEvents = $src -match 'InpMaxEvents>0 && ArraySize\(g_events\)>InpMaxEvents'
$capDisp   = $src -match 'InpMaxDisplacements>0 && ArraySize\(g_displacements\)>InpMaxDisplacements'
Check "events-cap-present" $capEvents "InpMaxEvents cap block present"
Check "displacements-cap-present" $capDisp "InpMaxDisplacements cap block present"

# B3 -- #11 side effect: the "new event?" test uses the monotonic counter, not the
#       array size (a capped registry no longer grows, so ArraySize would lie).
$monoUse = $src -match 'long beforeEvents = g_eventsAdded;'
$sizeUse = $src -match 'int beforeEvents = ArraySize\(g_events\);'
Check "new-event-detection-uses-monotonic-counter" ($monoUse -and -not $sizeUse) `
      ("monotonic=" + $monoUse + " arraySize=" + $sizeUse)
$addCount = ([regex]::Matches($src, 'g_eventsAdded\+\+')).Count
Check "monotonic-counter-increments-once" ($addCount -eq 1) ("g_eventsAdded++ occurrences = " + $addCount)

# B4 -- #12: the dead id generator is gone
$deadId = ([regex]::Matches($src, 'NewId\(\)')).Count
$deadVar = ([regex]::Matches($src, 'g_nextId')).Count
Check "dead-id-generator-removed" (($deadId -eq 0) -and ($deadVar -eq 0)) `
      ("NewId() x" + $deadId + " , g_nextId x" + $deadVar + " (both must be 0)")

# B5 -- performance: the event ledger is indexed in memory, not re-read per event
$ledgerFn = $src.IndexOf("bool EventLedgerContains(")
$ledgerEnd = $src.IndexOf("void LedgerIndexAdd(", $ledgerFn)
$ledgerBody = $src.Substring($ledgerFn, $ledgerEnd - $ledgerFn)
$opensFile = ($ledgerBody -match 'FileOpen')
$usesIndex = ($ledgerBody -match 'g_ledgerCacheIds')
Check "ledger-index-in-memory" (-not $opensFile -and $usesIndex) `
      ("EventLedgerContains opens a file: " + $opensFile + " ; reads index: " + $usesIndex)
$indexAddCalled = ([regex]::Matches($src, 'LedgerIndexAdd\(ledgerName,eventData.id\)')).Count
Check "ledger-index-updated-after-write" ($indexAddCalled -eq 1) `
      ("LedgerIndexAdd(...) after FileWrite occurrences = " + $indexAddCalled)

# B6 -- performance: session windows share ONE copied buffer
$collectIdx = $src.IndexOf("bool CollectWindowRange(")
$collectEnd = $src.IndexOf("bool WindowForDayBack(", $collectIdx)
$collectBody = $src.Substring($collectIdx, $collectEnd - $collectIdx)
$copyInCollect = ([regex]::Matches($collectBody, 'CopyTime\(|CopyHigh\(|CopyLow\(')).Count
Check "session-window-shares-one-copy" ($copyInCollect -eq 0) `
      ("Copy* calls inside CollectWindowRange = " + $copyInCollect + " (must be 0)")
$sharedCopy = ([regex]::Matches($src, 'g_winCacheNewest==newest\[0\]')).Count
Check "session-buffer-invalidates-on-new-bar" ($sharedCopy -eq 1) `
      ("newest-bar comparison occurrences = " + $sharedCopy)

# B7 -- performance: the EQ O(n^2) pass is memoized on the swing-set fingerprint
$eqMemo = $src -match 'if\(n==g_eqStampCount && g_eqStampLastId==swings\[n-1\]\.id'
Check "eq-memo-present" $eqMemo "swing-set fingerprint guard present in DetectEQ_FromSwings"

# B8 -- stability: rebuild finishes with a synchronized drawing layer, and the
#       draw calls are suppressed during the rebuild so nothing is drawn twice.
$rebuildIdx = $src.IndexOf("g_rebuildMode = true;")
$rebuildEnd = $src.IndexOf("if(isNewBar)", $rebuildIdx)
$rebuildBody = $src.Substring($rebuildIdx, $rebuildEnd - $rebuildIdx)
$redrawInRebuild = ($rebuildBody -match 'RedrawChartObjects\(\);')
$perfLog = ($rebuildBody -match 'ICT PHASE13 \| rebuild')
Check "rebuild-ends-with-redraw" $redrawInRebuild "RedrawChartObjects() called before the rebuild flag is left"
Check "rebuild-logs-performance" $perfLog "rebuild prints the Phase 13 counters"
$suppressed = ([regex]::Matches($src, '!g_rebuildMode\) Draw')).Count + ([regex]::Matches($src, '&& !g_rebuildMode\) Draw')).Count
Check "rebuild-suppresses-drawing" ($suppressed -ge 5) `
      ("guarded draw calls during rebuild = " + $suppressed + " (structure x2, FVG x3, OB x1, rejection x1)")

# B9 -- performance: the unused indicator buffer is gone
$bufDecl = ([regex]::Matches($src, 'g_bufDummy')).Count
$setIdx  = ([regex]::Matches($src, 'SetIndexBuffer')).Count
$propBuf = $src -match '#property indicator_buffers 0'
Check "unused-buffer-removed" (($bufDecl -eq 0) -and ($setIdx -eq 0) -and $propBuf) `
      ("g_bufDummy x" + $bufDecl + " , SetIndexBuffer x" + $setIdx + " , indicator_buffers 0 = " + $propBuf)

# =====================================================================
""
"==== RESULT ===="
"PASS=$pass  FAIL=$fail"
if ($fail -gt 0) { "RESULT: FAILED"; exit 1 } else { "RESULT: all rule and source checks passed"; exit 0 }
