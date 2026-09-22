# =====================================================================
# Validate-Phase43.ps1  --  one direction, one meaning (iFVG inversion)
#
# WHY THIS EXISTS
# ---------------
# The bug this phase closed was not arithmetic; it was a *mutated field*.
# The inversion rule used to rewrite g_fvgs[].direction, so one field carried
# two meanings over time (the direction the gap was born with, and the role it
# plays after price closed through it). Every consumer read that field
# directly, so depending on when it read, the same zone could be reported as
# bullish by one surface and bearish by another -- a purple (inverted) box
# whose diagnostic row said BULL, while the setup selector and the reversal
# gate disagreed with both.
#
# The fix has three parts, and this tool locks each one:
#
#   1. IMMUTABILITY -- nothing in the compiled unit may assign to
#      g_fvgs[..].direction. The birth direction is what the geometry
#      (top/bottom), the zone id (StableZoneId) and the object name are all
#      built from; changing it silently re-labels the object.
#
#   2. ONE DERIVATION -- the current role is produced by FVGActiveDir()
#      (and OBActiveDir() for order blocks, whose polarityFlipped flag is the
#      same idea). Every surface that answers "which way does this zone work
#      now?" must go through it: the box colour, the setup zone selector, the
#      POI registry, the reversal gate, the nearest-level readout and the
#      trading panel title.
#
#   3. ONE REPORT STRING -- FVGPolarityReport() builds the direction label for
#      both the explanation panel and the diagnostic CSV row, so those two can
#      never drift apart. A second, separate formatter anywhere is a failure.
#
# The remaining readers of the birth direction are listed explicitly below.
# Each of them must ask about the CREATOR, not about today's role:
#   * DisplacementChained  -- the chain belongs to the bar that formed the gap
#   * the inversion rule   -- it detects the state change itself
#   * the exhaustion zone  -- "a zone born with the bias has now failed"
# Any new reader that is not in that list fails this tool until it is either
# converted or justified in the list, which is the point: the decision is
# visible instead of accidental.
#
# Read-only. No build. No writes except stdout.
# =====================================================================
param(
   [string]$Source = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5",
   # Overridable so the section-5 parser itself can be exercised against a
   # synthetic report (the tool is tested, not just run).
   [string]$FvgCsv = ""
)

$ErrorActionPreference = "Stop"
$pass = 0
$fail = 0
$pending = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
   if ($ok) { $script:pass++; "PASS  {0}  {1}" -f $name, $detail }
   else     { $script:fail++; "FAIL  {0}  {1}" -f $name, $detail }
}

Write-Output "=== Phase 43 -- iFVG inversion: one direction, one meaning ==="
Write-Output ""

if (-not (Test-Path -LiteralPath $Source)) { throw "Canonical source not found: $Source" }
# The canonical indicator is a shell plus one module per strategy family;
# flatten it the way MQL5 does so the checks below see the real code.
. "$PSScriptRoot/CanonicalSource.ps1"
$src = Get-CanonicalSourceText -Path $Source

# ---------------------------------------------------------------------
# 1) IMMUTABILITY of the birth direction
# ---------------------------------------------------------------------
Write-Output "--- 1) the birth direction is immutable ---"

$mutations = [regex]::Matches($src, 'g_fvgs\[[^\]]*\]\s*\.\s*direction\s*=[^=]')
Check "1a_NO_WRITE_TO_FVG_DIRECTION" ($mutations.Count -eq 0) `
   ("assignments to g_fvgs[..].direction = {0} (must be 0: it is the birth direction, and the zone id / box name are built from it)" -f $mutations.Count)

# writing the field at construction time (f.direction=dir on a fresh struct) is
# not a mutation of a registered zone; only the registry array is checked above.
$ctorWrites = [regex]::Matches($src, '(?<![\.\w])f\s*\.\s*direction\s*=').Count
Check "1b_CONSTRUCTOR_SETS_DIRECTION_ONCE_PER_KIND" ($ctorWrites -ge 4) `
   ("fresh-struct direction assignments = {0} (standard/implied/volume-imbalance zones plus the shared AppendFVG path)" -f $ctorWrites)

Check "1c_INVERSION_STAMPS_TIME" `
   ($src -match 'g_fvgs\[i\]\.inverted\s*=\s*true;\s*\n\s*g_fvgs\[i\]\.invertedTime\s*=\s*curBarTime;') `
   "inversion records invertedTime, so the same zone's flip is auditable in the CSV (InvertedAt)"

$invertedInits   = [regex]::Matches($src, 'f\.inverted\s*=\s*false;').Count
$invertedTimeInit= [regex]::Matches($src, 'f\.invertedTime\s*=\s*0;').Count
Check "1d_EVERY_CONSTRUCTION_INITIALISES_INVERTED_TIME" ($invertedInits -eq $invertedTimeInit -and $invertedInits -gt 0) `
   ("f.inverted=false occurrences = {0}, f.invertedTime=0 occurrences = {1} (an uninitialised stamp would print garbage in the CSV)" -f $invertedInits, $invertedTimeInit)

# ---------------------------------------------------------------------
# 2) ONE DERIVATION of the active role
# ---------------------------------------------------------------------
Write-Output ""
Write-Output "--- 2) the active role has exactly one derivation ---"

foreach ($fn in @('FVGActiveDir', 'OBActiveDir')) {
   $defs = [regex]::Matches($src, ('ENUM_DIRECTION\s+' + $fn + '\s*\(')).Count
   Check ("2a_" + $fn + "_DEFINED_ONCE") ($defs -eq 1) ("definitions of {0} = {1}" -f $fn, $defs)
}

Check "2b_FVG_ACTIVE_DIR_USES_OPPOSITE" `
   ($src -match 'ENUM_DIRECTION FVGActiveDir\(const FVGObj &f\)\s*\n\{\s*\n\s*return f\.inverted\? OppositeDir\(f\.direction\) : f\.direction;') `
   "FVGActiveDir returns the birth direction unless the gap inverted"
Check "2c_OB_ACTIVE_DIR_USES_POLARITY_FLAG" `
   ($src -match 'ENUM_DIRECTION OBActiveDir\(const OBObj &o\)\s*\n\{\s*\n\s*return o\.polarityFlipped\? OppositeDir\(o\.direction\) : o\.direction;') `
   "OBActiveDir mirrors it for order blocks via polarityFlipped (breaker / mitigation block)"

# every surface that answers "which way now" must route through the helper
$surfaces = @(
   @{ Name = '2d_BOX_COLOUR_USES_ACTIVE_ROLE';    Pattern = 'color clr = FVGActiveDir\(f\)==DIR_BULL\?InpColorBull:InpColorBear;'; Detail = 'DrawFVG paints from the active role, so a filled zone cannot contradict the panel' },
   @{ Name = '2e_SETUP_ZONE_USES_ACTIVE_ROLE';    Pattern = 'if\(FVGActiveDir\(g_fvgs\[i\]\)!=g_htfBias\) continue;';                                            Detail = 'the setup engine selects the entry zone by today''s role (an inverted gap is a valid entry the other way)' },
   @{ Name = '2f_POI_REGISTRY_FVG_ACTIVE_ROLE';   Pattern = 'AddPOI\(g_fvgs\[i\]\.id, POIK_FVG, FVGActiveDir\(g_fvgs\[i\]\)';                                      Detail = 'the POI registry (trading-facing output) stores the active role for gaps' },
   @{ Name = '2g_POI_REGISTRY_OB_ACTIVE_ROLE';    Pattern = 'AddPOI\(g_obs\[i\]\.id, k, OBActiveDir\(g_obs\[i\]\)';                                                 Detail = 'the POI registry stores the active role for order blocks (a breaker is the opposite of its birth)' },
   @{ Name = '2h_REVERSAL_GATE_ACTIVE_ROLE';      Pattern = 'if\(FVGActiveDir\(g_fvgs\[i\]\)==dir && g_fvgs\[i\]\.causal';                                            Detail = 'the reversal gate asks for a same-direction witness in today''s role' },
   @{ Name = '2i_RISK_READOUT_ACTIVE_ROLE';       Pattern = 'RRFvgKindName\(g_fvgs\[i\]\.kind\)\+\(\(FVGActiveDir\(g_fvgs\[i\]\)==DIR_BULL\)';                          Detail = 'the nearest-level readout labels the zone by today''s role and says when it inverted' },
   @{ Name = '2j_RISK_READOUT_OB_ACTIVE_ROLE';    Pattern = 'string dirTxt=\(OBActiveDir\(o\)==DIR_BULL\)';                                                        Detail = 'the demand/supply label of the nearest OB follows the flipped polarity too' }
)
foreach ($s in $surfaces) {
   Check $s.Name ($src -match $s.Pattern) $s.Detail
}

# the birth-direction readers, each required to be present or absent on purpose
Write-Output ""
Write-Output "--- 2k) the remaining birth-direction readers are a declared list ---"
$birthReaders = [regex]::Matches($src, 'g_fvgs\[[a-z]*\]\s*\.\s*direction')
Check "2k_BIRTH_READER_COUNT" ($birthReaders.Count -eq 4) `
   ("readers of g_fvgs[..].direction = {0} (expected 4: displacement chain, the two inversion tests, the exhaustion zone-failure test)" -f $birthReaders.Count)
Check "2l_CHAIN_READER_IS_BIRTH_ON_PURPOSE" `
   ($src -match 'DisplacementChained\(g_fvgs\[i\]\.displacementId, g_fvgs\[i\]\.direction\)') `
   "the displacement chain belongs to the bar that formed the gap, not to today's role"
Check "2m_EXHAUSTION_READER_IS_BIRTH_ON_PURPOSE" `
   ($src -match 'if\(g_fvgs\[i\]\.direction==g_htfBias && \(g_fvgs\[i\]\.invalidated \|\| g_fvgs\[i\]\.inverted\)\)') `
   "the exhaustion witness asks whether a zone BORN with the bias has failed"

# ---------------------------------------------------------------------
# 3) ONE REPORT STRING for panel and CSV
# ---------------------------------------------------------------------
Write-Output ""
Write-Output "--- 3) the panel and the CSV share one string ---"

$reportDefs = [regex]::Matches($src, 'string\s+FVGPolarityReport\s*\(').Count
Check "3a_POLARITY_REPORT_DEFINED_ONCE" ($reportDefs -eq 1) ("FVGPolarityReport definitions = {0}" -f $reportDefs)
Check "3b_REPORT_SHOWS_BIRTH_THEN_ACTIVE" `
   ($src -match 'if\(!f\.inverted\) return birth;\s*\n\s*return birth\+" -> "\+DirToStr\(FVGActiveDir\(f\)\)\+" \(iFVG\)";') `
   "the report prints the birth direction and, when inverted, the active role after it"
$reportCalls = [regex]::Matches($src, 'FVGPolarityReport\s*\(').Count
Check "3c_REPORT_USED_BY_BOTH_SURFACES" ($reportCalls -ge 3) `
   ("FVGPolarityReport call sites = {0} (definition + panel title + diagnostic CSV row)" -f $reportCalls)
Check "3d_PANEL_TITLE_USES_REPORT" `
   ($src -match 'g_expTitle="ZONE "\+FVGKindToStr\(f\.kind\)\+" #"\+IdToStr\(f\.id\)\+" "\+FVGPolarityReport\(f\);') `
   "the panel title goes through the shared report"
Check "3e_CSV_ROW_USES_REPORT" `
   ($src -match '(?s)FileWrite\(h,IdToStr\(f\.id\),.*?FVGPolarityReport\(f\),') `
   "the diagnostic CSV row emits the same report string as the panel title"

# the CSV must keep the birth direction and the active role in SEPARATE columns
Check "3f_CSV_SEPARATES_BIRTH_FROM_ACTIVE" `
   (($src -match '"Id","DirBirth"') -and ($src -match '"InvertedAt"') -and ($src -match '"Role","ActiveDir"')) `
   'columns DirBirth / InvertedAt / Role / ActiveDir exist (a single "Dir" column was the ambiguity this phase removed)'
$legacyDirHeader = [regex]::Matches($src, '"Id","Dir"').Count
Check "3g_NO_AMBIGUOUS_DIR_HEADER" ($legacyDirHeader -eq 0) `
   ("ambiguous ""Dir"" CSV headers remaining = {0}" -f $legacyDirHeader)

# ---------------------------------------------------------------------
# 4) the behavioral self-test carries the phase-43 rows
# ---------------------------------------------------------------------
Write-Output ""
Write-Output "--- 4) the synthetic-data harness proves the behaviour ---"
$rows = @(
   'FVG_INVERSION_TARGET_ZONE_PRESENT', 'FVG_INVERSION_FLAG_AND_TIME',
   'FVG_INVERSION_KEEPS_BIRTH_DIRECTION', 'FVG_INVERSION_SWITCHES_ACTIVE_ROLE',
   'FVG_INVERSION_KEEPS_GEOMETRY_AND_ID', 'FVG_INVERSION_REPORTS_ONE_DIRECTION',
   'FVG_INVERSION_IS_ONE_WAY'
)
$missingRows = @($rows | Where-Object { $src -notmatch ('SelfTestRow\(\s*"' + [regex]::Escape($_) + '"') })
Check "4a_INVERSION_SCENARIOS_DECLARED" ($missingRows.Count -eq 0) `
   ("declared in the harness: {0} of {1}; missing=[{2}]" -f ($rows.Count - $missingRows.Count), $rows.Count, ($missingRows -join ','))
Check "4b_HARNESS_RUNS_THE_INVERSION_SUITE" ($src -match 'SelfTestFVGPolarity\(\);') `
   "SelfTestFVGPolarity() is called inside RunBehaviorSelfTest, so the rows are produced on every attach"
Check "4c_HARNESS_CALLS_THE_LIVE_LIFECYCLE" `
   ($src -match '(?s)void SelfTestFVGPolarity\(\).*?UpdateFVG_Lifecycle\(') `
   "the harness drives the production lifecycle function, not a copy of the rule"

# the same scenario list must stay in step with the runtime verifier
$runtimeTool = Join-Path $PSScriptRoot 'Validate-Phase37.ps1'
if (Test-Path -LiteralPath $runtimeTool) {
   $toolText = Get-Content -LiteralPath $runtimeTool -Raw
   $missingInTool = @($rows | Where-Object { $toolText -notmatch [regex]::Escape($_) })
   Check "4d_RUNTIME_VERIFIER_KNOWS_THE_ROWS" ($missingInTool.Count -eq 0) `
      ("Validate-Phase37 scenario inventory must list every new row; missing=[{0}]" -f ($missingInTool -join ','))
} else {
   Check "4d_RUNTIME_VERIFIER_KNOWS_THE_ROWS" $false "Validate-Phase37.ps1 not found next to this tool"
}

# ---------------------------------------------------------------------
# 5) RUNTIME EVIDENCE -- if the diagnostic CSV exists, the id must agree
#    with the birth direction, and ActiveDir must carry the flip.
#
#    The zone id is built as time*100 + kind*10 + direction, i.e. the last
#    digit IS the birth direction. Before this phase the CSV contradicted
#    that digit on every inverted row (measured: 140 of 140 inverted rows,
#    0 of 10 non-inverted rows), because the inversion rule had overwritten
#    the direction. That is the cheapest possible proof that the ambiguity
#    is gone: it needs no chart, only the file the indicator writes.
# ---------------------------------------------------------------------
Write-Output ""
Write-Output "--- 5) runtime evidence from the diagnostic CSV ---"

$fvgCsv = if ([string]::IsNullOrWhiteSpace($FvgCsv)) { "$env:APPDATA/MetaQuotes/Terminal/Common/Files/ICT_Assistant_Canonical_FVG_Diag.csv" } else { $FvgCsv }
if (-not (Test-Path -LiteralPath $fvgCsv)) {
   "PEND  5a_ID_AGREES_WITH_BIRTH_DIRECTION  no report yet: $fvgCsv (reload the indicator once, then re-run)"
   "PEND  5b_ACTIVE_DIR_CARRIES_THE_FLIP      no report yet"
   $pending = 2
} else {
   # The indicator writes this file as UTF-16LE (FILE_UNICODE); the fixtures in
   # 05_TESTS_AND_VALIDATION are UTF-8. Detect instead of assuming, otherwise a
   # mis-decoded header silently looks like "the old build".
   $bytes = [System.IO.File]::ReadAllBytes($fvgCsv)
   $enc   = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
               [System.Text.Encoding]::Unicode
            } else {
               New-Object System.Text.UTF8Encoding($false)
            }
   $raw = $enc.GetString($bytes)
   $lines = $raw -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 }
   # The file starts with a UTF-16 BOM, which -Encoding detects but keeps as a
   # U+FEFF character glued to the first header field. Without stripping it,
   # IndexOf('Id') returns -1 and every row is compared against the WRONG column
   # (PowerShell reads [-1] as the last element) - which is exactly how this
   # check once reported 33 phantom violations on consistent data.
   $header = ($lines[0] -replace "^\uFEFF", '') -split ';'
   $idxId     = [array]::IndexOf($header, 'Id')
   $idxBirth  = [array]::IndexOf($header, 'DirBirth')
   $idxActive = [array]::IndexOf($header, 'ActiveDir')
   $idxInv    = [array]::IndexOf($header, 'Inverted')
   $idxRole   = [array]::IndexOf($header, 'Role')
   if (($idxBirth -lt 0) -or ($idxActive -lt 0) -or ($idxRole -lt 0)) {
      "PEND  5a_ID_AGREES_WITH_BIRTH_DIRECTION  the file still has the old columns (Id;Dir;...) - it was written by the previous build; reload and re-run"
      "PEND  5b_ACTIVE_DIR_CARRIES_THE_FLIP      same reason"
      $pending = 2
   } else {
      $bad  = 0; $badEx = @()
      $badA = 0; $badAEx = @()
      $n = 0
      for ($i = 1; $i -lt $lines.Count; $i++) {
         $c = $lines[$i] -split ';'
         if ($c.Count -le $idxRole) { continue }
         $n++
         $id      = $c[$idxId]
         $birth   = $c[$idxBirth]
         $active  = $c[$idxActive]
         $inv     = $c[$idxInv]
         # last digit of the id is the direction the zone was born with (0=BULL, 1=BEAR)
         $idDir = if ($id[-1] -eq '0') { 'BULL' } else { 'BEAR' }
         if ($birth -ne $idDir) {
            $bad++
            if ($badEx.Count -lt 3) { $badEx += ("id={0} DirBirth={1} but the id encodes {2}" -f $id, $birth, $idDir) }
         }
         if ($inv -eq '1') {
            $expectActive = if ($birth -eq 'BULL') { 'BEAR' } else { 'BULL' }
            if ($active -ne $expectActive) {
               $badA++
               if ($badAEx.Count -lt 3) { $badAEx += ("id={0} DirBirth={1} Inverted=1 but ActiveDir={2}" -f $id, $birth, $active) }
            }
         }
      }
      Check "5a_ID_AGREES_WITH_BIRTH_DIRECTION" ($bad -eq 0) `
         ("rows={0}; DirBirth rows that contradict the direction encoded in the zone id = {1} [{2}]" -f $n, $bad, ($badEx -join ' | '))
      Check "5b_ACTIVE_DIR_CARRIES_THE_FLIP" ($badA -eq 0) `
         ("inverted rows whose ActiveDir is not the opposite of DirBirth = {0} [{1}]" -f $badA, ($badAEx -join ' | '))
   }
}

Write-Output ""
if ($pending -gt 0) {
   Write-Output ("RESULT: PASS={0} FAIL={1} PENDING={2} (section A/C are proved; section 5 needs one chart reload)" -f $pass, $fail, $pending)
} else {
   Write-Output ("RESULT: PASS={0} FAIL={1}" -f $pass, $fail)
}
if ($fail -gt 0) { exit 1 }
exit 0
