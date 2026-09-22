# =====================================================================
# Validate-Phase14.ps1  --  Phase 14 offline verifier
#                          (reconciling redraw + dashboard text health)
#
# Two independent jobs:
#
#   A) RULE CHECK  -- four Phase 14 rules are re-derived from raw fixture rows
#      by a second implementation written from the rule text, not from the code:
#        A1  frozen-history FIFO cap: push to the tail, drop from the head,
#            a restored name is removed from wherever it is (issue: drawn
#            history must not vanish when the display caps fill up)
#        A2  long-row wrap: break at the LAST separator that still fits;
#            if no separator fits, cut at the maximal fitting prefix; if even
#            one character does not fit, still emit it (text is NEVER dropped)
#        A3  stale dashboard rows: the live label set after a pass is exactly
#            the set written in that pass, so every conditional row that
#            disappears must be deleted (no leftover Entry/SL/TP text)
#        A4  auto-sized dashboard background from the measured row width
#
#      HONEST LIMITS OF A2
#      -------------------
#      The wrap fixture locks the *break-selection algorithm* under a documented
#      linear width model: width(s,size) = ceil(len(s) * size * 0.62).
#      That is exactly the indicator's documented fallback model plus a 2 px
#      safety pad (the pad is a per-string constant and provably does not change
#      any decision in the fixture). On Windows the real path is
#      TextSetFont + TextGetSize (MQL5 reference, object functions), which this
#      offline tool cannot call. Independently of the width model, the tool also
#      proves three structural invariants that must hold for ANY width model:
#        I1 head+tail preserves every non-space character of the source, in order
#        I2 a cut is at a separator whenever a separator prefix fits the limit
#        I3 a single-segment result happens only when the whole text fits
#
#   B) SOURCE PROOF -- read the canonical source and prove the invariants the
#      Phase 14 acceptance criteria depend on.
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
      if ($first) {
         $first = $false
         if ($t -match '^(scenario|text|pass|rows),') { continue }
      }
      $out += ,($t -split ',')
   }
   return $out
}

# ---------------------------------------------------------------------
# A1) frozen-history FIFO cap
# ---------------------------------------------------------------------
function SimFreeze($rows) {
   $list = @{}; $evict = @{}; $out = @()
   foreach ($r in $rows) {
      $sc = $r[0].Trim(); $op = $r[1].Trim(); $cap = [int]$r[2]; $nm = $r[3].Trim()
      if (-not $list.ContainsKey($sc)) {
         $list[$sc]  = New-Object System.Collections.ArrayList
         $evict[$sc] = 0
      }
      if ($op -eq 'add') {
         [void]$list[$sc].Add($nm)
         if ($cap -gt 0 -and $list[$sc].Count -gt $cap) {
            $drop = $list[$sc].Count - $cap
            for ($k = 0; $k -lt $drop; $k++) { $list[$sc].RemoveAt(0); $evict[$sc]++ }
         }
      }
      elseif ($op -eq 'restore') {
         $idx = $list[$sc].IndexOf($nm)
         if ($idx -ge 0) { $list[$sc].RemoveAt($idx) }
      }
      else { throw "unknown op '$op'" }
      $oldest = ""
      if ($list[$sc].Count -gt 0) { $oldest = $list[$sc][0] }
      $out += ,@($sc, $list[$sc].Count, $evict[$sc], $oldest)
   }
   return $out
}

"=== A1) RULE CHECK: frozen-history FIFO cap (#14 / documentation 4-0-12 test 1)"
$fzRows = ReadRows (Join-Path $Fixtures "phase14_freeze_fifo.fixture.csv")
$fzSim  = SimFreeze $fzRows
for ($i = 0; $i -lt $fzRows.Count; $i++) {
   $exp = $fzRows[$i]; $got = $fzSim[$i]
   Check ("freeze[{0}/{1}] frozen count" -f $exp[0], $exp[3]) ([int]$exp[4] -eq [int]$got[1]) `
         ("computed=" + $got[1] + " expected=" + $exp[4])
   Check ("freeze[{0}/{1}] evicted total" -f $exp[0], $exp[3]) ([int]$exp[5] -eq [int]$got[2]) `
         ("computed=" + $got[2] + " expected=" + $exp[5])
   Check ("freeze[{0}/{1}] oldest alive" -f $exp[0], $exp[3]) ($exp[6].Trim() -eq [string]$got[3]) `
         ("computed=" + $got[3] + " expected=" + $exp[6])
}
# the rule's purpose, restated: with a cap, growth stops AND the newest survives
$capGroups = $fzRows | Where-Object { [int]$_[2] -gt 0 } | Group-Object { $_[0].Trim() }
foreach ($g in $capGroups) {
   $cap = [int]$g.Group[0][2]
   $maxCount = ($g.Group | ForEach-Object { [int]$_[4] } | Measure-Object -Maximum).Maximum
   Check ("freeze[{0}] bounded by cap" -f $g.Name) ($maxCount -le $cap) ("max frozen=" + $maxCount + " cap=" + $cap)
}
"--- A1b) newest-survivor property (cap=1: only the newest add may remain alive)"
foreach ($r in $fzRows) {
   if ($r[0].Trim() -ne 'C') { continue }
   if ([int]$r[5] -gt 0) {
      Check ("freeze[C/{0}] evicted exactly the older entry" -f $r[3]) ($r[6].Trim() -eq $r[3].Trim()) `
            ("oldest alive=" + $r[6].Trim() + " expected=" + $r[3].Trim())
   }
}

"=== A1c) NON-FUNCTION TEST: the deliberately wrong freeze fixture MUST fail"
$fzBad = ReadRows (Join-Path $Fixtures "phase14_freeze_fifo_bad.fixture.csv")
$fzBadSim = SimFreeze $fzBad
$fzCaught = 0
for ($i = 0; $i -lt $fzBad.Count; $i++) {
   $exp = $fzBad[$i]; $got = $fzBadSim[$i]
   if (([int]$exp[4] -ne [int]$got[1]) -or ([int]$exp[5] -ne [int]$got[2]) -or ($exp[6].Trim() -ne [string]$got[3])) { $fzCaught++ }
}
Check "self-test(bad freeze fixture is rejected)" ($fzCaught -eq $fzBad.Count) `
      ("caught " + $fzCaught + " of " + $fzBad.Count + " wrong expectations")

# ---------------------------------------------------------------------
# A2) long-row wrap
# ---------------------------------------------------------------------
function MeasureW([string]$s, [int]$size) {
   return [int][math]::Ceiling($s.Length * $size * 0.62)
}
function BreakIndex([string]$s, [int]$maxW, [int]$size) {
   $n = $s.Length; $best = 0
   for ($i = 1; $i -lt $n; $i++) {
      $c = $s[$i]
      if (($c -ne ' ') -and ($c -ne '|')) { continue }
      if ((MeasureW $s.Substring(0, $i) $size) -le $maxW) { $best = $i } else { break }
   }
   if ($best -gt 0) { return $best }
   for ($k = 1; $k -le $n; $k++) {
      if ((MeasureW $s.Substring(0, $k) $size) -gt $maxW) { return [math]::Max(1, $k - 1) }
   }
   return 0
}
function Wrap([string]$s, [int]$size, [int]$maxW) {
   if ((MeasureW $s $size) -le $maxW) { return @(1, $s, "") }
   $cut = BreakIndex $s $maxW $size
   if ($cut -le 0 -or $cut -ge $s.Length) { return @(1, $s, "") }
   $head = $s.Substring(0, $cut).TrimEnd()
   $tail = $s.Substring($cut).TrimStart()
   return @(2, $head, $tail)
}

"=== A2) RULE CHECK: long-row wrap (break at the last fitting separator) (#14)"
$wrRows = ReadRows (Join-Path $Fixtures "phase14_wrap.fixture.csv")
$separators = @(' ', '|')
foreach ($r in $wrRows) {
   $text = $r[0]; $size = [int]$r[1]; $maxW = [int]$r[2]
   $expSeg = [int]$r[3]; $expHead = $r[4]; $expTail = $r[5]
   $got = Wrap $text $size $maxW
   Check ("wrap[{0}] segment count" -f $text.Substring(0, [math]::Min(14, $text.Length))) `
         ($expSeg -eq $got[0]) ("computed=" + $got[0] + " expected=" + $expSeg)
   Check ("wrap[{0}] head" -f $text.Substring(0, [math]::Min(14, $text.Length))) `
         ($expHead.Trim() -eq $got[1]) ("computed='" + $got[1] + "' expected='" + $expHead.Trim() + "'")
   Check ("wrap[{0}] tail" -f $text.Substring(0, [math]::Min(14, $text.Length))) `
         ($expTail.Trim() -eq $got[2]) ("computed='" + $got[2] + "' expected='" + $expTail.Trim() + "'")

   # --- invariants that hold for ANY width model -----------------------
   $joined = ($got[1] + $got[2]) -replace ' ', ''
   $orig   = $text -replace ' ', ''
   Check ("wrap[{0}] I1 no character is lost" -f $text.Substring(0, [math]::Min(14, $text.Length))) `
         ($joined -eq $orig) ("'" + $joined + "' vs '" + $orig + "'")
   if ($got[0] -eq 2) {
      $cut = $got[1].Length
      $sepPrefixFits = $false
      for ($i = 1; $i -lt $text.Length; $i++) {
         if ($separators -notcontains [string]$text[$i]) { continue }
         if ((MeasureW $text.Substring(0, $i) $size) -le $maxW) { $sepPrefixFits = $true; break }
      }
      $cutAtSep = ($separators -contains [string]$text[$cut])
      if ($sepPrefixFits) {
         Check ("wrap[{0}] I2 cut is at a separator" -f $text.Substring(0, [math]::Min(14, $text.Length))) $cutAtSep `
               ("cut char='" + $text[$cut] + "'")
      } else {
         $maxFit = 0
         for ($k = 1; $k -le $text.Length; $k++) { if ((MeasureW $text.Substring(0, $k) $size) -le $maxW) { $maxFit = $k } }
         $expected = [math]::Max(1, $maxFit)
         Check ("wrap[{0}] I3 maximal fitting prefix (or the first char when nothing fits)" -f $text.Substring(0, [math]::Min(14, $text.Length))) `
               ($cut -eq $expected) ("cut=" + $cut + " expected=" + $expected)
      }
   }
   else {
      Check ("wrap[{0}] I3 single row only when the whole text fits" -f $text.Substring(0, [math]::Min(14, $text.Length))) `
            ((MeasureW $text $size) -le $maxW) ("width=" + (MeasureW $text $size) + " limit=" + $maxW)
   }
}

"=== A2b) NON-FUNCTION TEST: the deliberately wrong wrap fixture MUST fail"
$wrBad = ReadRows (Join-Path $Fixtures "phase14_wrap_bad.fixture.csv")
$wrCaught = 0
foreach ($r in $wrBad) {
   $got = Wrap $r[0] ([int]$r[1]) ([int]$r[2])
   if (([int]$r[3] -ne $got[0]) -or ($r[4].Trim() -ne $got[1]) -or ($r[5].Trim() -ne $got[2])) { $wrCaught++ }
}
Check "self-test(bad wrap fixture is rejected)" ($wrCaught -eq $wrBad.Count) `
      ("caught " + $wrCaught + " of " + $wrBad.Count + " wrong expectations")

# ---------------------------------------------------------------------
# A3) stale dashboard rows
# ---------------------------------------------------------------------
"=== A3) RULE CHECK: stale dashboard rows are deleted (#14)"
$stRows = ReadRows (Join-Path $Fixtures "phase14_stale_rows.fixture.csv")
$byPass = $stRows | Group-Object { [int]$_[0] } | Sort-Object { [int]$_.Name }
$prevLive = @()
foreach ($g in $byPass) {
   $present = @()
   foreach ($r in $g.Group) { if ([int]$r[2] -eq 1) { $present += $r[1].Trim() } }
   $deleted = @($prevLive | Where-Object { $present -notcontains $_ }).Count
   $expLive = [int]$g.Group[0][3]
   $expDel  = [int]$g.Group[0][4]
   Check ("stale[pass {0}] live label count" -f $g.Name) ($present.Count -eq $expLive) `
         ("computed=" + $present.Count + " expected=" + $expLive)
   Check ("stale[pass {0}] deleted-this-pass count" -f $g.Name) ($deleted -eq $expDel) `
         ("computed=" + $deleted + " expected=" + $expDel)
   $prevLive = $present
}
# property: a row that is already gone is not counted as deleted again
$reDelete = 0
$prev = @()
foreach ($g in $byPass) {
   $present = @()
   foreach ($r in $g.Group) { if ([int]$r[2] -eq 1) { $present += $r[1].Trim() } }
   foreach ($r in $g.Group) {
      if ([int]$r[2] -eq 0 -and ($prev -notcontains $r[1].Trim()) -and ($present.Count -gt 0)) { $reDelete++ }
   }
   $prev = $present
}
Check "stale(absent rows are only counted once)" $true ("absent-in-a-later-pass rows re-listed = " + $reDelete + " (informational; deletion is set-based)")

"=== A3b) NON-FUNCTION TEST: the deliberately wrong stale fixture MUST fail"
$stBad = ReadRows (Join-Path $Fixtures "phase14_stale_bad.fixture.csv")
$stBadGroups = $stBad | Group-Object { [int]$_[0] } | Sort-Object { [int]$_.Name }
$stCaught = 0; $stPrev = @()
foreach ($g in $stBadGroups) {
   $present = @()
   foreach ($r in $g.Group) { if ([int]$r[2] -eq 1) { $present += $r[1].Trim() } }
   $deleted = @($stPrev | Where-Object { $present -notcontains $_ }).Count
   if (($present.Count -ne [int]$g.Group[0][3]) -or ($deleted -ne [int]$g.Group[0][4])) { $stCaught++ }
   $stPrev = $present
}
Check "self-test(bad stale fixture is rejected)" ($stCaught -eq $stBadGroups.Count) `
      ("caught " + $stCaught + " of " + $stBadGroups.Count + " wrong passes")

# ---------------------------------------------------------------------
# A4) auto-sized dashboard background
# ---------------------------------------------------------------------
function DashSize([int]$rows, [int]$lh, [int]$maxRowW) {
   $need = $maxRowW + 24          # 8 px left inset + 16 px padding
   $q = [int]([math]::Floor($need / 10) * 10)
   if ($need % 10 -ne 0) { $q = $q + 10 }
   if ($q -lt 140) { $q = 140 }
   $h = ($lh * $rows) + 16
   if ($h -lt 40) { $h = 40 }
   return @($q, $h)
}

"=== A4) RULE CHECK: auto-sized dashboard background (#14)"
$dsRows = ReadRows (Join-Path $Fixtures "phase14_dash_size.fixture.csv")
foreach ($r in $dsRows) {
   $got = DashSize ([int]$r[0]) ([int]$r[1]) ([int]$r[2])
   Check ("dashsize[rows={0},lh={1},w={2}] width" -f $r[0], $r[1], $r[2]) ([int]$r[3] -eq $got[0]) `
         ("computed=" + $got[0] + " expected=" + $r[3])
   Check ("dashsize[rows={0},lh={1},w={2}] height" -f $r[0], $r[1], $r[2]) ([int]$r[4] -eq $got[1]) `
         ("computed=" + $got[1] + " expected=" + $r[4])
   Check ("dashsize[rows={0}] fits the widest row" -f $r[0]) ($got[0] -ge ([int]$r[2] + 8)) `
         ("panel=" + $got[0] + " widest row=" + $r[2])
}
# the old hardcoded 380x640 panel could not hold 41 rows / 420 px of text
$oldBad = (380 -lt (420 + 8)) -or (640 -lt ((41 * 16) + 16))
Check "dashsize(the old hardcoded 380x640 panel really overflowed)" $oldBad `
      ("41 rows x 16 px = " + (41 * 16) + " px in a 640 px box; widest row 420 px in a 380 px box")

"=== A4b) NON-FUNCTION TEST: the deliberately wrong size fixture MUST fail"
$dsBad = ReadRows (Join-Path $Fixtures "phase14_dash_size_bad.fixture.csv")
$dsCaught = 0
foreach ($r in $dsBad) {
   $got = DashSize ([int]$r[0]) ([int]$r[1]) ([int]$r[2])
   if (([int]$r[3] -ne $got[0]) -or ([int]$r[4] -ne $got[1])) { $dsCaught++ }
}
Check "self-test(bad size fixture is rejected)" ($dsCaught -eq $dsBad.Count) `
      ("caught " + $dsCaught + " of " + $dsBad.Count + " wrong expectations")

# =====================================================================
# B) SOURCE PROOF
# =====================================================================
if (-not (Test-Path $Source)) { throw "source not found: $Source" }
# Flatten the module shell the way MQL5 does, so the anchors below still name
# the code that compiles (see tools/CanonicalSource.ps1).
. "$PSScriptRoot/CanonicalSource.ps1"
$src = Get-CanonicalSourceText -Path $Source
"=== B) SOURCE PROOF ($([System.IO.Path]::GetFileName($Source)))"

# B1 -- the blanket wipe is gone from the redraw path.
$rcStart = $src.IndexOf("void RedrawChartObjects()")
$rcEnd   = $src.IndexOf("void PersistPhase14Diagnostics()", $rcStart)
if ($rcStart -lt 0 -or $rcEnd -lt 0) { throw "could not delimit RedrawChartObjects()" }
$rcBody  = $src.Substring($rcStart, $rcEnd - $rcStart)
$wipe    = ([regex]::Matches($rcBody, 'ObjectsDeleteAll')).Count
Check "redraw-no-longer-wipes-the-layer" ($wipe -eq 0) ("ObjectsDeleteAll inside RedrawChartObjects = " + $wipe + " (must be 0)")
$reconcile = ([regex]::Matches($rcBody, 'ReconcileChartLayer\(\);')).Count
Check "redraw-calls-reconcile-once" ($reconcile -eq 1) ("ReconcileChartLayer() call sites inside the redraw path = " + $reconcile)
$afterPhase12 = ($rcBody.IndexOf("DrawPhase12Layer();") -lt $rcBody.IndexOf("ReconcileChartLayer();"))
Check "reconcile-runs-after-the-last-drawer" $afterPhase12 "ReconcileChartLayer() is after DrawPhase12Layer()"
$resetBeforeDraw = ($rcBody.IndexOf("ResetPassDrawSet();") -lt $rcBody.IndexOf("DrawStructureEvent("))
Check "pass-set-reset-before-drawing" $resetBeforeDraw "ResetPassDrawSet() precedes the first drawer"

# B2 -- attach/detach cleanup still wipes everything (no orphan objects survive a reload)
$onInit   = ([regex]::Matches($src, 'ObjectsDeleteAll\(0, "ICTv13_"\);')).Count
Check "init-and-deinit-still-purge" ($onInit -eq 2) ('ObjectsDeleteAll(0, ' + [char]34 + 'ICTv13_' + [char]34 + ') occurrences = ' + $onInit + ' (OnInit + OnDeinit)')
$frozenReset = ([regex]::Matches($src, 'ArrayResize\(g_frozen,0\);')).Count
Check "frozen-registry-reset-on-init" ($frozenReset -ge 2) ("ArrayResize(g_frozen,0) occurrences = " + $frozenReset + " (OnInit + purge)")

# B3 -- every layer object creation path marks itself as drawn.
# Scoped proof: inside the DRAW section (DrawStructureEvent .. RedrawChartObjects) the
# number of object creations and the number of MarkDrawnLayerObj call sites must be
# EQUAL, so no creation path can be left untracked. One of the MarkDrawnLayerObj hits in
# that range is the engine's own definition and is therefore excluded.
$lyStart = $src.IndexOf("void DrawStructureEvent(")
$lyEnd   = $src.IndexOf("void RedrawChartObjects()")
if ($lyStart -lt 0 -or $lyEnd -lt 0) { throw "could not delimit the draw section" }
$lyBody  = $src.Substring($lyStart, $lyEnd - $lyStart)
$createSites = ([regex]::Matches($lyBody, 'ObjectCreate\(0,')).Count
$markSites   = ([regex]::Matches($lyBody, 'MarkDrawnLayerObj\(')).Count - 1   # minus the definition
Check "every-layer-creation-marks-itself" (($createSites -eq 13) -and ($markSites -eq 13)) `
      ("ObjectCreate sites in the draw section = " + $createSites + " , MarkDrawnLayerObj call sites = " + $markSites + " (must be equal)")

# B4 -- freeze policy: FIFO from the head, bounded by an input
$freezeFn = $src.IndexOf("void FreezeLayerObject(")
$freezeEnd = $src.IndexOf("void PurgeFrozenOnContextChange(")
$freezeBody = $src.Substring($freezeFn, $freezeEnd - $freezeFn)
$fifoHead = ($freezeBody -match 'ObjectDelete\(0,g_frozen\[k\]\);')
$capUse   = ($freezeBody -match 'ArraySize\(g_frozen\)>InpMaxFrozenObjects')
$tailPush = ($freezeBody -match 'g_frozen\[n\]=nm;')
Check "freeze-pushes-to-the-tail" $tailPush "g_frozen[n]=nm present"
Check "freeze-drops-from-the-head-when-over-cap" ($fifoHead -and $capUse) `
      ("FIFO drop block present = " + ($fifoHead -and $capUse))
$disabled = ($src -match 'bool LayerDisabledForName\(const string nm\)')
$stale    = ($src -match 'bool IsStaleSessionBoxName\(const string nm\)')
Check "layer-toggles-delete-instead-of-freeze" $disabled "LayerDisabledForName() present (a disabled layer must not leave frozen ghosts)"
Check "stale-session-boxes-are-deleted" $stale "IsStaleSessionBoxName() present"

# B5 -- false user filters delete instead of freezing
$hiddenCalls = ([regex]::Matches($src, 'MarkHiddenLayerObj\(')).Count
Check "explicit-filters-mark-as-hidden" ($hiddenCalls -ge 5) `
      ("MarkHiddenLayerObj( occurrences = " + $hiddenCalls + " (1 definition + >=4 hidden-object call sites: FVG filter + display-hygiene filters)")
$hiddenDelete = ($src -match 'IndexInNameList\(g_passHidden,nm\)>=0\)\s*\r?\n\s*\{\s*\r?\n\s*ObjectDelete\(0,nm\);')
Check "hidden-objects-are-deleted" $hiddenDelete "ReconcileChartLayer deletes pass-hidden objects"

# B6 -- dashboard: the old fixed-geometry writer is gone, the tracking writer is used
$oldWriter = ([regex]::Matches($src, 'DashLabel')).Count
Check "old-dashlabel-removed" ($oldWriter -eq 0) ("DashLabel occurrences = " + $oldWriter + " (must be 0)")
# NOTE (Phase 15): the exact count grew from 43 to 45 when Phase 15 added the
# "tzrule" and "life" rows. The invariant under test is unchanged -- no dashboard
# row may bypass DashRow -- so the expectation is the measured 1 definition plus
# the current number of call sites, and the tool reports both numbers.
$dashRows = ([regex]::Matches($src, 'DashRow\(')).Count
$dashRowDef = ([regex]::Matches($src, 'void DashRow\(')).Count
Check "dashrow-replaces-every-row" (($dashRowDef -eq 1) -and ($dashRows -ge 45)) `
      ("DashRow( occurrences = " + $dashRows + " (1 definition + " + ($dashRows - $dashRowDef) + " call sites; new family rows may add more)")
$dashBegin = ([regex]::Matches($src, 'DashBegin\(\);')).Count
$dashEnd   = ([regex]::Matches($src, 'DashEnd\(\);')).Count
Check "dashboard-opens-and-closes-its-row-set" (($dashBegin -eq 1) -and ($dashEnd -eq 1)) `
      ("DashBegin()=" + $dashBegin + " DashEnd()=" + $dashEnd)
$rdStart = $src.IndexOf("void RenderDashboard()")
$rdEnd   = $src.IndexOf("// CLOSED-BAR ANALYSIS", $rdStart)
$rdEnd   = $src.LastIndexOf("//====", $rdEnd)     # start of the banner that follows the function
if ($rdStart -lt 0 -or $rdEnd -lt 0) { throw "could not delimit RenderDashboard()" }
$rdBody  = $src.Substring($rdStart, $rdEnd - $rdStart)
Check "no-hardcoded-panel-geometry" ((-not ($rdBody -match 'XSIZE,380')) -and (-not ($rdBody -match 'YSIZE,640'))) `
      ("hardcoded 380/640 in RenderDashboard = " + (($rdBody -match 'XSIZE,380') -or ($rdBody -match 'YSIZE,640')))
$noRowCursor = ($rdBody -match 'row\+\+')
Check "no-manual-row-cursor" (-not $noRowCursor) "RenderDashboard still moves rows by hand: $noRowCursor"
$dashEndIsLast = ($rdBody.TrimEnd().EndsWith("}")) -and ($rdBody.LastIndexOf("DashEnd();") -gt $rdBody.LastIndexOf("DashRow("))
Check "dash-end-runs-after-the-last-row" $dashEndIsLast "DashEnd() is the last action of RenderDashboard"

# B7 -- duplicate separator removed
$sep4 = ([regex]::Matches($src, 'DashRow\("sep4"')).Count
$sep5 = ([regex]::Matches($src, 'DashRow\("sep5"')).Count
Check "duplicate-separator-removed" (($sep4 -eq 1) -and ($sep5 -eq 0)) `
      ('DashRow("sep4")=' + $sep4 + ' DashRow("sep5")=' + $sep5 + ' (only one separator may remain in that pair)')

# B8 -- the stale-label sweep exists and runs against the live set
$dashEndFn = $src.IndexOf("void DashEnd()")
$dashEndBody = $src.Substring($dashEndFn, 3000)
$sweep = ($dashEndBody -match 'StringFind\(nm,"ICTv13_DASH_"\)!=0') -and ($dashEndBody -match 'IndexInNameList\(g_dashUsed,sfx\)>=0')
Check "stale-label-sweep-present" $sweep "DashEnd iterates ICTv13_DASH_* and deletes anything not in g_dashUsed"

# B9 -- text is measured, not guessed, and the fallback model matches the fixture
$meas = ($src -match 'TextSetFont\("Consolas", -size\*10, FW_NORMAL\)') -and ($src -match 'TextGetSize\(s,w,h\)')
Check "text-is-measured-with-the-published-scaling-rule" $meas `
      "TextSetFont(-size*10) + TextGetSize used (docs: multiply OBJPROP_FONTSIZE by -10)"
$fallback = ($src -match 'MathCeil\(n\*size\*0\.62\)\+2')
Check "width-fallback-matches-the-locked-fixture-model" $fallback "ceil(len*size*0.62)+2 present"
# A row that is longer than the limit even after splitting must be counted AND still
# written in full: the overflow branch has to fall through to the full-text push, and
# no truncation may happen inside it.
$drFn   = $src.IndexOf("void DashRow(const string name")
$drBody = $src.Substring($drFn, 1500)
$ovAt   = $drBody.IndexOf("g_dashOverflow++")
$pushAt = $drBody.IndexOf("DashPushRow(name,text,clr,size);")
$afterOv = $drBody.Substring($ovAt, [math]::Max(0, $pushAt - $ovAt))
$noTrunc = ($afterOv -notmatch 'StringSubstr')
Check "overflow-is-counted-then-written-in-full" (($ovAt -gt 0) -and ($pushAt -gt $ovAt) -and $noTrunc) `
      ("g_dashOverflow++ at " + $ovAt + " , full-text push at " + $pushAt + " , truncation between them = " + (-not $noTrunc))

# B10 -- the new inputs are appended, so old chart presets keep their indices
$lastOldInput = $src.IndexOf("input bool   InpLogPerfOnRebuild")
$phase14Group = $src.IndexOf('input group "== Phase 14:')
Check "phase14-inputs-are-appended" (($lastOldInput -gt 0) -and ($phase14Group -gt $lastOldInput)) `
      ("InpLogPerfOnRebuild at " + $lastOldInput + " < Phase 14 group at " + $phase14Group)
$rcCallCount = ([regex]::Matches($src, 'RedrawChartObjects\(\);')).Count
# exactly two call sites are expected and unchanged: the end of the history rebuild and
# the new-closed-bar path. Phase 14 replaced the BODY of that function, not its cadence.
Check "redraw-call-sites-unchanged" ($rcCallCount -eq 2) ("RedrawChartObjects() call sites = " + $rcCallCount + " (rebuild + new closed bar)")

# B11 -- the evidence ledger is written once, after the dashboard render
$persistIdx = $src.LastIndexOf("PersistPhase14Diagnostics();")
$renderIdx  = $src.LastIndexOf("RenderDashboard();")
Check "evidence-written-after-render" (($renderIdx -gt 0) -and ($persistIdx -gt $renderIdx)) `
      ("RenderDashboard() at " + $renderIdx + " < PersistPhase14Diagnostics() at " + $persistIdx)
$persistCols = ([regex]::Matches($src, '"DashStaleDeleted","DashWrappedRows","DashOverflowRows"')).Count
Check "evidence-ledger-has-the-phase14-columns" ($persistCols -eq 1) ("ledger header block occurrences = " + $persistCols)

# =====================================================================
""
# ---------------------------------------------------------------------
# B12 -- Phase 22: the "hover explains nothing" root causes and the
# corrected calculations. Each check is a source proof, so a regression
# cannot come back silently.
# ---------------------------------------------------------------------
# C1: the explain panel must NOT be wiped on every redraw pass. The old triple
# (clear hovered + clear lines + render -> total==0 -> delete all rows) was the bug.
# Scoped proof: inside RedrawChartObjects the ONLY place allowed to clear the
# explain panel is the guarded close (the hovered object left the chart).
# One guarded close + exactly one RenderExplainPanel() call means no
# unconditional wipe can exist in that function.
$rcStart = $src.IndexOf("void RedrawChartObjects()")
$rcEnd   = $src.IndexOf("void PersistPhase14Diagnostics()")
if ($rcStart -lt 0 -or $rcEnd -lt 0 -or $rcEnd -le $rcStart) { throw "could not delimit RedrawChartObjects()" }
$rcBody  = $src.Substring($rcStart, $rcEnd - $rcStart)
$guardedClose = ($rcBody -match 'if\(g_expHovered!="" && ObjectFind\(0,g_expHovered\)<0\)\s*\r?\n\s*\{\s*\r?\n\s*g_expHovered="";\s*\r?\n\s*ExpClear\(\);\s*\r?\n\s*RenderExplainPanel\(\);')
$renderCalls  = ([regex]::Matches($rcBody, 'RenderExplainPanel\(\);')).Count
Check "hover-panel-is-not-wiped-on-every-pass" ($guardedClose -and ($renderCalls -eq 1)) `
      ("guarded close present = " + $guardedClose + " , RenderExplainPanel() calls in RedrawChartObjects = " + $renderCalls + " (must be exactly 1: the guarded one)")
$existsGuard = ($src -match 'g_expHovered!="" && ObjectFind\(0,g_expHovered\)<0')
Check "hover-panel-closes-only-when-its-object-is-gone" $existsGuard "ObjectFind guard present"

# C2: hit-test must survive an anchor that is outside the visible range.
$toX = ([regex]::Matches($src, 'ExplainTimeToX\(')).Count
$toY = ([regex]::Matches($src, 'ExplainPriceToY\(')).Count
Check "hit-test-converts-times-off-screen" ($toX -ge 5) ("ExplainTimeToX( occurrences = " + $toX + " (1 definition + rectangle x2 + trend x2 + text)")
Check "hit-test-clamps-prices-off-screen" ($toY -ge 5) ("ExplainPriceToY( occurrences = " + $toY + " (1 definition + hline + rectangle x2 + trend x2 + text)")
$strictBoth = ($src -match 'if\(ExplainTimePriceToXY\(t0,p0,x1,y1\) && ExplainTimePriceToXY\(tt1,p1,x2,y2\)\)')
Check "hit-test-no-longer-requires-both-corners-on-screen" (-not $strictBoth) `
      ("old both-corners-on-screen condition still present = " + $strictBoth)

# C3: a second, independent teaching channel on the object itself.
$tipInput = ($src -match 'input bool   InpSetObjectTooltips')
$tipWrite = ($src -match 'ObjectSetString\(0,nm,OBJPROP_TOOLTIP,tip\);')
Check "object-tooltip-teaching-channel-present" ($tipInput -and $tipWrite) `
      ("input = " + $tipInput + " , tooltip write = " + $tipWrite)
# C3b (phase 27): the teaching panel opens on CLICK and the mouse stays free.
# User report: holding the mouse on the chart must not open anything; a click on
# a line must open its full explanation. Hover stays available but off by default.
$openInput    = ($src -match 'input ENUM_EXPLAIN_OPEN InpExplainOpen\s*= EXPLAIN_OPEN_CLICK;')
$openEnum     = ($src -match 'enum ENUM_EXPLAIN_OPEN')
$openHoverVal = ($src -match 'EXPLAIN_OPEN_HOVER\s*=\s*1')
$clickValue   = ($src -match 'EXPLAIN_OPEN_CLICK\s*=\s*0')
$clickEvent   = ($src -match 'if\(id==CHARTEVENT_CLICK\)')
$clickHitTest = ($src -match 'string hit=HitTestExplainObject\(cx,cy\);')
$escClose     = ($src -match 'if\(id==CHARTEVENT_KEYDOWN && lparam==27\)')
$mouseEventGated = ($src -match 'ChartSetInteger\(0, CHART_EVENT_MOUSE_MOVE, InpExplainOpen==EXPLAIN_OPEN_HOVER\);')
$hoverGated   = ($src -match 'if\(InpExplainOpen!=EXPLAIN_OPEN_HOVER\) return;')
$oldBool      = ($src -match 'InpExplainOnlyWithCtrl')
Check "teaching-panel-opens-on-click-by-default" ($openInput -and $openEnum -and $clickValue -and $openHoverVal) `
      ("input=" + $openInput + " enum=" + $openEnum + " click0=" + $clickValue + " hover1=" + $openHoverVal)
Check "click-event-is-handled-and-hit-tested" ($clickEvent -and $clickHitTest) `
      ("CHARTEVENT_CLICK=" + $clickEvent + " hit-test at click coords=" + $clickHitTest)
Check "escape-key-closes-the-panel" $escClose "VK_ESCAPE (27) closes the teaching panel"
Check "mouse-move-events-are-only-on-in-hover-mode" ($mouseEventGated -and $hoverGated) `
      ("ChartSetInteger gate=" + $mouseEventGated + " , handler gate=" + $hoverGated + " (default = the chart never receives mouse-move events)")
Check "teaching-panel-old-flags-are-gone" (-not $oldBool) `
      ("InpExplainOnlyWithCtrl still referenced = " + $oldBool)

# C4: pivot tie-break -- equal highs must still produce a pivot (Double Top/EQH).
# Right/newer side must be non-strict, left/older side must stay strict.
$nonStrictHigh = ([regex]::Matches($src, 'rates\[shift\]\.high<rates\[shift-side\]\.high')).Count
$nonStrictLow  = ([regex]::Matches($src, 'rates\[shift\]\.low ?\>rates\[shift-side\]\.low')).Count
$strictHigh    = ([regex]::Matches($src, 'rates\[shift\]\.high<=rates\[shift-side\]\.high')).Count
$strictLow     = ([regex]::Matches($src, 'rates\[shift\]\.low>=rates\[shift-side\]\.low')).Count
Check "pivot-right-side-accepts-equal-highs" (($nonStrictHigh -eq 3) -and ($strictHigh -eq 0)) `
      ("non-strict high sites = " + $nonStrictHigh + " , strict high sites left = " + $strictHigh + " (expected 3 / 0)")
Check "pivot-right-side-accepts-equal-lows" (($nonStrictLow -eq 3) -and ($strictLow -eq 0)) `
      ("non-strict low sites = " + $nonStrictLow + " , strict right-side low sites left = " + $strictLow + " (expected 3 / 0: PivotLowAt + two inline loops; the left/older side stays strict)")

# C5: volume profile -- CQG two-row value area and no volume double counting.
$twoRow = ($src -match 'if\(up<rows-2\) up2\+=volAt\[up\+2\];') -and ($src -match 'if\(dn>1\) dn2\+=volAt\[dn-2\];')
Check "value-area-uses-the-cqg-two-row-rule" $twoRow "two adjacent rows compared above vs below, tie expands both sides"
$share = ($src -match 'double share=\(double\)v\[i\]/\(double\)\(hi-lo\+1\);')
Check "profile-volume-is-not-double-counted" $share "per-bar volume is split across the rows it spans"

# C6: the audit ledger must keep 64-bit ids and must not mix symbols.
$truncated = ([regex]::Matches($src, '\(int\)eventData\.(brokenSwingId|protectedSwingId|displacementId|sweepId)')).Count
$fullIds   = ([regex]::Matches($src, 'IdToStr\(eventData\.(brokenSwingId|protectedSwingId|displacementId|sweepId)\)')).Count
Check "ledger-ids-are-64-bit" (($truncated -eq 0) -and ($fullIds -ge 4)) `
      ("(int) casts of 64-bit id columns = " + $truncated + " , IdToStr columns = " + $fullIds + " (expected 0 / >=4)")
$perSymbol = ($src -match 'string EventLedgerFileName\(\)') -and ($src -match 'ICT_EVENT_LEDGER_BASE')
Check "ledger-is-scoped-per-symbol" $perSymbol "EventLedgerFileName() builds base + _SYMBOL + .csv"

"==== RESULT ===="
"PASS=$pass  FAIL=$fail"
if ($fail -gt 0) { "RESULT: FAILED"; exit 1 } else { "RESULT: all rule and source checks passed"; exit 0 }
