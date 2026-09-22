# =====================================================================
# Verify-ModuleSplit.ps1  --  the anti-drift gate for the module split
#
#   The canonical indicator was one 11,068-line file. It is now a shell plus
#   30 per-family modules. That refactor is only trustworthy if the compiled
#   translation unit is *provably* unchanged, so this tool reassembles the
#   shell + modules exactly the way the MQL5 preprocessor does and compares
#   the bytes with the frozen pre-split source.
#
#   WHAT IT PROVES
#     1. Byte identity: shell header + the included modules, in include order,
#        hash to the frozen reference SHA256. Nothing was lost, reordered,
#        re-indented or silently rewritten - including line endings.
#   #        The reference hash is the reviewed source, not "the pre-split file
   #        forever". It started as the pre-split monolith (13A34E6B..., pure
   #        refactor, zero logic change). Re-frozen twice:
   #
   #        * phase 40 (25D59CEC...) when the timeframe-change crash was fixed on purpose:
#        a smaller copy (CopyTickVolume / CopyHigh / CopyBuffer can return
#        fewer bars than requested right after a TF switch) was indexed by a
#        rebuild shift, which aborted every OnCalculate pass and left the
#        chart empty. Re-freezing is a deliberate act and must be justified by
#        an external diff, never by simply editing this constant:
#
#          git show <pre-change-commit>:01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5 > /tmp/before.mq5
#          powershell -File tools/CanonicalSource.ps1 ... (or use -ReferencePath)   #          diff -u /tmp/before.mq5 /tmp/assembled.mq5     # must show ONLY the intended change
   #
   #        * phase 41 (B22B2294...) when the Persian explanation panel was made
   #          readable: RtlSafe() was rewritten to move only *Latin-letter* tokens
   #          to the head of a line (digits stay in place - they do not split an
   #          RTL run), the panel path emits through it, RenderLine() mode 0 pins
   #          the paragraph direction with U+200F, and the FVG family's teaching
   #          text was rewritten so no English word sits inside a Persian sentence.
   #          Proof used: tools/Assemble-Canonical.ps1 over the frozen package
   #          mirror reproduced 25D59CEC..., and diff -u of that against the new
   #          assembly showed exactly 8 hunks, all of them the edits above.   #        * phase 43 (37C28223...) when the FVG inversion rule stopped rewriting
   #          the zone's birth direction. `direction` now always means "the
   #          direction the gap was born with" (the geometry, the zone id and the
   #          chart object name are built from it) and the current role is derived
   #          through FVGActiveDir() / OBActiveDir(), with one shared report string
   #          for the panel and the diagnostic CSV. Before the fix one field carried
   #          two meanings, so a purple inverted box could be reported bullish by
   #          the CSV, bearish by the setup selector and neither by the panel.
   #          Proof used: Assemble-Canonical.ps1 over the phase-42 tree was
   #          byte-identical to the tree at the start of this phase (F6453447...),
   #          and diff -u of that assembly against the new one showed only the
   #          intended hunks: the new struct field, the two helpers, the two
   #          inversion branches, the seven polarity call sites, the FVG panel and
   #          OB panel titles, the diagnostic CSV header/row, the new harness
   #          suite and its call. No condition or arithmetic other than the
   #          polarity selections themselves.
   #        * phase 42 (D1A0CBC7...) when the teaching text of every remaining
#          family was rewritten so no English word sits inside a Persian
#          sentence and every panel row is short: Persian twins were added for
#          the coded values that used to be substituted mid-sentence (timeframe,
#          direction, liquidity type, OB/rejection/exhaustion/trend/POI/entry
#          model/RTM/S-D/Wyckoff/AMT day and open types), the setup status and
#          leg-reject codes became Latin-only (the panel prints them on their
#          own line and explains them in Persian), and the Wyckoff phase reasons
#          lost their Latin words. Proof used: Assemble-Canonical.ps1 over the
#          phase-41 package mirror reproduced B22B2294... byte-for-byte, and
#          diff -u of that against the new assembly showed 13 hunks, all inside
#          06_MultiTimeframe, 19_SetupEngine, 24_RedrawReconcile and
#          26_PersianRender - the four modules this phase touched.
#
#     2. Nothing hides after the last include: the shell's trailing content
#        may only be blank lines or // comments, so no code can be smuggled
#        in outside the module tree.
#     3. The file list and the compiled unit cannot drift: every .mqh on disk
#        must be referenced by an include, and every include must resolve.
#     4. Each module still opens with a section banner, so a module file is
#        recognisably a strategy family rather than an arbitrary chunk.
#
#   WHY BYTES AND NOT TEXT
#     PowerShell text cmdlets normalise line endings (Set-Content writes CRLF
#     on Windows) and can add or drop a BOM. The source is pure LF with a BOM,
#     so a text round-trip would corrupt it invisibly. Everything here is
#     byte-level on purpose.
#
#   To diff against the original instead of trusting a hash, extract it first:
#     git show <commit>:01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5 > /tmp/orig.mq5
#     powershell -File tools/Verify-ModuleSplit.ps1 -ReferencePath /tmp/orig.mq5
#
# Read-only. No build. No writes except stdout.
# =====================================================================
param(
   [string]$Shell      = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5",
   [string]$ModulesDir = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/modules",
   [string]$ReferencePath = "",
   # Re-frozen 2026-09-20 (phase 42): the Persian teaching-text rewrite.
   # Justified by an external diff, not by faith. tools/Strip-Literals.ps1
   # removes every string literal, every comment and all insignificant
   # whitespace from both sides; the resulting diff contained only
   #   - ExpAdd/ExpAddWrapped panel rows (added rows, Wrapped->single-line for
   #     rows that now fit, one row colour),
   #   - engine note/reason/status strings (why +=, phaseReason, smrReason,
   #     chainText, zoneSource, slSource, narrative, breakdown, Print rows),
   #   - one label swap EnumToString(InpHTF) -> TfFa(InpHTF), both strings.
   # No condition, no arithmetic, no registry write, no buffer index differs.
   # Re-frozen 2026-09-21 (phase 44): the click path was made total and tested.
   # Every drawn object family now has an explainer (the corner risk strip was the
   # one measured gap), a missing registry record is announced instead of leaving
   # an empty panel, the overlap tie-break is explicit (distance, then smallest
   # box, then name) and an automatic test drives the real hit-test plus the real
   # panel builder for every clickable object on the chart.
   #
   # HONEST NOTE ON THE PROOF FOR THIS PHASE: the phase-43 baseline file was
   # deleted before the diff was taken, so the usual "assemble the frozen tree and
   # diff" proof was not available this time. The change list was instead checked
   # by hand against the four touched modules (01_HeaderAndInputs, 25_Explain,
   # 26_PersianRender, 30_OnCalculate): two blocks were MOVED verbatim (the old
   # generic fallback and the frozen-history note, now ExplainUnknownObject and
   # ExplainFrozenNote), one function was renamed (BuildExplanation ->
   # ExplainDispatchObject) and everything else is new code carrying the phase-44
   # marker. To stop this gap from repeating, Verify-ModuleSplit now has a
   # -Freeze switch that writes the assembled baseline to a file, so the next
   # phase can always diff against real bytes instead of a hash.
   # Re-frozen 2026-09-22 (phase 46): the A+/A/B+/B signal grade.
   # Justified by an external diff against the phase-44 baseline bytes
   # (05_TESTS_AND_VALIDATION/frozen/assembled_9E675F79.mq5), which showed
   # exactly 12 hunks and nothing else:
   #   - the shell gains one include (modules/31_SignalGrade.mqh),
   #   - a new module 31 (the grade engine: family code, buckets, the fitted
   #     coefficient table, the thresholds, the measured win% per grade),
   #   - 01_HeaderAndInputs: one new input (InpEnableSignalGrade),
   #   - 03_GlobalState: the grade globals plus the saved row values,
   #   - 15_ReverseRisk: the CSV write MOVED out of UpdateReverseRisk() into
   #     PersistReverseRiskEvidence() so the grade columns are not one bar stale,
   #     plus five appended columns,
   #   - 26_PersianRender: the teaching rows for the strip,
   #   - 27_Dashboard: the strip row leads with GRADE and its width now follows
   #     the row length instead of a fixed 640 px,
   #   - 30_OnCalculate: UpdateSignalGrade() and PersistReverseRiskEvidence() in
   #     the closed-bar block after UpdateExhaustion().
   # No condition, arithmetic, registry write or buffer index of any earlier
   # feature was changed.
   # Re-frozen 2026-09-22 (phase 47): the pending scenario (what is waiting for a
   # candle to close) and per-timeframe evidence files.
   # Justified by an external diff against the phase-46 baseline bytes
   # (05_TESTS_AND_VALIDATION/frozen/assembled_C0725861.mq5). The stripped diff
   # contained exactly these hunks and nothing else:
   #   - the shell gains one include (modules/32_PendingScenario.mqh),
   #   - a new module 32: the pending-scenario engine, its fitted confirmation
   #     table, the single chart row, and the Persian explainer,
   #   - 01_HeaderAndInputs: four new inputs in the Phase 47 group,
   #   - 03_GlobalState: the display-only g_pend* globals,
   #   - 04_Utilities: one new helper, ChartTfCode(),
   #   - 15_ReverseRisk: the ledger file name gains the chart timeframe and one
   #     column (ChartTF) is appended,
   #   - 21_ReversalGate: the same for the reversal ledger (name + column + the
   #     matching delete/open calls in the header self-heal),
   #   - 26_PersianRender: the PEND branch in the click dispatcher,
   #   - 30_OnCalculate: UpdatePendingScenario(atrBuf[1]) in the closed-bar block
   #     and RenderPendingLine() next to RenderRiskStrip().
   # No condition, arithmetic, registry write or buffer index of any earlier
   # feature was changed; the pending engine writes nothing at all.
   # Re-frozen 2026-09-22 (phase 48): one chart colour palette, and the pending
   # row merged into the grade strip as a single "path" line.
   # Justified by an external diff against the phase-47 baseline bytes
   # (05_TESTS_AND_VALIDATION/frozen/assembled_32A7FB3F.mq5): 30 hunks, and every
   # one of them is one of the two intended changes:
   #   - 02_Types gains the chart palette table (PAL_*), declared before every
   #     drawing module so no include has to move,
   #   - 23_Drawing / 24_RedrawReconcile: the chart-object colour literals become
   #     palette names. Nothing else on those lines changed - no style, width,
   #     price, time or object name. The best-POI box, which is a highlight rather
   #     than a family of its own, now takes the DIRECTION colour (DeepSkyBlue /
   #     OrangeRed used to collide with the breaker box and the bearish gap),
   #   - 26_PersianRender / 27_Dashboard: the corner-panel border uses
   #     PAL_PANEL_BORDER, and one click on the strip now appends BOTH the grade
   #     and the pending sections,
   #   - 27_Dashboard: RenderRiskStrip composes the merged path line,
   #   - 30_OnCalculate: RenderPendingLine() becomes CleanupLegacyPendingRow(),
   #   - 32_PendingScenario: PendingScenarioLine()/RenderPendingLine() become
   #     PendingFragmentFa()/CleanupLegacyPendingRow(),
   #   - 01_HeaderAndInputs: the three pending-row layout inputs are removed (the
   #     merged row uses InpRiskStripY / InpRiskStripWidth),
   #   - 03_GlobalState: g_pendLineOn / g_pendLastText become g_pendRowCleaned.
   # No condition, arithmetic, registry write or buffer index of any earlier
   # feature was changed; no object name was renamed.
   [string]$ExpectedSha256 = "7BB650EF46BB0307CFACC1E6C5005C6D2A7D5FB710E0057C88D676A7A853E6C2",
   [int]$ExpectedModules = 32,
   [int]$ExpectedPreIncludeLines = 32,
   [int]$ExpectedLines = 12991,
   # Write the assembled baseline next to the tests so a later phase can diff
   # against real bytes: -Freeze  (no effect on the checks above)
   [switch]$Freeze,
   [string]$FreezeDir = "D:/ICT_indicator/05_TESTS_AND_VALIDATION/frozen"
)

$ErrorActionPreference = 'Stop'
$pass = 0
$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
   if ($ok) { $script:pass++; "PASS  {0}  {1}" -f $name, $detail }
   else     { $script:fail++; "FAIL  {0}  {1}" -f $name, $detail }
}

Write-Output '=== Module split verifier ==='
Write-Output ''

if (-not (Test-Path -LiteralPath $Shell)) { throw "Shell not found: $Shell" }

# ---- index the shell by line, keeping byte offsets -------------------------
$shellBytes = [System.IO.File]::ReadAllBytes($Shell)
$lineStart = New-Object 'System.Collections.Generic.List[int]'
$lineStart.Add(0)
for ($i = 0; $i -lt $shellBytes.Length; $i++) {
   if ($shellBytes[$i] -eq 10) { $lineStart.Add($i + 1) }
}
$shellLineCount = $lineStart.Count - 1
$latin1 = [System.Text.Encoding]::GetEncoding(28591)   # byte-preserving for ASCII scan lines

function Get-ShellLine([int]$n) {
   # 1-based; returns the line text without its terminator
   $a = $lineStart[$n - 1]
   $b = if ($n -lt $lineStart.Count) { $lineStart[$n] } else { $shellBytes.Length }
   $len = $b - $a
   while ($len -gt 0 -and ($shellBytes[$a + $len - 1] -eq 10 -or $shellBytes[$a + $len - 1] -eq 13)) { $len-- }
   if ($len -le 0) { return '' }
   return $latin1.GetString($shellBytes, $a, $len)
}
function Get-ShellLineBytes([int]$n) {
   $a = $lineStart[$n - 1]
   $b = if ($n -lt $lineStart.Count) { $lineStart[$n] } else { $shellBytes.Length }
   $len = $b - $a
   $out = New-Object byte[] $len
   [Array]::Copy($shellBytes, $a, $out, 0, $len)
   return ,$out
}

# ---- locate the include block ----------------------------------------------
$includeLines = @()
$includeNames = @()
for ($n = 1; $n -le $shellLineCount; $n++) {
   $m = [regex]::Match((Get-ShellLine $n), '^\s*#include\s+"([^"]+)"\s*$')
   if ($m.Success) { $includeLines += $n; $includeNames += $m.Groups[1].Value }
}

Check 'S1_INCLUDE_BLOCK_FOUND' ($includeLines.Count -gt 0) `
   ("includes found = {0}" -f $includeLines.Count)
Check 'S2_MODULE_COUNT' ($includeNames.Count -eq $ExpectedModules) `
   ("includes = {0}, expected = {1}" -f $includeNames.Count, $ExpectedModules)

$firstInc = if ($includeLines.Count -gt 0) { $includeLines[0] } else { 1 }
$lastInc  = if ($includeLines.Count -gt 0) { $includeLines[$includeLines.Count - 1] } else { 0 }

Check 'S3_HEADER_LINES_BEFORE_INCLUDES' ($firstInc -eq ($ExpectedPreIncludeLines + 1)) `
   ("first include is line {0}; the property/define header must occupy lines 1..{1}" -f $firstInc, $ExpectedPreIncludeLines)

# ---- nothing executable after the last include -----------------------------
$postProblems = @()
for ($n = $lastInc + 1; $n -le $shellLineCount; $n++) {
   $t = (Get-ShellLine $n).TrimStart()
   if ($t.Length -eq 0) { continue }
   if ($t.StartsWith('//')) { continue }
   $postProblems += ("line {0}: {1}" -f $n, $t)
}
Check 'S4_NO_CODE_AFTER_LAST_INCLUDE' ($postProblems.Count -eq 0) `
   ("content after the include block must be blank or a comment; offenders = [{0}]" -f ($postProblems -join ' | '))

# ---- every include resolves, every module is referenced --------------------
$missing = @()
foreach ($rel in $includeNames) {
   $p = Join-Path (Split-Path -Parent $Shell) $rel
   if (-not (Test-Path -LiteralPath $p)) { $missing += $rel }
}
Check 'S5_ALL_INCLUDES_RESOLVE' ($missing.Count -eq 0) ("unresolved includes = [{0}]" -f ($missing -join ','))

$onDisk = @(Get-ChildItem -LiteralPath $ModulesDir -Filter '*.mqh' -File | ForEach-Object { $_.Name })
$declaredNames = @($includeNames | ForEach-Object { Split-Path -Leaf $_ })
$unreferenced = @($onDisk | Where-Object { $declaredNames -notcontains $_ })
Check 'S6_NO_ORPHAN_MODULE' ($unreferenced.Count -eq 0) `
   ("every .mqh must be included; unreferenced = [{0}]" -f ($unreferenced -join ','))

# ---- each module opens with a banner --------------------------------------
$bannerProblems = @()
foreach ($rel in $includeNames) {
   $p = Join-Path (Split-Path -Parent $Shell) $rel
   $mb = [System.IO.File]::ReadAllBytes($p)
   if ($mb.Length -eq 0) { $bannerProblems += "$rel (empty)"; continue }
   $head = $latin1.GetString($mb, 0, [Math]::Min(60, $mb.Length))
   if ($head -notmatch '^//={20,}') { $bannerProblems += "$rel (no banner)" }
}
Check 'S7_EVERY_MODULE_IS_A_FAMILY' ($bannerProblems.Count -eq 0) `
   ("each module must start with a section banner; offenders = [{0}]" -f ($bannerProblems -join ','))

# ---- reassemble exactly what the preprocessor sees -------------------------
$out = New-Object 'System.Collections.Generic.List[byte]'
for ($n = 1; $n -lt $firstInc; $n++) {
   $out.AddRange((Get-ShellLineBytes $n))
}
foreach ($rel in $includeNames) {
   $p = Join-Path (Split-Path -Parent $Shell) $rel
   $out.AddRange([System.IO.File]::ReadAllBytes($p))
}
$assembled = $out.ToArray()

$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = ([System.BitConverter]::ToString($sha.ComputeHash($assembled))).Replace('-', '')
Write-Output ''
Write-Output ("Assembled bytes  : {0}" -f $assembled.Length)
Write-Output ("Assembled SHA256 : {0}" -f $hash)
Write-Output ("Frozen pre-split : {0}" -f $ExpectedSha256)
Check 'S8_BYTE_IDENTICAL_TO_PRE_SPLIT' ($hash -eq $ExpectedSha256.ToUpper()) `
   'assembled translation unit hashes to the frozen pre-split source'

$assembledLines = 0
foreach ($b in $assembled) { if ($b -eq 10) { $assembledLines++ } }
Check 'S9_LINE_COUNT_PRESERVED' ($assembledLines -eq $ExpectedLines) `
   ("assembled lines = {0}, reference lines = {1}" -f $assembledLines, $ExpectedLines)

# ---- optional: store the baseline so the NEXT phase can diff real bytes ----
if ($Freeze) {
   if (-not (Test-Path -LiteralPath $FreezeDir)) { New-Item -ItemType Directory -Path $FreezeDir -Force | Out-Null }
   $target = Join-Path $FreezeDir ("assembled_" + $hash.Substring(0, 8) + ".mq5")
   [System.IO.File]::WriteAllBytes($target, $assembled)
   Write-Output ("Frozen baseline : {0}" -f $target)
}

# ---- optional real diff against an extracted original ----------------------
if (-not [string]::IsNullOrWhiteSpace($ReferencePath)) {
   if (-not (Test-Path -LiteralPath $ReferencePath)) { throw "Reference not found: $ReferencePath" }
   $ref = [System.IO.File]::ReadAllBytes($ReferencePath)
   Check 'S10_REFERENCE_LENGTH' ($ref.Length -eq $assembled.Length) `
      ("reference = {0} bytes, assembled = {1} bytes" -f $ref.Length, $assembled.Length)
   $firstDiff = -1
   for ($i = 0; $i -lt [Math]::Min($ref.Length, $assembled.Length); $i++) {
      if ($ref[$i] -ne $assembled[$i]) { $firstDiff = $i; break }
   }
   if ($firstDiff -ge 0) {
      $lineNo = 1
      for ($i = 0; $i -lt $firstDiff; $i++) { if ($ref[$i] -eq 10) { $lineNo++ } }
      Check 'S11_REFERENCE_BYTE_DIFF' $false ("first difference at byte {0} (line {1})" -f $firstDiff, $lineNo)
   } else {
      Check 'S11_REFERENCE_BYTE_DIFF' $true 'no differing byte against the supplied reference'
   }
}

Write-Output ''
Write-Output ("RESULT: PASS={0} FAIL={1}" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
