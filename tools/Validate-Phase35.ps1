# Validate-Phase35.ps1 - lock tool for Phase 35 (single-line risk strip)
# ASCII-only by project rule: PowerShell 5.1 parses .ps1 as ANSI (phase-28 lesson).
$ErrorActionPreference='Stop'
$src = Get-Content -Raw -Encoding UTF8 '01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5'
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
Assert 'strip body reads g_rrLabel'    'RenderRiskStrip\(\)\s*\{[\s\S]{0,600}?g_rrLabel'
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
Assert 'strip shows level [state] ATR' '\[%s\] %s ATR'
Assert 'strip feeds from g_rrLegProg'  'g_rrLegProg\)'
Assert 'strip shows SFP marker'        'SFP'
Assert 'strip shows Bias prefix'       'StringFormat\("Bias: %s'
# strip color must come from the phase-32 engine's score (g_rrScore is owned by UpdateReverseRisk)
Assert 'linked to phase-32 engine'     'g_rrScore>=50\? InpColorBear'

Write-Host ''
Write-Host ("Phase35 validation: PASS={0} FAIL={1}" -f $pass,$fail)
if($fail -gt 0){ exit 1 } else { exit 0 }
