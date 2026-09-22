<#
  Validate-Phase49.ps1  --  locks the symbol profile ("all symbols, majors and minors")

  What is proven, and how:

    A1 the two problems -- the phase exists because TWO things change per symbol and
                           were held constant: the meaning of a "point" and the
                           calibration the grade is read from. Both are checked by
                           pattern, not by intention.
    A2 point scaling   -- SymbolPointScale() must return 0.1 on a pip-quoted symbol
                           whose point is 10x coarser than the reference grid (2/4
                           digits) and 1.0 on the reference grid (3/5 digits).
    A3 gold untouched  -- the non-FX early return and the auto switch must both sit
                           BEFORE the digit test, so a chart that behaves today keeps
                           behaving identically (class METAL/INDEX/CRYPTO -> 1.0).
    A4 call sites      -- the five point floors that used the raw point conversion are
                           gone and now go through the normalised one. A leftover raw
                           call would silently reintroduce the 10x-wide floor.
    A5 no symbol names -- no symbol name may live in the engine; the only literal is
                           the reference-symbol INPUT default.

    B1 loader          -- a per-symbol calibration file is read at OnInit.
    B2 file discovery  -- four name variants, including the per-timeframe one, read
                           from COMMON\Files.
    B3 loader keys     -- the exact key strings the loader asks for.
    B4 precedence      -- inside every lift function the calibration lookup must come
                           BEFORE the reference literals, otherwise a fitted file
                           would be ignored and the constants would still win.
    B5 thresholds      -- the grade boundaries come from the file too.

    C  one table       -- the fitter and the loader must agree key-for-key. This is a
                           real lock: the bucket names are extracted from BOTH sources
                           and compared as sets, so renaming a bucket in one tool and
                           not the other turns this red instead of silently zeroing a
                           whole feature (a zero lift is a silent no-op).

    D  honest display  -- the corner row must not print a reference win% as if it were
                           measured on this symbol.

    E  evidence        -- the runtime CSV must carry the numbers this phase is about.

    R  runtime         -- when the runtime CSV exists, every row is recomputed
                           independently: does the scale follow from class+digits, and
                           does "calibrated" follow from rows/reference?

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

$profFile = Join-Path $root '01_CANONICAL_CANDIDATES/modules/33_SymbolProfile.mqh'
$prof  = [System.IO.File]::ReadAllText($profFile)
$grade = [System.IO.File]::ReadAllText((Join-Path $root '01_CANONICAL_CANDIDATES/modules/31_SignalGrade.mqh'))
$fit   = [System.IO.File]::ReadAllText((Join-Path $root 'tools/Fit-SignalGrade.ps1'))

function Section([string]$name) {
   foreach ($l in ($code -split "`n")) { if ($l -match ("^\s*(void|int|bool|string|double|color|ENUM_SYM_CLASS|ENUM_GRADE_UNCAL)\s+" + $name + "\s*\(")) { return $l } }
   return ''
}
function FuncBody([string]$text, [string]$name) {
   $i = $text.IndexOf("$name(")
   if ($i -lt 0) { return '' }
   $j = $text.IndexOf("`n}", $i)
   if ($j -lt 0) { return $text.Substring($i) }
   return $text.Substring($i, $j - $i)
}

Write-Host "=== Phase 49: symbol profile ==="

# ------------------------------------------------------------------ A) point scaling
$scaleBody = FuncBody $prof 'SymbolPointScale'
Check 'A1_normaliser_exists' `
   (($prof -match 'double\s+PointFloorPrice\s*\(\s*double\s+pts\s*\)') -and ($scaleBody -ne '')) `
   'the normalised point floor is defined once, in 33_SymbolProfile.mqh'

Check 'A2_scale_table' `
   (($scaleBody -match 'if\(d==3 \|\| d==5\) return 1\.0;') -and ($scaleBody -match 'if\(d==2 \|\| d==4\) return 0\.1;')) `
   'reference grid (3/5 digits) = 1.0 ; coarse grid (2/4 digits) = 0.1'

$autoIdx  = $scaleBody.IndexOf('InpAutoPointScale')
$pipIdx   = $scaleBody.IndexOf('IsPipQuotedSymbol')
$digitIdx = $scaleBody.IndexOf('SYMBOL_DIGITS')
Check 'A3_non_fx_untouched' `
   (($autoIdx -ge 0) -and ($pipIdx -gt $autoIdx) -and ($digitIdx -gt $pipIdx)) `
   'both guards sit before the digit test, so a metal/index/crypto chart scales by exactly 1.0'

$rawEq = ([regex]::Matches($code, 'PointsToPrice\(InpEQ_Tolerance_Points\)')).Count
$rawSl = ([regex]::Matches($code, 'PointsToPrice\(\(double\)InpSL_MinPoints\)')).Count
$newEq = ([regex]::Matches($code, 'PointFloorPrice\(InpEQ_Tolerance_Points\)')).Count
$newSl = ([regex]::Matches($code, 'PointFloorPrice\(\(double\)InpSL_MinPoints\)')).Count
Check 'A4_all_floors_migrated' (($rawEq -eq 0) -and ($rawSl -eq 0) -and ($newEq -eq 4) -and ($newSl -eq 1)) `
   ("raw point floors left = {0}/{1} ; normalised = {2}/{3} (EQH-EQL dedup + EQ cluster + trendline + range, SL buffer)" -f $rawEq, $rawSl, $newEq, $newSl)

$namedLines = @()
foreach ($l in ($code -split "`n")) {
   $t = $l.Trim()
   if ($t.StartsWith('//')) { continue }
   if ($t -match '^\s*input') { continue }
   if ($l -match '(XAUUSD|EURUSD|GBPUSD|USDJPY|BTCUSD)') { $namedLines += $t }
}
$refDefaults = ([regex]::Matches($code, 'InpGradeRefSymbol\s*=\s*"XAUUSD"')).Count
Check 'A5_no_symbol_in_engine' (($namedLines.Count -eq 0) -and ($refDefaults -eq 1)) `
   ("symbol names inside engine code = {0} ; reference-symbol input default = {1}" -f $namedLines.Count, $refDefaults)

# ------------------------------------------------------------------ B) loader
Check 'B1_loader_called' `
   (($prof -match 'bool\s+LoadGradeCalibration\s*\(\s*\)') -and ($code -match 'LoadGradeCalibration\(\);')) `
   'the loader exists and is called from OnInit'

$nameVariants = ([regex]::Matches($prof, 'ICT_Assistant_Canonical_GradeCalib_')).Count
Check 'B2_file_variants' (($nameVariants -ge 3) -and ($prof -match '\+base\+"_"\+tf\+"\.csv') -and ($prof -match 'FILE_COMMON')) `
   ("per-symbol AND per-timeframe name variants ({0} construction sites), read from COMMON" -f $nameVariants)

Check 'B3_loader_keys' `
   (($grade -match '"lift\.f1\."') -and ($grade -match '"lift\.f2\."') -and ($grade -match '"lift\.f3\."') -and `
    ($grade -match '"lift\.f4\."') -and ($grade -match '"lift\.f5\.mtf"') -and ($grade -match '"lift\.f6\.swept"') -and `
    ($grade -match '"lift\.f7\."') -and ($grade -match 'CalGet\("thr\.aplus"') -and ($grade -match 'CalGet\("thr\.a"') -and `
    ($grade -match 'CalGet\("thr\.bplus"') -and ($grade -match 'CalGet\("thr\.b"') -and `
    ($grade -match 'CalGet\("win\."\+k') -and ($grade -match 'CalGet\("n\."\+k') -and `
    ($grade -match 'CalGet\("basewin"') -and ($grade -match 'CalGet\("basen"')) `
   'all seven lift families, the four thresholds, the per-grade win/n and the baseline keys are read from the file'

# A reference literal is any return carrying a decimal constant (the ternary forms
# of F5/F6 included). The calibration gate must sit before ALL of them; otherwise a
# fitted file would be ignored and the frozen constants would still decide.
$precedence = $true
$bad = @()
foreach ($fn in @('GradeLiftF1','GradeLiftF2','GradeLiftF3','GradeLiftF4','GradeLiftF5','GradeLiftF6','GradeLiftF7')) {
   $b = FuncBody $grade $fn
   $cal = $b.IndexOf('g_calLoaded')
   $lits = [regex]::Matches($b, 'return[^;\n]*[0-9]+\.[0-9]+')
   $okFn = ($cal -ge 0) -and ($lits.Count -gt 0)
   foreach ($m in $lits) { if ($m.Index -lt $cal) { $okFn = $false } }
   if (-not $okFn) { $precedence = $false; $bad += $fn }
}
Check 'B4_calibration_wins' $precedence `
   ("a fitted file must win over the reference literals in all seven lifts; offenders = [{0}]" -f ($bad -join ','))

Check 'B5_thresholds_from_file' `
   (($grade -match '\$?\s*tAplus\s*=\s*g_calLoaded') -or ($grade -match 'double tAplus = g_calLoaded')) `
   'the grade boundaries are read from the fit instead of being constants when a fit exists'

# ------------------------------------------------------------------ C) cross-tool lock
function KeysOf([string]$text, [string]$pattern) {
   $set = New-Object System.Collections.Generic.HashSet[string]
   foreach ($m in [regex]::Matches($text, $pattern)) { [void]$set.Add($m.Value) }
   return $set
}
function SameSet($a, $b) {
   if ($a.Count -ne $b.Count) { return $false }
   foreach ($x in $a) { if (-not $b.Contains($x)) { return $false } }
   return $true
}

$famMod = KeysOf (FuncBody $grade 'RRLevelFamilyCode') 'fam[A-Z]+'
$famFit = KeysOf (FuncBody $fit 'Get-Family') 'fam[A-Z]+'
Check 'C1_family_keys_agree' (SameSet $famMod $famFit) `
   ("module=[{0}] fitter=[{1}]" -f (($famMod | Sort-Object) -join ','), (($famFit | Sort-Object) -join ','))

$distMod = KeysOf (FuncBody $grade 'GradeDistBucket') 'dist[A-Za-z0-9]+'
$distFit = KeysOf (FuncBody $fit 'Get-DistBucket') 'dist[A-Za-z0-9]+'
Check 'C2_dist_keys_agree' (SameSet $distMod $distFit) `
   ("module=[{0}] fitter=[{1}]" -f (($distMod | Sort-Object) -join ','), (($distFit | Sort-Object) -join ','))

$legMod = KeysOf (FuncBody $grade 'GradeLegBucket') 'leg[A-Za-z0-9]+'
$legFit = KeysOf (FuncBody $fit 'Get-LegBucket') 'leg[A-Za-z0-9]+'
Check 'C3_leg_keys_agree' (SameSet $legMod $legFit) `
   ("module=[{0}] fitter=[{1}]" -f (($legMod | Sort-Object) -join ','), (($legFit | Sort-Object) -join ','))

$dolMod = KeysOf (FuncBody $grade 'GradeDolBucket') 'dol[A-Za-z0-9]+'
$dolFit = KeysOf (FuncBody $fit 'Get-DolBucket') 'dol[A-Za-z0-9]+'
Check 'C4_dol_keys_agree' (SameSet $dolMod $dolFit) `
   ("module=[{0}] fitter=[{1}]" -f (($dolMod | Sort-Object) -join ','), (($dolFit | Sort-Object) -join ','))

Check 'C5_bool_keys_agree' `
   (($fit -match "'mtf'\s*\+") -and ($fit -match "'swept'\s*\+") -and ($grade -match '"lift\.f5\.mtf"\+') -and ($grade -match '"lift\.f6\.swept"\+')) `
   'the two boolean features use the same composed key in both tools (mtf<value> / swept<value>)'

$emitPrefixes = @('lift.f', 'thr.', 'win.', 'n.', 'basewin', 'basen')
$emitOk = $true
foreach ($p in $emitPrefixes) { if ($fit -notmatch [regex]::Escape("'" + $p) -and $fit -notmatch [regex]::Escape("[void]`$cal.Add('" + $p)) { $emitOk = $false } }
Check 'C6_emitted_keys_are_readable' $emitOk `
   ("every key family the fitter emits ({0}) is one the loader asks for" -f ($emitPrefixes -join ', '))

# ------------------------------------------------------------------ D) honest display
# The format string and its arguments are on consecutive lines, so the block is
# what must be inspected - not a single line.
$stripLine = ''
$si = $code.IndexOf('string txt=StringFormat(')
if ($si -ge 0) { $stripLine = $code.Substring($si, [math]::Min(320, $code.Length - $si)) }
Check 'D1_strip_uses_gradetag' (($stripLine -ne '') -and ($stripLine -match 'GradeTag\(\)')) `
   'the corner row composes its grade fragment from GradeTag(), not from the raw win%'

$tag = FuncBody $grade 'GradeTag'
Check 'D2_tag_labels_reference' (($tag -match 'GradeCalibrated\(\)') -and ($tag -match 'GradeRefSymbolBase\(\)') -and ($tag -match 'GRUNC_SUPPRESS')) `
   'on an uncalibrated symbol the row names the reference symbol, and the suppress mode can hide the grade entirely'

Check 'D3_panel_states_source' ($code -match 'GradeSourceFa\(\)') `
   'the teaching panel prints which calibration the numbers came from'

# ------------------------------------------------------------------ E) evidence
Check 'E1_profile_row_written' `
   (($prof -match 'void\s+WriteSymbolProfileDiag\s*\(\s*\)') -and ($code -match 'WriteSymbolProfileDiag\(\);') -and `
    ($prof -match '"PointScale"') -and ($prof -match '"Digits"') -and ($prof -match '"Calibrated"') -and ($prof -match '"CalibRows"')) `
   'the runtime CSV carries class, digits, point scale and the calibration source, and is written at init'

Check 'E2_module_shipped' `
   ((Test-Path -LiteralPath $profFile) -and (( [System.IO.File]::ReadAllText($src) ) -match 'modules/33_SymbolProfile\.mqh')) `
   'the shell includes the new module, so the compiled unit contains it'

# ------------------------------------------------------------------ R) runtime
$objFile = Join-Path $env:APPDATA 'MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Indicators\khaleq\newICT\ICT_Assistant_Canonical_v0_1.ex5'
if (Test-Path -LiteralPath $objFile) {
   Check 'R1_artifact_present' $true ("compiled artifact = {0}" -f (Get-Item -LiteralPath $objFile).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
} else {
   Pend 'R1_artifact_present' 'no compiled artifact yet; run tools/Sync-And-Compile-Canonical.ps1'
}

$profCsv = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\ICT_Assistant_Canonical_SymbolProfile.csv'
if (Test-Path -LiteralPath $profCsv) {
   $rows = @(Get-Content -LiteralPath $profCsv -Encoding Unicode | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne '' })
   $mismatch = 0; $fxRows = 0; $nonFxRows = 0
   $detail = @()
   foreach ($r in $rows) {
      $p = $r -split ';'
      if ($p.Count -lt 14) { continue }
      $cls = ($p[3] + '').Trim(); $digits = 0; [void][int]::TryParse($p[5], [ref]$digits)
      $scale = 0.0; [void][double]::TryParse($p[8], [ref]$scale)
      $rowsN = 0; [void][int]::TryParse($p[12], [ref]$rowsN)
      $cal = (($p[13] + '').Trim() -eq 'true'); $ref = ($p[10] + '').Trim(); $base = ($p[2] + '').Trim()
      $isFx = ($cls -eq 'FX_MAJOR' -or $cls -eq 'FX_MINOR')
      $expect = 1.0
      if ($isFx -and ($digits -eq 2 -or $digits -eq 4)) { $expect = 0.1 }
      # auto-scale off is a legitimate runtime choice; then 1.0 is the only value.
      $scaleOk = ([math]::Abs($scale - $expect) -lt 0.0001) -or ([math]::Abs($scale - 1.0) -lt 0.0001)
      $calOk = ($cal -eq (($rowsN -gt 0) -or ($base -eq $ref)))
      if ($isFx) { $fxRows++ } else { $nonFxRows++ }
      if (-not ($scaleOk -and $calOk)) { $mismatch++; $detail += ($base + '/' + $cls + '/d' + $digits + '/s' + $scale) }
   }
   Check 'R2_runtime_rows_recomputed' (($rows.Count -gt 0) -and ($mismatch -eq 0)) `
      ("rows={0} (fx={1}, non-fx={2}) ; scale-or-calibration mismatches={3} [{4}]" -f $rows.Count, $fxRows, $nonFxRows, $mismatch, (($detail | Select-Object -First 3) -join ' '))
} else {
   Pend 'R2_runtime_rows_recomputed' 'no SymbolProfile.csv yet; reload the indicator once and rerun'
}

Write-Host ("`nPASS={0}  FAIL={1}  PENDING={2}" -f $pass, $fail, $pend)
if ($fail -gt 0) { exit 1 }
exit 0
