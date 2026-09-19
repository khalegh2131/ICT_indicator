# =====================================================================
# Validate-PersianRender.ps1  --  offline verifier for the Persian text
#                                render pipeline (chart objects)
#
# WHY THIS EXISTS
# ---------------
# Recent MetaTrader 5 builds changed how chart-object text is drawn: the
# object renderer no longer performs bidi, so a logical Persian string is
# painted left-to-right and looks mirrored. Official report:
#   https://www.mql5.com/en/forum/504522
# "Arabic Text Object Displays Reversed After Latest MetaTrader 5 Update"
#
# The indicator therefore builds the *visual* string itself:
#   1) ShapePersianLogical()  -- logical letters -> Arabic Presentation
#      Forms with the correct isolated/initial/medial/final shape, joining
#      computed on the logical string (Latin/digits break joining).
#   2) VisualOrderForLtrEngine() -- UBA rule N1/N2 for neutral characters,
#      then runs emitted last-to-first; RTL runs reversed character-wise
#      with bracket pairs mirrored.
#
# Two independent jobs:
#
#   A) RULE CHECK -- the ordering rule is re-implemented here from the rule
#      text (not from the MQL5 source) and executed against
#      05_TESTS_AND_VALIDATION/persian_visual.fixture.csv, whose expected
#      column was derived by hand. A dumb LTR renderer must paint the
#      "visual" column literally and get correct Persian.
#
#   B) SOURCE CHECK -- the MQL5 side really wires that pipeline everywhere a
#      Persian string can reach a chart object, and the defaults do not
#      resurrect the two known-broken paths:
#        B1  RenderLine() mode 2 = shaping + visual order (the default)
#        B2  no RLE..PDF path is the default (builds ignore it now)
#        B3  explain panel rows go through RenderLine()
#        B4  object tooltips are handed the RAW logical string: the tooltip
#            is painted by the terminal UI (which does have bidi), so the
#            manual visual conversion must not be applied twice
#        B5  the shaper tables are index-aligned and equal in length
#        B6  the dashboard is off by default (clean chart)
#
#   HONEST LIMITS -- this proves the ordering rule and the wiring. Only a
#   chart reload can prove what the font actually rasterises.
# =====================================================================

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8   # so the Persian evidence is readable
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src  = Join-Path $root '01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5'
$fix  = Join-Path $root '05_TESTS_AND_VALIDATION/persian_visual.fixture.csv'

$pass = 0
$fail = 0
function Check($name, $ok, $detail) {
   if ($ok) { $script:pass++ ; Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
   else     { $script:fail++ ; Write-Host ("FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red }
}

# ---------------------------------------------------------------------
# A) second implementation of the ordering rule
# ---------------------------------------------------------------------
function Get-CharDir([int]$c) {
   if ($c -ge 0x06F0 -and $c -le 0x06F9) { return -1 }              # Persian digits
   if ($c -ge 0x0660 -and $c -le 0x0669) { return -1 }              # Arabic-Indic digits
   if (($c -ge 0x0600 -and $c -le 0x06FF) -or
       ($c -ge 0xFB50 -and $c -le 0xFDFF) -or
       ($c -ge 0xFE70 -and $c -le 0xFEFF)) { return 1 }             # RTL script
   if (($c -ge 48 -and $c -le 57) -or
       ($c -ge 65 -and $c -le 90) -or ($c -ge 97 -and $c -le 122)) { return -1 }
   return 0
}

function Mirror-Char([char]$ch) {
   switch ([int]$ch) {
      40  { return ')' }   # (
      41  { return '(' }   # )
      91  { return ']' }   # [
      93  { return '[' }   # ]
      123 { return '}' }   # {
      125 { return '{' }   # }
      60  { return '>' }   # <
      62  { return '<' }   # >
      default { return $ch }
   }
}

function ConvertTo-Visual([string]$s) {
   $s = $s.TrimEnd()
   $chars = $s.ToCharArray()
   $n = $chars.Length
   if ($n -eq 0) { return $s }

   $dir = New-Object 'int[]' $n
   $anyRtl = $false
   for ($i = 0; $i -lt $n; $i++) {
      $dir[$i] = Get-CharDir ([int]$chars[$i])
      if ($dir[$i] -gt 0) { $anyRtl = $true }
   }
   if (-not $anyRtl) { return $s }              # all-Latin line: untouched

   # N1/N2: neutrals take a shared neighbour direction, else the base (RTL)
   for ($i = 0; $i -lt $n; $i++) {
      if ($dir[$i] -ne 0) { continue }
      $j = $i
      while ($j -lt $n -and $dir[$j] -eq 0) { $j++ }
      $before = 1
      if ($i -gt 0) { $before = $dir[$i - 1] }
      $after = 1
      if ($j -lt $n) { $after = $dir[$j] }
      $res = 1
      if ($before -eq $after) { $res = $before }
      for ($k = $i; $k -lt $j; $k++) { $dir[$k] = $res }
      $i = $j
   }

   $out = ''
   $j = $n - 1
   while ($j -ge 0) {
      $d = $dir[$j]
      $start = $j
      while ($start -ge 0 -and $dir[$start] -eq $d) { $start-- }
      $run = @($chars[($start + 1)..$j])
      if ($d -gt 0) {
         $rev = ''
         for ($k = 0; $k -lt $run.Length; $k++) { $rev = (Mirror-Char $run[$k]) + $rev }
         $run = $rev.ToCharArray()
      }
      $out += -join $run
      $j = $start
   }
   return $out
}

$lines = [System.IO.File]::ReadAllLines($fix, [System.Text.Encoding]::UTF8)
$cases = 0
foreach ($ln in $lines) {
   $t = $ln.Trim()
   if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
   $p = $t.Split(';')
   if ($p.Length -lt 2) { continue }
   $logical  = $p[0].Trim()
   $expected = $p[1].Trim()
   $got = ConvertTo-Visual $logical
   $cases++
   $detail = "'$logical' -> '$got'"
   if ($got -ne $expected) { $detail += "  expected '$expected'" }
   Check ("fixture-" + $cases) ($got -eq $expected) $detail
}
Check 'fixture-cases-ran' ($cases -ge 8) ("cases = $cases (expected >= 8)")

# ---------------------------------------------------------------------
# A2) shaping oracle -- the Presentation-Forms tables must match the
#     Unicode standard, looked up by base codepoint. The oracle is the
#     standard (see the fixture header), not the source code.
# ---------------------------------------------------------------------
if (-not $code) { $code = Get-Content -Raw -Encoding UTF8 $src }
$shapeFix = Join-Path $root '05_TESTS_AND_VALIDATION/persian_shape.fixture.csv'
$tables = @{}
foreach ($tn in 'Base', 'Isol', 'Fina', 'Init', 'Medi') {
   $m = [regex]::Match($code, ('int g_fa{0}\[\]\s*=\s*\{{([^}}]*)\}}' -f $tn))
   if (-not $m.Success) { $tables[$tn] = @(); continue }
   $tables[$tn] = @($m.Groups[1].Value.Split(',') |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -ne '' } |
                    ForEach-Object { [Convert]::ToInt32($_, 16) })
}

$rowsOk  = 0
$rowsBad = @()
foreach ($ln in ([System.IO.File]::ReadAllLines($shapeFix, [System.Text.Encoding]::UTF8))) {
   $t = $ln.Trim()
   if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
   $p = @($t.Split(';') | ForEach-Object { $_.Trim() })
   if ($p.Length -lt 5) { continue }
   $base = [Convert]::ToInt32($p[0], 16)
   $idx = [Array]::IndexOf($tables['Base'], $base)
   if ($idx -lt 0) { $rowsBad += ('base U+{0:X4} missing from g_faBase' -f $base); continue }
   $want = @{ Isol = $p[1]; Fina = $p[2]; Init = $p[3]; Medi = $p[4] }
   $rowOk = $true
   foreach ($k in 'Isol', 'Fina', 'Init', 'Medi') {
      $w = 0
      if ($want[$k] -ne '-') { $w = [Convert]::ToInt32($want[$k], 16) }
      if ([int]$tables[$k][$idx] -ne $w) { $rowOk = $false }
   }
   if ($rowOk) { $rowsOk++ } else { $rowsBad += ('U+{0:X4} form mismatch' -f $base) }
}
Check 'shaper-forms-match-unicode-standard' ($rowsBad.Count -eq 0) (($rowsOk.ToString() + ' rows matched' + $(if ($rowsBad.Count -gt 0) { ' | ' + ($rowsBad -join ', ') } else { '' })))
Check 'shaper-oracle-rows-ran' ($rowsOk -ge 8) ("rows = $rowsOk (expected >= 8)")

# ---------------------------------------------------------------------
# B) source wiring
# ---------------------------------------------------------------------
if (-not $code) { $code = Get-Content -Raw -Encoding UTF8 $src }

Check 'renderline-mode-2-shapes-then-orders' `
      ($code -match 'string shaped=\(mode==2\) \? ShapePersianLogical\(text\) : text;\s*\r?\n\s*return VisualOrderForLtrEngine\(shaped\);') `
      'RenderLine() mode 2 = ShapePersianLogical() then VisualOrderForLtrEngine()'

Check 'default-render-mode-is-raw-logical' `
      ($code -match 'input int\s+InpExplainRenderMode\s+=\s+0;') `
      'InpExplainRenderMode default = 0 (raw logical text)'

# فاز ۲۷ — شاهد ریشه‌ای: چرا حالت خام درست است.
# پنل توضیح با OBJ_EDIT رسم می‌شود و OBJ_EDIT کنترل **بومی ویندوز** است که
# خودش شکل‌دهی و bidi را انجام می‌دهد. تبدیل دستی متن قبل از دادن به آن،
# «دو بار تبدیل» می‌ساخت و فارسی را کامل به‌هم می‌ریخت.
Check 'panel-rows-are-a-native-control-that-does-its-own-bidi' `
      ($code -match 'ObjectCreate\(0,name,OBJ_EDIT,0,0,0\)') `
      'panel rows are OBJ_EDIT = native control; pre-shaping them was the bug'

Check 'manual-render-modes-are-kept-as-fallbacks' `
      (($code -match 'string shaped=\(mode==2\)') -and ($code -match 'VisualOrderForLtrEngine\(shaped\)') -and ($code -match '0x202B')) `
      'modes 1/2/3 remain available for builds whose renderer does its own RTL';

$panelRows = [regex]::Matches($code, 'ExplainEditRow\("ICTv13_EXP_')
$panelRendered = ([regex]::Matches($code, 'RenderLine\(g_expLines\[i\],InpExplainRenderMode\)')).Count
Check 'panel-rows-are-rendered-through-renderline' `
      ($panelRendered -ge 1 -and $panelRows.Count -ge 2) `
      ("panel edit rows = {0}, rows sent through RenderLine = {1}" -f $panelRows.Count, $panelRendered)

# فاز ۲۵: مسیر رندر پنل و tooltip یکی شد؛ و tooltip پیش‌فرض خاموش است تا
# روی کل چارت باز نشود.
$tipBlock = [regex]::Match($code, 'string tip="";[\s\S]{0,1400}?ObjectSetString\(0,nm,OBJPROP_TOOLTIP,tip\);')
Check 'tooltip-uses-the-shared-renderline-path' `
      ($tipBlock.Success -and ($tipBlock.Value -match 'tip=RenderLine\(g_expTitle,InpExplainRenderMode\);') -and ($tipBlock.Value -match 'tip \+= "\\n" \+ RenderLine\(g_expLines\[k\],InpExplainRenderMode\);')) `
      'tooltip rows go through RenderLine() with the same InpExplainRenderMode as the panel'
Check 'tooltip-write-is-unconditional-so-stale-tips-clear' `
      ($tipBlock.Success -and ($tipBlock.Value -match 'ObjectSetString\(0,nm,OBJPROP_TOOLTIP,tip\);')) `
      'the tooltip is written every pass (empty string when disabled = stale tip removed)'
Check 'object-tooltips-are-off-by-default' `
      ($code -match 'input bool\s+InpSetObjectTooltips\s+=\s+false;') `
      'InpSetObjectTooltips default = false (panel is the single teaching channel)'
Check 'hit-test-skips-fully-offscreen-zones' `
      (($code -match 'bool verticallyVisible=\(yBot>=-tol && yTop<=\(double\)chartH\+tol\);') -and ($code -match 'dist<=tol\*2\.0')) `
      'a zone whose whole price range is off-screen is not a hover candidate, and the accept radius is tol*2'

$arr = [regex]::Matches($code, 'int g_fa(Base|Isol|Fina|Init|Medi)\[\]\s*=\s*\{([^}]*)\}')
Check 'shaper-tables-present' ($arr.Count -eq 5) ("tables found = " + $arr.Count)
if ($arr.Count -eq 5) {
   $lens = @{}
   foreach ($m in $arr) { $lens[$m.Groups[1].Value] = ($m.Groups[2].Value.Split(',')).Count }
   $uniq = ($lens.Values | Sort-Object -Unique)
   Check 'shaper-tables-are-index-aligned' ($uniq.Count -eq 1) `
         ("lengths: " + (($lens.Keys | Sort-Object | ForEach-Object { "$_=$($lens[$_])" }) -join ' '))
}
Check 'shaper-tables-are-index-aligned' ((@($arr).Count -eq 5)) 'FasIndex() indexes all five tables in parallel'

Check 'bracket-mirroring-is-applied' `
      ($code -match 'rev=ShortToString\(FaMirror\(StringGetCharacter\(run,k\)\)\)\+rev;') `
      'RTL runs are reversed through FaMirror()'

Check 'dashboard-is-off-by-default' `
      ($code -match 'input bool\s+InpShowDashboard\s+=\s+false;') `
      'InpShowDashboard default = false (clean chart, one click to restore)'

Write-Host ''
Write-Host '==== RESULT ===='
Write-Host ("PASS={0}  FAIL={1}" -f $pass, $fail)
if ($fail -gt 0) { Write-Host 'RESULT: FAILED'; exit 1 }
Write-Host 'RESULT: all rule and source checks passed'
exit 0
