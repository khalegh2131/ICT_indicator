# =====================================================================
# Validate-Phase44.ps1  --  the click path must always answer
#
# WHY THIS EXISTS
# ---------------
# The promise of this project is that every object on the chart explains
# itself: what it is, why it formed, what makes it right, what makes it
# fake. Every validator until now proved *text* properties of the source.
# None of them could see the click path, because the click path has three
# runtime stages:
#
#   1. pixel hit-test      -- price/time -> pixel, pick the object
#   2. registry lookup     -- the id inside the object name -> the record
#   3. explanation build   -- the panel text for that record
#
# Any of the three can fail silently. Measured before this phase, from the
# live diagnostic file: exactly one drawn object (the corner risk strip,
# ICTv13_RSTRIP_TXT) resolved to the generic fallback, and every family
# branch that missed its registry entry returned with no title and no lines
# at all, which leaves the panel EMPTY -- the worst outcome, because the
# user cannot tell whether the click missed or the code is broken.
#
# This tool locks the three stages:
#
#   A) COMPLETENESS (static) -- every object-name family the drawing code
#      can create is either handled in the dispatch chain or declared in
#      the exclusion list below. A new family that forgets to wire its
#      explanation turns this tool red, which is the point.
#   B) NO SILENT EMPTY (static) -- the dispatch must announce "not in
#      registry" instead of returning silently, and BuildExplanation must
#      guarantee a title plus at least one line for anything it is given.
#   C) DETERMINISM (static) -- the overlap tie-break must be explicit
#      (distance, then smallest area, then name) instead of depending on
#      the order ObjectsTotal happens to enumerate.
#   D) RUNTIME EVIDENCE -- the indicator writes
#      ICT_Assistant_Canonical_Click_Diag.csv from an automatic test that
#      drives the real hit-test and the real panel builder for every
#      clickable object on the chart, without a mouse. This section reads
#      that report and requires zero objects with no handler.
#
# The runtime report distinguishes two kinds of fallback on purpose:
#   NO_HANDLER     -- no explanation exists for that family  (a defect)
#   REGISTRY_MISS  -- the record was evicted by a retention cap while the
#                     object stayed on the chart as display history. That
#                     is a designed state, and it is now explained to the
#                     user instead of showing a blank panel.
#
# Read-only. No build. No writes except stdout.
# =====================================================================
param(
   [string]$Source = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5",
   [string]$Report = "$env:APPDATA/MetaQuotes/Terminal/Common/Files/ICT_Assistant_Canonical_Click_Diag.csv"
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

Write-Output "=== Phase 44 -- click path: every object answers with name and reason ==="
Write-Output ""

if (-not (Test-Path -LiteralPath $Source)) { throw "Canonical source not found: $Source" }
. "$PSScriptRoot/CanonicalSource.ps1"
$src = Get-CanonicalSourceText -Path $Source

# ---------------------------------------------------------------------
# A) COMPLETENESS -- every drawn family is wired to an explainer
# ---------------------------------------------------------------------
Write-Output "--- A) every object family can be explained ---"

# The panel and the dashboard are readouts, not analysis layers: the hit test
# deliberately ignores them, so they need no family explainer.
# Phase 48 added PEND_BG / PEND_TXT to this list: those two objects of the removed
# separate "pending" row are now only ever DELETED (CleanupLegacyPendingRow), never
# created, so there is nothing to explain and no family to dispatch.
$excluded = @('DASH_', 'EXP_', 'RSTRIP_BG', 'PEND_BG', 'PEND_TXT')

# families created by the drawing code
$created = [regex]::Matches($src, '"ICTv13_([A-Za-z0-9_]+)"') |
   ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
# some names are built as "ICTv13_FVG_"+id : capture those too
$created += [regex]::Matches($src, '"ICTv13_([A-Za-z0-9_]+)_"\+') | ForEach-Object { $_.Groups[1].Value + '_' }
$created = $created | Sort-Object -Unique

# families the dispatch chain knows about
$dispatchBody = [regex]::Match($src, '(?s)void ExplainDispatchObject\(string objName\).*?\n\}').Value
$handled = [regex]::Matches($dispatchBody, 'StringFind\(body,"([A-Za-z0-9_]+)"') |
   ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

$unhandled = @()
foreach ($c in $created) {
   if ([string]::IsNullOrWhiteSpace($c)) { continue }
   $isExcluded = $false
   foreach ($ex in $excluded) { if ($c.StartsWith($ex) -or $ex.StartsWith($c)) { $isExcluded = $true; break } }
   if ($isExcluded) { continue }
   $ok = $false
   foreach ($hnd in $handled) { if ($c.StartsWith($hnd)) { $ok = $true; break } }
   if (-not $ok) { $unhandled += $c }
}
Check "A1_EVERY_DRAWN_FAMILY_HAS_AN_EXPLAINER" ($unhandled.Count -eq 0) `
   ("created families = {0}; handled = {1}; unhandled = [{2}]" -f $created.Count, ($handled -join ','), ($unhandled -join ','))

Check "A2_RISK_STRIP_EXPLAINED" ($dispatchBody -match 'StringFind\(body,"RSTRIP"\)') `
   "the corner risk strip has its own explainer (before this phase it fell through to the generic message; measured in the live report)"
Check "A3_RISK_STRIP_TEXT_PRESENT" ($src -match 'void\s+ExplainRiskStripObject\s*\(') `
   "ExplainRiskStripObject() is defined"

# ---------------------------------------------------------------------
# B) NO SILENT EMPTY PANEL
# ---------------------------------------------------------------------
Write-Output ""
Write-Output "--- B) no click may leave the panel empty ---"

$missDefs = [regex]::Matches($src, 'void\s+ExplainRegistryMiss\s*\(').Count
Check "B1_REGISTRY_MISS_HELPER_DEFINED_ONCE" ($missDefs -eq 1) ("ExplainRegistryMiss definitions = {0}" -f $missDefs)

$missElse = [regex]::Matches($src, 'else\s+ExplainRegistryMiss\(').Count
Check "B2_FAMILY_BRANCHES_ANNOUNCE_EVICTION" ($missElse -ge 6) `
   ("branches that explain an evicted record instead of returning silently = {0} (LIQ, SWEEP, EVT, FVG, OB, REJECTION)" -f $missElse)

Check "B3_BUILD_EXPLANATION_DELEGATES" `
   ($src -match '(?s)void BuildExplanation\(string objName\)\s*\{\s*\n\s*g_clickResolve=ExplainBuildDetailed\(objName\);') `
   "BuildExplanation routes through ExplainBuildDetailed, so the guarantee applies to every caller"
Check "B4_GUARANTEE_FILLS_EMPTY_RESULTS" `
   ($src -match '(?s)ENUM_CLICK_RESOLVE ExplainBuildDetailed\(string objName\)\s*\{\s*\n.*?if\(ArraySize\(g_expLines\)==0\).*?ExplainUnknownObject\(objName\);\s*\n\s*ExplainFrozenNote\(objName\);\s*\n\s*return CLICK_RS_FALLBACK;') `
   "an empty result is replaced by the fallback message (title plus reasons), never returned as-is"
Check "B5_TITLE_NEVER_EMPTY" `
   ($src -match 'if\(g_expTitle==""\) g_expTitle="OBJECT "\+') `
   "a missing title is derived from the object name, so the panel header always identifies the click"
Check "B6_REASON_IS_CLASSIFIED" `
   (($src -match 'g_clickReason="REGISTRY_MISS";') -and ($src -match 'g_clickReason="NO_HANDLER";') -and ($src -match 'g_clickReason="RESOLVED";')) `
   "each resolution records whether it resolved, missed the registry, or had no handler"
Check "B7_SAVED_CSV_USES_THE_SAME_PATH" `
   ($src -match '(?s)void ExplainSaveCsv\(\).*?ExpClear\(\);\s*\n\s*BuildExplanation\(nm\);') `
   "the explanation CSV runs the same builder as the click, so the file and the panel cannot drift"

# ---------------------------------------------------------------------
# C) DETERMINISM in overlap
# ---------------------------------------------------------------------
Write-Output ""
Write-Output "--- C) the overlap tie-break is explicit ---"
$hitBody = [regex]::Match($src, '(?s)string HitTestExplainObject\(int mx, int my\).*?\n\}').Value
Check "C1_TIEBREAK_BY_AREA_THEN_NAME" `
   (($hitBody -match 'bestArea') -and ($hitBody -match 'nm<best') -and ($hitBody -match 'area=\(xR-xL\)')) `
   "selection is distance, then smallest bounding box, then name order (previously the first enumerated match won)"
Check "C2_OVERLAPS_DOCUMENTED" ($hitBody -match '(?s)\u0641\u0627\u0632 \u06f4\u06f4 \u2014 \u0642\u0627\u0639\u062f\u0647\u0654 \u0642\u0637\u0639\u06cc' -or $hitBody -match 'bestArea=1e18') `
   "the rule is stated in the source next to the loop"

# ---------------------------------------------------------------------
# D) the automatic test is wired and runs on real data
# ---------------------------------------------------------------------
Write-Output ""
Write-Output "--- D) the automatic click test is wired ---"
Check "D1_TEST_DEFINED_ONCE" (([regex]::Matches($src, 'void\s+RunClickPathSelfTest\s*\(')).Count -eq 1) `
   "RunClickPathSelfTest is defined exactly once"
Check "D2_TEST_CALLED_ONCE_AFTER_REDRAW" `
   ($src -match '(?s)RedrawChartObjects\(\);\s*\n\s*PROBE_END\("6\.firstRedraw",rd0\);.*?RunClickPathSelfTest\(\);') `
   "called at the end of the history rebuild, i.e. after the objects are drawn"
Check "D3_TEST_DRIVES_THE_LIVE_PATH" `
   (($src -match '(?s)void RunClickPathSelfTest\(\).*?HitTestExplainObject\(') -and ($src -match '(?s)void RunClickPathSelfTest\(\).*?ExplainBuildDetailed\(')) `
   "the test calls the production hit-test and the production panel builder, not a copy"
Check "D4_TEST_USES_SHARED_PIXEL_HELPERS" `
   ($src -match '(?s)bool ClickTestCenterOf.*?ExplainTimeToX\(') `
   "the centre pixel is computed with the same helpers the hit test uses, so the two cannot drift"
Check "D5_TEST_WRITES_NAMED_REPORT" ($src -match 'ICT_Assistant_Canonical_Click_Diag\.csv') `
   "report file name is present in the source"
Check "D6_TEST_INPUT_DECLARED" ($src -match 'input\s+bool\s+InpRunClickPathSelfTest\s*=') `
   "input InpRunClickPathSelfTest declared"
Check "D7_TEST_LEAVES_PANEL_CLEAN" `
   ($src -match '(?s)void RunClickPathSelfTest\(\).*?g_expHovered="";\s*\n\s*ExpClear\(\);') `
   "the test clears the panel and the hover state when it finishes"

Write-Output ""
Write-Output "--- D8) runtime report from the indicator ---"
if (-not (Test-Path -LiteralPath $Report)) {
   Pending "D8A_CLICK_REPORT_PRESENT" ("not found yet: {0}  (reload the indicator once, then re-run)" -f $Report)
} else {
   $bytes = [System.IO.File]::ReadAllBytes($Report)
   $enc = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [System.Text.Encoding]::Unicode }
          else { New-Object System.Text.UTF8Encoding($false) }
   $lines = ($enc.GetString($bytes)) -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 }
   $header = $lines[0] -split ';'
   $iReason = [array]::IndexOf($header, 'Reason')
   $iLines  = [array]::IndexOf($header, 'Lines')
   $iObj    = [array]::IndexOf($header, 'Object')
   $iSelf   = [array]::IndexOf($header, 'HitIsSelf')
   $iOnScr  = [array]::IndexOf($header, 'OnScreen')
   $iHit    = [array]::IndexOf($header, 'HitObject')

   $rows = @()
   for ($i = 1; $i -lt $lines.Count; $i++) {
      $c = $lines[$i] -split ';'
      if ($c.Count -le $iHit) { continue }
      $rows += [pscustomobject]@{
         Object = $c[$iObj]; Reason = $c[$iReason]; Lines = $c[$iLines]
         OnScreen = $c[$iOnScr]; Hit = $c[$iHit]; Self = $c[$iSelf]
      }
   }
   Check "D8A_CLICK_REPORT_PRESENT" ($rows.Count -gt 0) ("rows = {0}" -f $rows.Count)

   $noHandler = @($rows | Where-Object { $_.Reason -eq 'NO_HANDLER' })
   Check "D8B_NO_OBJECT_WITHOUT_HANDLER" ($noHandler.Count -eq 0) `
      ("objects whose family has no explainer = {0} [{1}]" -f $noHandler.Count, (($noHandler | ForEach-Object { $_.Object }) -join ','))

   $emptyLines = @($rows | Where-Object { [int]$_.Lines -le 0 })
   Check "D8C_NO_EMPTY_PANEL" ($emptyLines.Count -eq 0) `
      ("objects that produced zero explanation lines = {0} [{1}]" -f $emptyLines.Count, (($emptyLines | ForEach-Object { $_.Object }) -join ','))

   $resolved  = @($rows | Where-Object { $_.Reason -eq 'RESOLVED' }).Count
   $missed    = @($rows | Where-Object { $_.Reason -eq 'REGISTRY_MISS' }).Count
   Write-Output ("INFO   resolved by specialist explainer = {0} / {1} ; explained as evicted-from-registry = {2}" -f $resolved, $rows.Count, $missed)

   $onScreen = @($rows | Where-Object { $_.OnScreen -eq '1' })
   $missHit  = @($onScreen | Where-Object { $_.Hit -eq '' })
   Check "D8D_CENTRE_CLICK_ALWAYS_FINDS_AN_OBJECT" ($missHit.Count -eq 0) `
      ("objects whose own centre pixel found no object = {0} of {1} on-screen [{2}]" -f $missHit.Count, $onScreen.Count, (($missHit | ForEach-Object { $_.Object }) -join ','))

   $selfHit = @($onScreen | Where-Object { $_.Self -eq '1' }).Count
   Write-Output ("INFO   centre click landed on the object itself = {0} of {1} on-screen (the rest are overlaps; the tie-break rule decides those, see section C)" -f $selfHit, $onScreen.Count)
}

Write-Output ""
if ($pending -gt 0) {
   Write-Output ("RESULT: PASS={0} FAIL={1} PENDING={2} (sections A-C are proved from source; section D8 needs one indicator reload)" -f $pass, $fail, $pending)
} else {
   Write-Output ("RESULT: PASS={0} FAIL={1}" -f $pass, $fail)
}
if ($fail -gt 0) { exit 1 }
exit 0
