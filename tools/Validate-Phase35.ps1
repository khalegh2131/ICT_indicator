# Validate-Phase35.ps1 - lock tool for Phase 35 (single-line risk strip)
# ASCII-only by project rule: PowerShell 5.1 parses .ps1 as ANSI (phase-28 lesson).
$ErrorActionPreference='Stop'
# Flatten the module shell the way MQL5 does (see tools/CanonicalSource.ps1).
. "$PSScriptRoot/CanonicalSource.ps1"
$src = Get-CanonicalSourceText -Path '01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5'
$fail=0; $pass=0
function Assert([string]$name,[string]$pattern,[bool]$mustHave=$true){
  $found = $src -match $pattern
  $ok = $found
  if(-not $mustHave){ $ok = (-not $found) }
  if($ok){ $script:pass++; Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green }
  else   { $script:fail++; Write-Host ("  FAIL  {0}" -f $name) -ForegroundColor Red }
}

Write-Host '== Phase 35: risk strip =='
# 1) inputs
Assert 'input InpShowRiskStrip=true'   'input bool\s+InpShowRiskStrip\s*=\s*true'
Assert 'input InpRiskStripY'           'input int\s+InpRiskStripY\s*=\s*2;'
Assert 'input InpRiskStripWidth'       'input int\s+InpRiskStripWidth\s*=\s*640;'
# 2) object names carry the ICTv13_ prefix (OnDeinit ObjectsDeleteAll covers them)
Assert 'bg object ICTv13_RSTRIP_BG'    'ICTv13_RSTRIP_BG'
Assert 'txt object ICTv13_RSTRIP_TXT'  'ICTv13_RSTRIP_TXT'
# 3) rule: display-only - reads g_rr* state of the phase-32 engine, no parallel math
# Phase 46 prepended the grade fields and a width calculation to the same body,
# so the window had to grow; the rule itself is unchanged - the strip still reads
# the phase-32 state and now also reads the fitted grade.
Assert 'strip body reads g_rrLabel'    'RenderRiskStrip\(\)\s*\{[\s\S]{0,1400}?g_rrLabel'
# Phase 48 merged the pending row into this same body and documented the merge in
# a comment block before the string, so the window grew again. The rule itself is
# unchanged - the strip still leads with the fitted grade.
# Phase 49: the strip's grade fragment now comes from GradeTag(), which is what
# decides whether a reference win% may be shown as if it were measured on this
# symbol. The rule is unchanged - the strip still leads with the fitted grade.
Assert 'strip body reads the grade'    'RenderRiskStrip\(\)\s*\{[\s\S]{0,2600}?GradeTag\(\)'
Assert 'no iATR inside strip body'     '(?s)void RenderRiskStrip\(\)[\s\S]{0,3000}iATR\(' $false
# 4) rule: Persian channel = the proven OBJ_EDIT pipeline (raw text, mode 0)
Assert 'renders via ExplainEditRow'    'ExplainEditRow\("ICTv13_RSTRIP_TXT"'
Assert 'same pipeline as panel'        'RenderLine\(txt,InpExplainRenderMode\)'
# 5) rule: performance - text cache + conditional redraw
Assert 'text cache variable'           'string g_riskStripLastText'
Assert 'skip when unchanged'           'if\(g_riskStripOn && txt==g_riskStripLastText\) return;'
Assert 'ChartRedraw call present'      'ChartRedraw\(0\);'
# 6) rule: cleanup - delete-once path when input off
Assert 'delete bg when disabled'       'ObjectDelete\(0,"ICTv13_RSTRIP_BG"\);'
Assert 'delete txt when disabled'      'ObjectDelete\(0,"ICTv13_RSTRIP_TXT"\);'
Assert 'one-shot teardown guard'       'if\(g_riskStripOn\)[\s\S]{0,120}?ObjectDelete\(0,"ICTv13_RSTRIP_BG"\);'
# 7) wiring: both OnCalculate render paths
Assert 'wired: early-tick path'        'RenderDashboard\(\);\s*//[^\r\n]*\s*RenderRiskStrip\(\);'
Assert 'wired: closed-bar path'        'RenderDashboard\(\);\r?\n\s*RenderRiskStrip\(\);'
$cnt=([regex]::Matches($src,'RenderRiskStrip\(\);')).Count
if($cnt -ge 2){ $script:pass++; Write-Host '  PASS  wired: >=2 call sites' -ForegroundColor Green }
else          { $script:fail++; Write-Host '  FAIL  wired: >=2 call sites' -ForegroundColor Red }
# 8) user's three requirements: nearest level + its type + reversal score
# Phase 42 removed the Latin "ATR" from inside this row: the strip still shows
# the nearest level, its state and its distance, but the distance is now spelled
# out in Persian (فاصله ... برابر میانگین دامنه) so the row is one RTL run.
# The word is built from codepoints because Windows PowerShell 5.1 decodes a
# BOM-less .ps1 with the system ANSI codepage, which would mangle a literal.
$chFe=[char]0x0641; $chSad=[char]0x0627; $chSad2=[char]0x0635; $chLam=[char]0x0644; $chHe=[char]0x0647
$wordDist = "$chFe$chSad$chSad2$chLam$chHe"      # فاصله - "distance"
Assert 'strip shows level [state] and its distance' ('\[%s\][^"\r\n]*' + $wordDist)
Assert 'strip feeds from g_rrLegProg'  'g_rrLegProg\)'
Assert 'strip shows SFP marker'        'SFP'
# Phase 46: the row now LEADS with the grade; the bias field moved after it. Both
# labels are still Latin-led, which is what kept the line from splitting.
Assert 'strip shows Bias prefix'       'BIAS: %s'
# Phase 49: the grade is still the FIRST field, but its text is now built by
# GradeTag() so an uncalibrated symbol cannot print the reference numbers bare.
Assert 'strip leads with the grade'    'StringFormat\("%s[\s\S]{0,120}?BIAS: %s[\s\S]{0,240}?GradeTag\(\)'
# strip color must come from the phase-32 engine's score (g_rrScore is owned by UpdateReverseRisk)
Assert 'linked to phase-32 engine'     'g_rrScore>=50\? InpColorBear'

Write-Host ''
Write-Host ("Phase35 validation: PASS={0} FAIL={1}" -f $pass,$fail)
if($fail -gt 0){ exit 1 } else { exit 0 }
