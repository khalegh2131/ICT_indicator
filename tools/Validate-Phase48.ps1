<#
  Validate-Phase48.ps1  --  locks the chart colour palette and the merged path row

  What is proven, and how:

    A1 palette exists  -- the chart palette table is declared in 02_Types.mqh, i.e.
                          BEFORE every drawing module, so no include had to move.
    A2 no duplicate    -- every palette entry is either a distinct RGB triple, or is
                          one of the SEVEN shares the source declares on purpose
                          (same-family roles told apart by the label or by line
                          style). Before this phase four unrelated families shared
                          one colour, so "is it an order block or a Silver Bullet
                          window?" could not be answered from the chart.
    A3 distance        -- the minimum pairwise RGB distance across the distinct
                          palette values is recomputed from the source text and must
                          stay above a floor. This is the number the design was
                          optimised for, not a matter of taste.
    A4 the three asked -- the three families the user named (inverted gap, daily
                          true open, weekly true open) must be far apart from each
                          other. This is the explicit complaint this phase answers.
    A5 direction inputs -- the two user-configurable direction colours must also stay
                          away from every palette entry, otherwise a bull/bear zone
                          would blend into a family that is not its own.
    B  one source      -- no drawing call site may pass a raw colour literal any
                          more. If it does, a later edit can reintroduce a silent
                          collision without touching the palette table.
    C  one row         -- the grade row and the pending row are ONE row now: exactly
                          one corner panel is created, the strip composes the path
                          fragment, and the removed layout inputs are gone.
    D  one click       -- clicking that one row must explain BOTH halves, otherwise
                          merging the rows would have cost the user a section.
    E  cleanup         -- the objects of the removed row are deleted once at runtime,
                          so an existing chart does not keep a stale box.

  NOTE: ASCII-only by design (PowerShell 5.1 misreads non-BOM UTF-8 sources).
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src  = Join-Path $root '01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5'

$pass = 0; $fail = 0; $pend = 0
function Check($name, $ok, $detail) {
   if ($ok) { $script:pass++ ; Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
   else     { $script:fail++ ; Write-Host ("FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red }
}
function Pend($name, $detail) { $script:pend++ ; Write-Host ("PEND  {0}  {1}" -f $name, $detail) -ForegroundColor Yellow }

. "$PSScriptRoot/CanonicalSource.ps1"
$code = Get-CanonicalSourceText -Path $src
$typesFile = Join-Path $root '01_CANONICAL_CANDIDATES/modules/02_Types.mqh'
$types = [System.IO.File]::ReadAllText($typesFile)

# ------------------------------------------------------------------ A) palette
# Every explicit PAL_ value is read from 02_Types.mqh - that file is included before
# every drawing module, and the ONLY place a PAL_ constant may be declared.
$entries = @{}
foreach ($line in ($types -split "`n")) {
   $lm = [regex]::Match($line, "const\s+color\s+(PAL_[A-Z0-9_]+)\s*=\s*C'(\d+)\s*,\s*(\d+)\s*,\s*(\d+)'\s*;")
   if ($lm.Success) {
      $entries[$lm.Groups[1].Value] = @([int]$lm.Groups[2].Value, [int]$lm.Groups[3].Value, [int]$lm.Groups[4].Value)
   }
}
$declaredElsewhere = @()
foreach ($rel in @('23_Drawing.mqh','24_RedrawReconcile.mqh','27_Dashboard.mqh','31_SignalGrade.mqh','32_PendingScenario.mqh')) {
   $p = Join-Path $root ('01_CANONICAL_CANDIDATES/modules/' + $rel)
   if ((Test-Path -LiteralPath $p) -and ([System.IO.File]::ReadAllText($p) -match 'const\s+color\s+PAL_')) { $declaredElsewhere += $rel }
}
Check 'A1_palette_declared_before_draw' (($entries.Count -ge 35) -and ($declaredElsewhere.Count -eq 0)) `
   ("the PAL_ table lives in 02_Types.mqh only (before every drawing module); stray declarations = [{0}]" -f ($declaredElsewhere -join ', '))
Check 'A1b_palette_entries_found' ($entries.Count -ge 35) ("explicit RGB entries = {0}" -f $entries.Count)

# the SEVEN shares the source declares on purpose
$allowed = @(
   'PAL_SESS_LONDON|PAL_SESS_LONDONCLOSE',
   'PAL_SESS_NY|PAL_SESS_NYPM',
   'PAL_PROF_POC|PAL_PROF_NPOC',
   'PAL_LOC_GOLDEN|PAL_LOC_EQ',
   'PAL_LOC_GOLDEN|PAL_LOC_OTE',
   'PAL_LOC_EQ|PAL_LOC_OTE',
   'PAL_BROOKS_MM|PAL_BROOKS_TRMID'
)
$byValue = @{}
foreach ($k in $entries.Keys) {
   $key = ($entries[$k] -join ',')
   if (-not $byValue.ContainsKey($key)) { $byValue[$key] = @() }
   $byValue[$key] += $k
}
$badPairs = @()
foreach ($key in $byValue.Keys) {
   $names = @($byValue[$key])
   if ($names.Count -le 1) { continue }
   # every PAIR inside a shared group must be declared, so a group of three only
   # passes when all three of its pairs are on the list
   for ($a = 0; $a -lt $names.Count; $a++) {
      for ($b = $a + 1; $b -lt $names.Count; $b++) {
         $want = (@($names[$a], $names[$b]) | Sort-Object) -join '|'
         # normalise BOTH sides the same way, so the order inside the list above
         # cannot decide whether a share counts as declared
         $declared = @(($allowed | ForEach-Object { (@($_ -split '\|') | Sort-Object) -join '|' }))
         if ($declared -notcontains $want) { $badPairs += ($want + ' = ' + $key) }
      }
   }
}
$badShares = $badPairs
Check 'A2_no_undeclared_duplicate' ($badShares.Count -eq 0) ("distinct values = {0}; undeclared shares = [{1}]" -f $byValue.Count, ($badShares -join ' ; '))

# minimum pairwise distance across the distinct values
function Dist($a, $b) {
   $s = 0.0
   for ($i = 0; $i -lt 3; $i++) { $d = $a[$i] - $b[$i]; $s += $d * $d }
   return [math]::Sqrt($s)
}
$vals = @()
foreach ($key in $byValue.Keys) { $vals += ,@($key -split ',' | ForEach-Object { [int]$_ }) }
$minAll = [double]::MaxValue; $minPair = ''
for ($i = 0; $i -lt $vals.Count; $i++) {
   for ($j = $i + 1; $j -lt $vals.Count; $j++) {
      $d = Dist $vals[$i] $vals[$j]
      if ($d -lt $minAll) { $minAll = $d; $minPair = (($vals[$i] -join ',') + ' vs ' + ($vals[$j] -join ',')) }
   }
}
$minAll = [math]::Round($minAll, 1)
Check 'A3_min_pairwise_distance' ($minAll -ge 50) ("min pairwise RGB distance = {0} (floor 50) at {1}" -f $minAll, $minPair)

# the three families the user named must be far apart
$needed = @('PAL_FVG_INVERTED', 'PAL_QT_DAY', 'PAL_QT_WEEK')
$haveAll = $true
foreach ($n in $needed) { if (-not $entries.ContainsKey($n)) { $haveAll = $false } }
$sep = @()
if ($haveAll) {
   for ($i = 0; $i -lt 3; $i++) {
      for ($j = $i + 1; $j -lt 3; $j++) {
         $sep += [math]::Round((Dist $entries[$needed[$i]] $entries[$needed[$j]]), 1)
      }
   }
}
Check 'A4_named_three_are_distinct' ($haveAll -and (($sep | Measure-Object -Minimum).Minimum -ge 150)) `
   ("inverted gap / daily open / weekly open separations = [{0}] (floor 150)" -f ($sep -join ', '))

# the two direction inputs must stay away from the palette too
$direction = @{ 'InpColorBull(lime)' = @(0, 255, 0); 'InpColorBear(orangered)' = @(255, 69, 0) }
$minDir = [double]::MaxValue; $minDirWho = ''
foreach ($key in $byValue.Keys) {
   $v = @($key -split ',' | ForEach-Object { [int]$_ })
   foreach ($dn in $direction.Keys) {
      $d = Dist $v $direction[$dn]
      if ($d -lt $minDir) { $minDir = $d; $minDirWho = ($dn + ' vs ' + $key) }
   }
}
$minDir = [math]::Round($minDir, 1)
Check 'A5_direction_inputs_clear' ($minDir -ge 50) ("closest distance from a direction input = {0} (floor 50) at {1}" -f $minDir, $minDirWho)

# ------------------------------------------------------------------ B) one source
$rawCall = [regex]::Matches($code, '(DrawHLineObj|DrawBoxObj|DrawTextObj|DrawTrendObj|DrawArrowObj|DrawRectObj|DrawVLineObj)\([^;]*clr[A-Z][A-Za-z]*')
$rawProp = [regex]::Matches($code, 'OBJPROP_COLOR[^;]*clr[A-Z][A-Za-z]*')
Check 'B1_no_raw_colour_in_draw_calls' ($rawCall.Count -eq 0) ("offenders = {0}" -f $rawCall.Count)
Check 'B2_no_raw_colour_in_object_prop' ($rawProp.Count -eq 0) ("offenders = {0}" -f $rawProp.Count)

# ------------------------------------------------------------------ C) one row
$stripBody = ''
$i = $code.IndexOf('void RenderRiskStrip()')
if ($i -ge 0) {
   $open = $code.IndexOf('{', $i)
   $j = $code.IndexOf("`n}", $open)
   $stripBody = $code.Substring($open, $j - $open)
}
Check 'C1_strip_composes_the_path' ($stripBody -match 'PendingFragmentFa\(\)') `
   'RenderRiskStrip() appends the pending fragment'
Check 'C2_strip_leads_with_the_grade' ($stripBody -match 'GRADE:') `
   'the row still leads with the fitted grade'
$pendBody = ''
$i = $code.IndexOf('string PendingFragmentFa()')
if ($i -ge 0) {
   $open = $code.IndexOf('{', $i)
   $j = $code.IndexOf("`n}", $open)
   $pendBody = $code.Substring($open, $j - $open)
}
Check 'C3_fragment_reads_only_pending_state' `
   (($pendBody -match 'g_pendState') -and ($pendBody -match 'g_pendMagnetPrice') -and ($pendBody -match 'g_pendTriggerFa') -and ($pendBody -notmatch 'iATR\(|CopyClose|Bid|Ask')) `
   'the merged fragment reuses the pending state and reads no live price'
$rowObjects = [regex]::Matches($code, 'ObjectCreate\([^;]*"ICTv13_PEND_(BG|TXT)"')
Check 'C4_no_second_row_object' ($rowObjects.Count -eq 0) `
   'the separate pending row is no longer created; only deleted once (CleanupLegacyPendingRow)'
$deadInputs = @('InpShowPendingLine', 'InpPendingLineY', 'InpPendingLineWidth')
$stillThere = @($deadInputs | Where-Object { $code -match ('(?m)^input\s+\w+\s+' + $_ + '\s*=') })
Check 'C5_layout_inputs_removed' ($stillThere.Count -eq 0) ("removed inputs still declared = [{0}]" -f ($stillThere -join ', '))

# ------------------------------------------------------------------ D) one click
$explain = ''
$i = $code.IndexOf('void ExplainRiskStripObject()')
if ($i -ge 0) {
   $open = $code.IndexOf('{', $i)
   $j = $code.IndexOf("`n}", $open)
   $explain = $code.Substring($open, $j - $open)
}
Check 'D1_click_explains_both_halves' `
   (($explain -match 'ExplainPendingScenario\(true\)') -and ($explain -match 'g_grade')) `
   'one click on the row explains the grade AND the pending path'
Check 'D2_strip_still_dispatchable' ($code -match 'StringFind\(body,"RSTRIP"\)') `
   'the click dispatcher still routes the row to ExplainRiskStripObject()'

# ------------------------------------------------------------------ E) cleanup
$onCalc = ''
$i = $code.IndexOf('CleanupLegacyPendingRow();')
Check 'E1_legacy_row_cleaned_once' (($code -match 'void CleanupLegacyPendingRow\(\)') -and ($i -ge 0) -and ($code -match 'g_pendRowCleaned')) `
   'the old row objects are deleted once, guarded by g_pendRowCleaned'

# ------------------------------------------------------------------ R) runtime
$objFile = Join-Path $env:APPDATA 'MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Indicators\khaleq\newICT\ICT_Assistant_Canonical_v0_1.ex5'
if (Test-Path -LiteralPath $objFile) {
   Check 'R1_artifact_present' $true ("compiled artifact = {0}" -f (Get-Item -LiteralPath $objFile).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
} else {
   Pend 'R1_artifact_present' 'no compiled artifact yet; run tools/Sync-And-Compile-Canonical.ps1'
}

Write-Host ("`nPASS={0}  FAIL={1}  PENDING={2}" -f $pass, $fail, $pend)
if ($fail -gt 0) { exit 1 }
exit 0
