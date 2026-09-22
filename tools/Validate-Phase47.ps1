<#
  Validate-Phase47.ps1  --  locks the pending scenario and per-timeframe evidence

  What is proven, and how:

    S1 wiring    -- the pending module is included, its update runs INSIDE the
                    closed-bar block (exactly once, after the reversal gate), the
                    chart row is rendered next to the risk strip, and the click
                    dispatcher has a PEND branch. A pending row that is computed
                    per tick instead of per closed bar would be a repainting
                    claim, so the call site is checked structurally, not by hope.
    S2 numbers   -- every rate and sample count in 32_PendingScenario.mqh is
                    compared NUMERICALLY with
                    05_TESTS_AND_VALIDATION/pending_scenario.fixture.csv, which
                    tools/Fit-PendingScenario.ps1 generated from the indicator's
                    own evidence ledger. Nothing is compared against a hand list.
    S3 buckets   -- the distance bucket boundaries in the MQL5 source and in the
                    fitting tool must be the same four numbers (0.20 / 0.50 /
                    1.00 / 2.00). Different boundaries would silently re-label
                    every measured rate.
    S4 no writes -- the engine half of the module (everything before the renderer)
                    must contain no file write, no registry append, no bias write
                    and no event append. The pending layer is display-only: with
                    it switched off the analysis must be bit-identical.
    S5 no live price -- the module must never read the current price (Bid/Ask,
                    iClose/iHigh/iLow/iTime at shift 0, SymbolInfo*). That is the
                    whole reason the row cannot repaint: its inputs are closed
                    bars, so its text is constant until the next bar closes.
    S6 per timeframe -- both evidence ledgers now carry the chart timeframe in the
                    file NAME and as a ChartTF column. Two live charts of one
                    symbol used to share one file, so every measurement read from
                    those ledgers mixed two chart timeframes.
    S7 layout    -- the pending row must sit below the risk strip, otherwise the
                    two rows overlap and the top of the chart becomes unreadable.
    R1 runtime   -- if a per-timeframe ledger already exists, its ChartTF column
                    must agree with the timeframe in its own file name. Before a
                    chart reload the new files do not exist yet -> PENDING, which
                    is honest, rather than a green tick on nothing.

  NOTE: ASCII-only by design (PowerShell 5.1 misreads non-BOM UTF-8 sources).
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src  = Join-Path $root '01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5'
$fixture = Join-Path $root '05_TESTS_AND_VALIDATION/pending_scenario.fixture.csv'
$fitTool = Join-Path $root 'tools/Fit-PendingScenario.ps1'
$filesDir = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'

$pass = 0; $fail = 0; $pend = 0
function Check($name, $ok, $detail) {
   if ($ok) { $script:pass++ ; Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
   else     { $script:fail++ ; Write-Host ("FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red }
}
function Pend($name, $detail) { $script:pend++ ; Write-Host ("PEND  {0}  {1}" -f $name, $detail) -ForegroundColor Yellow }
function Num([string]$s) { return [double]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture) }

. "$PSScriptRoot/CanonicalSource.ps1"
$code = Get-CanonicalSourceText -Path $src
$modFile = Join-Path $root '01_CANONICAL_CANDIDATES/modules/32_PendingScenario.mqh'
$mod = Get-Content -LiteralPath $modFile -Raw

# returns the body of a function whose signature line starts with $prefix
function Get-Body([string]$text, [string]$prefix) {
   $i = $text.IndexOf($prefix)
   if ($i -lt 0) { return '' }
   $open = $text.IndexOf('{', $i)
   if ($open -lt 0) { return '' }
   $j = $text.IndexOf("`n}", $open)
   if ($j -lt 0) { return $text.Substring($open) }
   return $text.Substring($open, $j - $open)
}

# ------------------------------------------------------------------ S1 wiring
# The include must be asserted on the SHELL text: the flattened source has the
# includes already replaced by module bodies, so the directive itself is gone.
$shellText = [System.IO.File]::ReadAllText($src)
$incl = ($shellText -match '(?m)^\s*#include\s+"modules/32_PendingScenario\.mqh"\s*$')
Check 'S1a_module_included' $incl 'the shell includes modules/32_PendingScenario.mqh'

$calls = ([regex]::Matches($code, [regex]::Escape('UpdatePendingScenario(atrBuf[1]);'))).Count
Check 'S1b_update_called_once' ($calls -eq 1) ("update call count = {0}" -f $calls)

# The call must sit inside the closed-bar block: after the nearest preceding
# new-bar guard and before the once-per-pass dashboard render, in the same
# segment as the closed-bar context update.
$iCall = $code.IndexOf('UpdatePendingScenario(atrBuf[1]);')
$iNew = -1; $iDash = -1; $seg = ''
if ($iCall -ge 0) {
   $iNew = $code.LastIndexOf('if(isNewBar)', $iCall)
   $iDash = $code.IndexOf('RenderDashboard();', $iCall)
   if ($iNew -ge 0) { $seg = $code.Substring($iNew, $iCall - $iNew) }
}
$insideBar = ($iNew -ge 0 -and $iDash -gt $iCall -and $seg.Contains('UpdateContextForClosedBar'))
Check 'S1c_update_inside_closed_bar' $insideBar `
   ("newBar anchor = {0}, update = {1}, dashboard = {2}" -f $iNew, $iCall, $iDash)

# Phase 48 merged this row INTO the grade strip (one "path" line), so the row is
# no longer rendered by its own function. What must still hold: the fragment is
# built in exactly one place and the strip is the only caller - otherwise the
# same numbers could be rendered twice and drift apart.
$rCalls = ([regex]::Matches($code, [regex]::Escape('PendingFragmentFa();'))).Count
$stripCalls = ($code -match '(?s)void RenderRiskStrip\(\)[\s\S]{0,2600}?PendingFragmentFa\(\)')
Check 'S1d_row_rendered_once' (($rCalls -eq 1) -and $stripCalls) `
   ("fragment call count = {0}, called from the strip = {1}" -f $rCalls, $stripCalls)

$disp = ($code -match 'ExplainPendingScenario\(true\);')
Check 'S1e_click_dispatch' $disp 'clicking the merged row opens this explainer as its second half'

# ------------------------------------------------------------------ S2 numbers
$rows = @{}
foreach ($ln in (Get-Content -LiteralPath $fixture)) {
   $f = $ln.Trim() -split ';'
   if ($f.Count -lt 4) { continue }
   if ($f[0] -eq 'bucket') { continue }
   $rows[$f[0]] = @{ n = [int]$f[1]; hit = [int]$f[2]; rate = Num $f[3] }
}
Check 'S2a_fixture_read' ($rows.Count -ge 3) ("buckets in the fitted fixture = {0}" -f $rows.Count)

$rateBody = Get-Body $mod 'double PendMeasuredRate(string b)'
$nBody = Get-Body $mod 'int PendMeasuredN(string b)'
$mismatch = New-Object System.Collections.ArrayList
foreach ($b in $rows.Keys) {
   $wantR = $rows[$b].rate
   $wantN = $rows[$b].n
   $mR = [regex]::Match($rateBody, ('if\(b=="' + $b + '"\)\s*return\s+([0-9.]+);'))
   $mN = [regex]::Match($nBody, ('if\(b=="' + $b + '"\)\s*return\s+([0-9]+);'))
   if (-not $mR.Success) { [void]$mismatch.Add(($b + ': rate missing in source')); continue }
   if (-not $mN.Success) { [void]$mismatch.Add(($b + ': n missing in source')); continue }
   $gotR = Num $mR.Groups[1].Value
   $gotN = [int]$mN.Groups[1].Value
   if ([math]::Abs($gotR - $wantR) -gt 0.05) { [void]$mismatch.Add(("{0}: rate source {1} vs fitted {2}" -f $b, $gotR, $wantR)) }
   if ($gotN -ne $wantN) { [void]$mismatch.Add(("{0}: n source {1} vs fitted {2}" -f $b, $gotN, $wantN)) }
}
Check 'S2b_table_matches_fixture' ($mismatch.Count -eq 0) ("mismatches = " + ($mismatch -join ' ; '))

# The source must say where the table came from, so a reader can re-measure it.
$prov = ($mod -match 'Fit-PendingScenario\.ps1')
Check 'S2c_provenance_named' $prov 'the module names the tool that produced the table'

# ------------------------------------------------------------------ S3 buckets
$tool = Get-Content -LiteralPath $fitTool -Raw
$srcBuckets = @()
foreach ($m in [regex]::Matches((Get-Body $mod 'string PendBucketCode(double d)'), 'd<([0-9.]+)')) { $srcBuckets += (Num $m.Groups[1].Value) }
$toolBuckets = @()
foreach ($m in [regex]::Matches((Get-Body $tool 'function Get-PendBucket([double]$d)'), '\$d -lt ([0-9.]+)')) { $toolBuckets += (Num $m.Groups[1].Value) }
$sameEdges = (($srcBuckets.Count -eq $toolBuckets.Count) -and ($srcBuckets.Count -ge 3))
if ($sameEdges) { for ($i = 0; $i -lt $srcBuckets.Count; $i++) { if ($srcBuckets[$i] -ne $toolBuckets[$i]) { $sameEdges = $false } } }
Check 'S3a_bucket_edges_identical' $sameEdges ("source = [" + ($srcBuckets -join ',') + "] tool = [" + ($toolBuckets -join ',') + "]")

# ------------------------------------------------------------------ S4 no writes
$engine = $mod
# Phase 48: the presenter of this module now starts at CleanupLegacyPendingRow()
# (the separate row renderer was removed). Everything before it - the state clear,
# the engine and the fragment builder - must still write nothing at all.
$cut = $mod.IndexOf('void CleanupLegacyPendingRow()')
if ($cut -gt 0) { $engine = $mod.Substring(0, $cut) }
# Everything below must look at CODE, not at prose: this module documents the
# words it refuses to use (Bid/Ask, g_htfBias=) inside its own comments, and a
# naive token search would flag its own documentation. Line comments are removed
# first; the module uses no block comments and no '//' inside a literal.
$engineCode = (($engine -split "`n") | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n"
$modCode = ((($mod -split "`n") | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n")

$forbidden = @('FileWrite', 'FileOpen', 'DiagOpen', 'AppendStructureEvent', 'AppendLiquidity',
   'AppendDisplacement', 'ArrayResize(g_', 'ObjectCreate', 'ObjectSetInteger', 'ObjectSetString',
   'ObjectDelete', 'EventSetTimer', 'SendNotification')
$badEngine = @($forbidden | Where-Object { $engineCode.IndexOf($_) -ge 0 })
$biasWrite = [regex]::IsMatch($engineCode, 'g_(htfBias|internalDir)\s*=[^=]')
if ($biasWrite) { $badEngine += 'bias-write' }
Check 'S4a_engine_writes_nothing' ($badEngine.Count -eq 0) ("offenders in the engine half = [" + ($badEngine -join ',') + "]")

# No registry array can even be TOUCHED, except the liquidity registry, which is
# read-only for the liquidity magnet. A write there is caught by the assignment
# pattern below.
$foreign = @('g_fvgs[', 'g_obs[', 'g_events[', 'g_sd[', 'g_trendlines[', 'g_displacements[', 'g_setup[')
$badForeign = @($foreign | Where-Object { $engineCode.IndexOf($_) -ge 0 })
Check 'S4b_engine_touches_no_other_registry' ($badForeign.Count -eq 0) ("offenders = [" + ($badForeign -join ',') + "]")
$mutates = [regex]::IsMatch($engineCode, 'g_liquidity\[[^\]]+\]\.\w+\s*=[^=]')
Check 'S4c_engine_mutates_no_registry' (-not $mutates) 'the liquidity registry is only read'

# ------------------------------------------------------------------ S5 no live price
$live = @('Bid', 'Ask', 'iClose', 'iHigh', 'iLow', 'iTime', 'iOpen', 'SymbolInfoDouble',
   'SymbolInfoTick', 'CopyClose', 'CopyHigh', 'CopyLow', 'MqlTick')
$badLive = @($live | Where-Object { [regex]::IsMatch($modCode, ('\b' + [regex]::Escape($_) + '\b')) })
Check 'S5a_no_live_price_read' ($badLive.Count -eq 0) ("offenders = [" + ($badLive -join ',') + "]")

$onlyClosed = ($modCode -match 'snapBarClose' -and $modCode -match 'snapGuardOk')
Check 'S5b_inputs_are_closed_bar_state' $onlyClosed 'distance and trigger come from the last closed HTF bar'

# ------------------------------------------------------------------ S6 per timeframe
$rrName = ($code -match 'DiagOpen\("ICT_Assistant_Canonical_ReverseRisk_"\+_Symbol\+"_"\+ChartTfCode\(\)\+"\.csv"\)')
Check 'S6a_reverse_risk_file_per_tf' $rrName 'reverse-risk ledger name carries the chart timeframe'

$revName = ($code -match 'DiagOpen\("ICT_Assistant_Canonical_Reversal_Diag_"\+ChartTfCode\(\)\+"\.csv"\)')
Check 'S6b_reversal_file_per_tf' $revName 'reversal ledger name carries the chart timeframe'

$tfCol = (([regex]::Matches($code, '"ChartTF"')).Count -ge 2)
Check 'S6c_charttf_column_in_both' $tfCol 'both ledgers record the chart timeframe as a column too'

$tfWritten = (([regex]::Matches($code, 'ChartTfCode\(\)\)')).Count -ge 2)
Check 'S6d_charttf_value_written' $tfWritten 'the column is actually filled on every row'

$helper = (Get-Body $code 'string ChartTfCode()')
$helperOk = ($helper -match 'PERIOD_M15' -and $helper -match 'PeriodSeconds')
Check 'S6e_tf_helper' $helperOk 'one helper maps the chart period to a short code'

# ------------------------------------------------------------------ S7 layout
# Phase 48: there is only ONE corner row now, so "is the second row below the
# first?" is no longer a question. What must hold instead: the row's position
# comes from the strip input, and no second-row layout input survived (a stale
# input would let a later edit re-draw the old row without anyone noticing).
$mStripY = [regex]::Match($code, 'InpRiskStripY\s*=\s*([0-9]+)')
$leftover = @('InpPendingLineY', 'InpPendingLineWidth', 'InpShowPendingLine')
$stillDeclared = @($leftover | Where-Object { $code -match ('(?m)^input\s+\w+\s+' + $_ + '\s*=') })
Check 'S7_single_corner_row' ($mStripY.Success -and ($stillDeclared.Count -eq 0)) `
   ("row Y comes from InpRiskStripY; leftover second-row inputs = [{0}]" -f ($stillDeclared -join ','))

# ------------------------------------------------------------------ R1 runtime
$tfLedgers = @(Get-ChildItem -LiteralPath $filesDir -Filter 'ICT_Assistant_Canonical_Reversal_Diag_*.csv' -ErrorAction SilentlyContinue)
if ($tfLedgers.Count -eq 0) {
   Pend 'R1_runtime_tf_ledger' 'no per-timeframe reversal ledger yet - reload the chart once after this build'
} else {
   $bad = @()
   foreach ($f in $tfLedgers) {
      $suffix = [regex]::Match($f.BaseName, '_([A-Z0-9]+)$').Groups[1].Value
      $first = (Get-Content -LiteralPath $f.FullName -Encoding Unicode -TotalCount 1)
      $fields = ($first -split ';')
      if (($fields -notcontains 'ChartTF')) { $bad += ($f.Name + ': no ChartTF column'); continue }
      $dataRows = @(Get-Content -LiteralPath $f.FullName -Encoding Unicode | Where-Object { $_ -match '^\d{4}\.\d{2}\.\d{2}' })
      if ($dataRows.Count -eq 0) { continue }
      $last = @($dataRows | Select-Object -Last 1)
      if ($last.Count -eq 0) { continue }
      $vals = ($last[0].TrimEnd("`r") -split ';')
      $tfVal = $vals[$vals.Count - 1]
      if ($tfVal -ne $suffix) { $bad += ($f.Name + ': row says ' + $tfVal) }
   }
   Check 'R1_runtime_tf_ledger' ($bad.Count -eq 0) ("ledgers = {0}; problems = [{1}]" -f $tfLedgers.Count, ($bad -join ' ; '))
}

Write-Host ""
Write-Host ("PASS={0}  FAIL={1}  PENDING={2}" -f $pass, $fail, $pend)
if ($fail -gt 0) { Write-Host 'RESULT: FAILED'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0
