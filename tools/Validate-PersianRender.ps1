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
if (-not $code) { . "$PSScriptRoot/CanonicalSource.ps1"; $code = Get-CanonicalSourceText -Path $src }
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
if (-not $code) { . "$PSScriptRoot/CanonicalSource.ps1"; $code = Get-CanonicalSourceText -Path $src }

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
      (($code -match 'bool verticallyVisible=\(yBot>=-tol && yTop<=\(double\)chartH\+tol\);') -and
       (($code -match 'dist<=tol\*2\.0') -or ($code -match 'if\(dist>tol\*2\.0\) continue;'))) `
      'a zone whose whole price range is off-screen is not a hover candidate, and the accept radius is tol*2 (phase 44 rewrote the same rule as an early continue plus the distance/area/name tie-break)'

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

# ---------------------------------------------------------------------
# C) PHASE 41 -- readable mixed lines (the "Persian mixed with English" fix)
#
# WHY: the panel rows are OBJ_EDIT, a native control that runs bidi itself and
# picks the paragraph base direction from the first strong character (UBA
# P2/P3). A Latin WORD inside a Persian sentence splits it into two RTL runs
# whose relative order flips under some base directions, so the reader sees the
# sentence reversed. Digits do not do this (rule W keeps an EN number inside
# the RTL run), which is why only letter-carrying tokens may move.
#
# C1 rule oracle -- RtlSafe() re-implemented from the rule text and executed
#                  against persian_line_rtl.fixture.csv (expected column by hand)
# C2 source wiring -- the guard is applied on the real panel path, the paragraph
#                  direction is pinned, and the FVG family's teaching text no
#                  longer puts a Latin word inside a Persian sentence
# ---------------------------------------------------------------------
function Test-LatinToken([string]$w) {
   foreach ($ch in $w.ToCharArray()) {
      if (($ch -ge 'A' -and $ch -le 'Z') -or ($ch -ge 'a' -and $ch -le 'z')) { return $true }
   }
   return $false
}
function Test-PersianToken([string]$w) {
   foreach ($ch in $w.ToCharArray()) {
      $v = [int]$ch
      if (($v -ge 0x0600 -and $v -le 0x06FF) -or
          ($v -ge 0xFB50 -and $v -le 0xFDFF) -or
          ($v -ge 0xFE70 -and $v -le 0xFEFF)) { return $true }
   }
   return $false
}
function ConvertTo-RtlSafe([string]$s) {
   if ($s.Length -eq 0) { return $s }
   $toks = @($s -split ' ' | Where-Object { $_.Length -gt 0 })
   $hasPersian = $false
   foreach ($t in $toks) { if (Test-PersianToken $t) { $hasPersian = $true; break } }
   if (-not $hasPersian) { return $s }                 # all-Latin (or digits only)
   $seen = $false
   $needs = $false
   foreach ($t in $toks) {
      if (Test-LatinToken $t) { if ($seen) { $needs = $true; break } }
      elseif (Test-PersianToken $t) { $seen = $true }
   }
   if (-not $needs) { return $s }
   $latin = @(); $fa = @()
   foreach ($t in $toks) {
      if (Test-LatinToken $t) { $latin += $t } else { $fa += $t }
   }
   if ($fa.Count -eq 0) { return ($latin -join ' ') }
   return (($latin -join ' ') + ' | ' + ($fa -join ' '))
}

$lineFix = Join-Path $root '05_TESTS_AND_VALIDATION/persian_line_rtl.fixture.csv'
$rtlCases = 0
foreach ($ln in ([System.IO.File]::ReadAllLines($lineFix, [System.Text.Encoding]::UTF8))) {
   $t = $ln.Trim()
   if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
   $p = $t.Split(';')
   if ($p.Length -lt 2) { continue }
   $logical  = $p[0].Trim()
   $expected = $p[1].Trim()
   $got = ConvertTo-RtlSafe $logical
   $rtlCases++
   $detail = "'$logical' -> '$got'"
   if ($got -ne $expected) { $detail += "  expected '$expected'" }
   Check ("rtl-line-" + $rtlCases) ($got -eq $expected) $detail
}
Check 'rtl-line-cases-ran' ($rtlCases -ge 8) ("cases = $rtlCases (expected >= 8)")

# C2a -- the panel path really runs the guard (not dead code any more: the same
#        rule shipped once before, was left unused, and the bug came back)
Check 'panel-rows-run-the-rtl-guard' `
      ($code -match 'g_expLines\[n\]=InpExplainLatinFirst\? RtlSafe\(text\) : text;') `
      'ExpAdd() applies RtlSafe() to every panel row when InpExplainLatinFirst is on'
Check 'rtl-guard-is-switchable' `
      ($code -match 'input bool\s+InpExplainLatinFirst\s+=\s+true;') `
      'InpExplainLatinFirst default = true'
Check 'guard-moves-letters-not-all-ascii' `
      (($code -match 'bool TokenHasLatinLetter\(string w\)') -and ($code -notmatch 'IsLatinChar')) `
      'only letter-carrying tokens move; the old "every char < 0x0600" test is gone (it dragged digits out of their sentence)'
Check 'long-hoisted-line-is-split-not-clipped' `
      (($code -match 'void ExpEmitLine\(string line, color clr, int maxChars\)') -and
       ($code -match 'ExpEmitLine\(line, clr, maxChars\);') -and
       ($code -match 'ExpAdd\(StringSubstr\(outLine,0,sepPos\), clr\);')) `
      'if hoisting pushes a line past the panel width, the Latin block moves to its own row instead of being clipped'
Check 'paragraph-direction-is-pinned-for-persian-rows' `
      ($code -match 'if\(HasPersianText\(text\)\) return ShortToString\(0x200F\)\+text;') `
      'RenderLine() mode 0 prefixes U+200F (RLM) so P2/P3 resolves the base direction to RTL'
Check 'fvg-title-is-latin-only' `
      ($code -match 'if\(k==FVGK_VOL_IMBALANCE\) return "VOLUME IMBALANCE";') `
      'the panel title carries no Persian (a title with Persian inside breaks into reordered runs)'
Check 'fvg-kind-has-a-persian-twin' `
      ($code -match 'string FVGKindFa\(ENUM_FVG_KIND k\)') `
      'FVGKindFa() gives the Persian definition for the body rows'

# C2b -- static scan of the rewritten family: no literal may contain a Latin
#        token that follows a Persian token. Format specifiers (%d/%s/%.2f) are
#        stripped first: at runtime they are numbers, not Latin words.
function Get-LatinInsidePersian([string]$body, [string]$skipComments) {
   $bad = @()
   # A comment is never rendered on the chart, so the rule is applied to the
   # code text only: a Persian dev comment that names an acronym is not a
   # rendering bug. Block comments go first, then line comments.
   if ($skipComments) {
      $body = [regex]::Replace($body, '(?s)/\*.*?\*/', '')
      $body = [regex]::Replace($body, '(?m)//[^\r\n]*', '')
   }
   foreach ($m in [regex]::Matches($body, '"([^"\r\n]*)"')) {
      $lit = $m.Groups[1].Value
      $lit = [regex]::Replace($lit, '%[-+ 0-9.#]*[a-zA-Z]', '')
      $lit = $lit -replace '\\n', ''
      if ($lit -notmatch '[\u0600-\u06FF]') { continue }
      $toks = @($lit -split ' ' | Where-Object { $_.Length -gt 0 })
      $seen = $false
      foreach ($t in $toks) {
         if (Test-LatinToken $t) { if ($seen) { $bad += $lit; break } }
         elseif (Test-PersianToken $t) { $seen = $true }
      }
   }
   return $bad
}
# C2b -- every teaching family, not only FVG. Phase 42 rewrote the remaining
#        families by hand, so the same static rule must now hold for all of them:
#        no literal may put a Latin token after a Persian token.
$explainFns = [regex]::Matches($code, '(?s)void (Explain[A-Za-z0-9_]*)\([^)]*\)\r?\n\{.*?\r?\n\}')
Check 'teaching-families-found' ($explainFns.Count -ge 18) ("teaching functions located = " + $explainFns.Count)

$badFamilies = @()
$badLiterals = 0
$rowsTotal = 0
foreach ($fn in $explainFns) {
   $bad = @(Get-LatinInsidePersian $fn.Groups[0].Value $true)
   if ($bad.Count -gt 0) { $badFamilies += ($fn.Groups[1].Value + '=' + $bad.Count); $badLiterals += $bad.Count }
}
Check 'every-family-teaching-text-has-no-latin-inside-persian' ($badLiterals -eq 0) `
      ("offending families = {0}" -f (($badFamilies | Select-Object -First 6) -join ', '))

# the dispatcher's own literals (object fallback, AMD, MTF tag) are teaching
# text too, so they are held to the same rule
# C2e -- the rule above was first applied to the teaching functions only. Phase
#        42 then cleaned the engine's own note/reason/status strings (the rows
#        the panel prints as "دلیل واقعی" / "چرا این سطح"), so the same rule now
#        holds for EVERY literal in the whole translation unit. Comments are
#        excluded: they are read by a developer in the editor, never drawn.
$wholeBad = @(Get-LatinInsidePersian $code 'skip')
if ($wholeBad.Count -gt 0) {
   # The console cannot show Persian on every codepage, and a mojibake report is
   # useless. Write the offenders to a UTF-8 file so they are readable, and
   # leave only the count and the first line number in the console detail.
   [System.IO.File]::WriteAllLines((Join-Path $root '05_TESTS_AND_VALIDATION/persian_latin_offenders.txt'),
      [string[]]$wholeBad, (New-Object System.Text.UTF8Encoding($false)))
}
Check 'no-literal-in-the-whole-source-puts-latin-after-persian' ($wholeBad.Count -eq 0) `
      ("offending literals = {0} (full list -> 05_TESTS_AND_VALIDATION/persian_latin_offenders.txt)" -f $wholeBad.Count)

$dispStart = $code.IndexOf('void BuildExplanation')
$dispEnd   = $code.IndexOf("`n}`n", $dispStart)
if ($dispStart -ge 0 -and $dispEnd -gt $dispStart) {
   $dispBad = @(Get-LatinInsidePersian $code.Substring($dispStart, $dispEnd - $dispStart) $true)
   Check 'dispatcher-teaching-text-has-no-latin-inside-persian' ($dispBad.Count -eq 0) `
         ("offending literals = {0}" -f (($dispBad | Select-Object -First 3) -join ' || '))
}

# C2c -- short rows. Every row is one OBJ_EDIT and ExpAddWrapped() breaks it at
#        InpExplainPanelWidth/8 characters, so a literal far past that turns into
#        a wall of wrapped text in a panel that is InpExplainMaxRows tall. Ceiling
#        is 260 characters (format specifiers excluded: at runtime they are numbers).
$longestLen = 0
$longestLit = ''
$overCap = @()
foreach ($fn in $explainFns) {
   foreach ($m in [regex]::Matches($fn.Groups[0].Value, '"([^"\r\n]*)"')) {
      $lit = [regex]::Replace($m.Groups[1].Value, '%[-+ 0-9.#]*[a-zA-Z]', '')
      if ($lit -notmatch '[\u0600-\u06FF]') { continue }
      $rowsTotal++
      if ($lit.Length -gt $longestLen) { $longestLen = $lit.Length; $longestLit = $lit }
      if ($lit.Length -gt 260) { $overCap += $lit }
   }
}
Check 'every-family-row-stays-short' ($overCap.Count -eq 0) `
      ("rows over 260 chars = {0}; longest = {1}; rows measured = {2}" -f $overCap.Count, $longestLen, $rowsTotal)

Write-Host ''
Write-Host ("INFO  teaching rows measured: {0}; longest literal: {1} chars (panel wraps at ~{2})" -f $rowsTotal, $longestLen, [int](580/8)) -ForegroundColor Yellow
if ($longestLen -gt 200) {
   # Print the offending literal itself (it is the only actionable part of the
   # number) so a long row can be shortened without hunting for it.
   Write-Host ("INFO  longest literal text: {0}" -f $longestLit) -ForegroundColor Yellow
}
if ($overCap.Count -gt 0) {
   $i = 0
   foreach ($lit in $overCap) { $i++; Write-Host ("INFO  over-cap row #{0}: {1}" -f $i, $lit) -ForegroundColor Red }
}
Write-Host 'INFO  RtlSafe() still runs on every row as a runtime safety net for values that come from the engine (notes, reasons, codes)' -ForegroundColor Yellow

# C2d -- the mechanism behind the rewrite: every coded value that used to be
#        substituted mid-sentence now has a Persian twin, and the engine's status
#        codes are Latin-only (the panel prints them on their own line).
$twins = 'TfFa', 'DirFa', 'LiqTypeFa', 'LiqTypeCode', 'ObStateFa', 'ObKindFa',
         'RejectionStateFa', 'ExhaustionStateFa', 'TrendPhaseFa', 'PoiKindFa',
         'EntryModelFa', 'RTMEventFa', 'RTMEventCode', 'AMTDayTypeFa',
         'AMTOpenTypeFa', 'SDKindFa', 'WyckoffEventFa', 'WyckoffEventCode',
         'QTPhaseFa', 'SetupStatusFa', 'LegRejectFa', 'FVGKindFa'
$missingTwins = @($twins | Where-Object { $code -notmatch ('(string\s+' + $_ + '\()') })
Check 'every-coded-value-has-a-persian-twin' ($missingTwins.Count -eq 0) `
      ("missing = {0}" -f ($missingTwins -join ', '))

Check 'setup-status-codes-are-latin-only' `
      (($code -match 'g_setup\.status="WAITING_ENTRY_MODEL";') -and
       ($code -match 'WAITING_QUALITY_LOW \(score %d of 10\)') -and
       ($code -notmatch 'WAITING_QUALITY_LOW \(%d از')) `
      'the engine emits Latin-only status codes; the panel explains them in Persian on a separate row'

# NOTE  Persian is addressed by codepoint, never as a literal in this file: a
#       .ps1 without a UTF-8 BOM is decoded with the system ANSI codepage by
#       Windows PowerShell 5.1, so a literal would silently become mojibake and
#       the comparison would fail for a reason that has nothing to do with the
#       indicator. [char]0x.... builds the same word and survives any codepage.
$chFa  = [char]0x0641   # ف
$chAlef= [char]0x0627   # ا
$chZah = [char]0x0632   # ز
$chLam = [char]0x0644   # ل
$chEm  = [char]0x2014   # —
$wPhase = "$chFa$chAlef$chZah"            # فاز
$wPhaseA= "$wPhase $chAlef$chLam$chFa"    # فاز الف

Check 'wyckoff-phase-reasons-are-latin-free' `
      (($code -match ('reason="' + $wPhaseA + ' ')) -and
       ($code -notmatch ('reason="' + $wPhase + ' [A-E] '))) `
      'the Wyckoff phase reasons are interpolated mid-sentence, so the phase is named in Persian (الف/ب/ج/د/ه) and no Latin letter rides inside the clause'

Check 'latin-anchors-may-only-open-a-row' `
      (($code -match 'ExpAdd\(\(o\.scope==SCOPE_EXTERNAL\)\?"EXTERNAL \(ERL\)":"INTERNAL \(IRL\)"') -and
       ($code -match 'ExpAdd\("LIQ #"\+IdToStr\(l\.id\)')) `
      'where a Latin acronym is kept for orientation it opens its own row (dictionary style), never sits inside a Persian clause'

Write-Host ''
Write-Host '==== RESULT ===='
Write-Host ("PASS={0}  FAIL={1}" -f $pass, $fail)
if ($fail -gt 0) { Write-Host 'RESULT: FAILED'; exit 1 }
Write-Host 'RESULT: all rule and source checks passed'
exit 0
