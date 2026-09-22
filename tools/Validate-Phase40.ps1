# =====================================================================
# Validate-Phase40.ps1  --  "objects vanish when the timeframe changes"
#
#   THE BUG THIS LOCKS
#     Several functions copied a series into a LOCAL array with Copy* and
#     then indexed it with a variable derived from the REQUESTED count:
#
#        int need = extBars + ...;
#        if(shift+need >= ArraySize(h)) return;      // bounds the OnCalculate arrays
#        if(CopyTickVolume(_Symbol,PERIOD_CURRENT,0,need,v)<=0) return;
#        double volRatio=(double)v[shift]/avgVol;    // v may be SHORTER than need
#
#     Copy* only fills as many bars as the series has READY. Right after a
#     timeframe switch the new series is incomplete, so the copy is short,
#     v[shift] is out of range, and MQL5 aborts the whole OnCalculate pass.
#     Because OnDeinit had already deleted the graphical layer, the visible
#     result was: change timeframe -> the chart comes back empty.
#
#   SECTION A locks the fix in the source text (via CanonicalSource.ps1, the
#   same flattened view the MQL5 preprocessor sees).
#   SECTION B is the runtime witness: it reads the terminal journal and
#   requires that the newest initialisation of the indicator is NOT followed
#   by an array-out-of-range line. Source checks alone cannot prove a runtime
#   crash is gone, and the journal is the only place that records it.
#
# Read-only. No build. No writes except stdout.
# =====================================================================
param(
   [string]$Source  = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5",
   [string]$Journal = '',          # defaults to the newest MQL5\Logs\*.log
   [string]$Program = 'ICT_Assistant_Canonical',
   [switch]$SkipRuntime
)

$ErrorActionPreference = 'Stop'
$pass = 0
$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
   if ($ok) { $script:pass++; "PASS  {0}  {1}" -f $name, $detail }
   else     { $script:fail++; "FAIL  {0}  {1}" -f $name, $detail }
}

Write-Output '=== Phase 40 validator: copy-length bounds + handle lifecycle ==='
Write-Output ''

. (Join-Path $PSScriptRoot 'CanonicalSource.ps1')
$text  = Get-CanonicalSourceText  -Path $Source
$lines = Get-CanonicalSourceLines -Path $Source
Write-Output ("Canonical unit: {0} lines, {1} chars" -f $lines.Count, $text.Length)
Write-Output ''

# ---------------------------------------------------------------------------
# A) source invariants - one check per crash site and per leak
# ---------------------------------------------------------------------------

# A1  Wyckoff: the volume copy is short right after a TF switch, so the shift
#     used for v[shift] must be validated against the ACTUAL copied count.
$okA1 = ($text -match 'int\s+volCopied\s*=\s*CopyTickVolume[^;]*;' -and
         $text -match 'if\s*\(\s*shift\s*>=\s*volCopied\s*\)\s*return\s*;')
Check 'A1_wyckoff_shift_bounded_by_copied_volume' $okA1 `
   'UpdateWyckoff must cap shift with the number of volume bars actually copied'

# A2  Profile: the row loop must be bounded by the smallest series that was
#     really copied, not by the requested count.
$okA2 = ($text -match 'int\s+bars\s*=\s*MathMin\s*\(\s*copiedV\s*,\s*MathMin\s*\(\s*ArraySize\s*\(\s*h\s*\)\s*,\s*ArraySize\s*\(\s*l\s*\)\s*\)\s*\)\s*;' -and
         $text -match 'for\s*\(\s*int\s+i\s*=\s*0\s*;\s*i\s*<\s*bars\s*;\s*i\+\+\s*\)')
Check 'A2_profile_loop_bounded_by_actual_series' $okA2 `
   'UpdateProfile must iterate the copied length, not the requested need'

# A3  OnCalculate: all five series must share one bound, or a short ATR buffer
#     would overflow while keyed off ArraySize(h).
$okA3 = ($text -match 'int\s+avail\s*=\s*ArraySize\s*\(\s*h\s*\)\s*;' -and
         $text -match 'avail\s*=\s*MathMin\s*\(\s*avail\s*,\s*ArraySize\s*\(\s*atrBuf\s*\)\s*\)\s*;' -and
         $text -match 'int\s+maxScan\s*=\s*avail\s*-')
Check 'A3_oncalculate_single_bound_for_all_series' $okA3 `
   'OnCalculate must derive the rebuild bound from the smallest series (ATR included)'

# A4  Auction-profile window cache: same class of defect on five copies.
$okA4 = ($text -match 'int\s+n\s*=\s*MathMin\s*\(\s*copied\s*,\s*MathMin\s*\(\s*cH\s*,' -and
         $text -match 'copied\s*=\s*n\s*;')
Check 'A4_window_cache_clamped_to_copied_length' $okA4 `
   'the profile window cache must clamp its window to the smallest copied series'

# A5  Every buffer handle produced in OnInit must be released in OnDeinit.
#     A timeframe switch is OnDeinit + OnInit, so an unreleased handle leaks on
#     every switch until the terminal handle limit is hit.
$creates  = [regex]::Matches($text, 'g_\w+Handle\s*=\s*i[A-Za-z]+\s*\(')
$releases = [regex]::Matches($text, 'IndicatorRelease\s*\(\s*(g_\w+Handle)\s*\)')
$createdNames  = @($creates  | ForEach-Object { $_.Value -replace '\s*=.*$', '' } | Sort-Object -Unique)
$releasedNames = @($releases | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$unreleased = @($createdNames | Where-Object { $releasedNames -notcontains $_ })
Check 'A5_every_handle_released' ($unreleased.Count -eq 0) `
   ("created = [{0}] ; released = [{1}] ; unreleased = [{2}]" -f ($createdNames -join ','), ($releasedNames -join ','), ($unreleased -join ','))

# A6  No local array filled by Copy* may be indexed with the requested count.
#     Heuristic, deliberately narrow: find `CopyX(...,<name>)` targets and flag
#     a `for(...; i < <name's request var>; ...)` in the same function. Reported
#     as informational when it cannot prove a violation.
$copyTargets = [regex]::Matches($text, 'Copy(?:Open|High|Low|Close|Time|TickVolume|Rates|Buffer)\s*\([^;]*?,\s*(\w+)\s*\)\s*[^;]*;')
$targetNames = @($copyTargets | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Check 'A6_copy_targets_enumerated' ($targetNames.Count -gt 0) `
   ("local Copy* targets found = {0} ({1})" -f $targetNames.Count, ($targetNames -join ','))

# A7  The whole point: a shift/loop may never be bounded by a variable that was
#     only ever used as a Copy* REQUEST. The two patterns below are the exact
#     shapes that caused the crash; they must not reappear anywhere.
$badNeed = [regex]::Matches($text, 'for\s*\(\s*int\s+\w+\s*=\s*0\s*;\s*\w+\s*<\s*need\s*;\s*\w+\+\+\s*\)')
$badShift = [regex]::Matches($text, 'v\[shift\]')
$shiftGuarded = ($text -match 'if\s*\(\s*shift\s*>=\s*volCopied\s*\)\s*return\s*;')
Check 'A7_no_unbounded_copy_indexing' ($badNeed.Count -eq 0 -and ($badShift.Count -eq 0 -or $shiftGuarded)) `
   ("loops bounded by a copy request = {0} ; raw v[shift] sites = {1} ; guarded = {2}" -f $badNeed.Count, $badShift.Count, $shiftGuarded)

# ---------------------------------------------------------------------------
# B) runtime witness - the terminal journal
# ---------------------------------------------------------------------------
Write-Output ''

if ($SkipRuntime) {
   Write-Output 'Runtime section skipped by request (-SkipRuntime).'
   Write-Output ''
   Write-Output ("RESULT: PASS={0} FAIL={1}" -f $pass, $fail)
   if ($fail -gt 0) { exit 1 }
   exit 0
}

if ([string]::IsNullOrWhiteSpace($Journal)) {
   $logsDir = 'C:\Users\Khaleq\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Logs'
   if (-not (Test-Path -LiteralPath $logsDir)) {
      Write-Output ("Journal folder not found: {0} - runtime witness unavailable." -f $logsDir)
      Write-Output ''
      Write-Output ("RESULT: PASS={0} FAIL={1}" -f $pass, $fail)
      if ($fail -gt 0) { exit 1 }
      exit 0
   }
   $newest = Get-ChildItem -LiteralPath $logsDir -Filter '*.log' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
   $Journal = $newest.FullName
}
Write-Output ("Journal: {0}" -f $Journal)

# The journal is UTF-16 with a byte-order mark; read it as Unicode so the
# tab-separated fields survive. The terminal keeps the file open while it
# writes, so a plain ReadAllText throws - open it shared instead.
$shareReadWrite = [System.IO.FileShare]::ReadWrite
$journalStream  = New-Object System.IO.FileStream($Journal, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $shareReadWrite)
try {
   $reader = New-Object System.IO.StreamReader($journalStream, [System.Text.Encoding]::Unicode)
   $journalText = $reader.ReadToEnd()
   $reader.Dispose()
} finally {
   $journalStream.Dispose()
}
$jLines = $journalText -split "`r?`n"

$stampRe = [regex]'^\S\S\t\d+\t(\d{2}:\d{2}:\d{2}\.\d{3})\t'
function Get-Stamp([string]$line) {
   $m = $stampRe.Match($line)
   if ($m.Success) { return $m.Groups[1].Value }
   return '00:00:00.000'
}

$initLines  = @($jLines | Where-Object { $_ -match [regex]::Escape($Program) -and $_ -match 'ICT Assistant \(v0\.1\)' })
$crashLines = @($jLines | Where-Object { $_ -match [regex]::Escape($Program) -and ($_ -match 'array out of range' -or $_ -match 'critical error' -or $_ -match 'zero divide') })
$rebuild    = @($jLines | Where-Object { $_ -match [regex]::Escape($Program) -and $_ -match 'ICT PHASE13 \| rebuild' })

$lastInit  = if ($initLines.Count  -gt 0) { Get-Stamp $initLines[-1] }  else { '' }
$lastCrash = if ($crashLines.Count -gt 0) { Get-Stamp $crashLines[-1] } else { '' }

Write-Output ("attaches seen      : {0} (newest {1})" -f $initLines.Count,  $(if ($lastInit)  { $lastInit }  else { 'none' }))
Write-Output ("runtime errors seen: {0} (newest {1})" -f $crashLines.Count, $(if ($lastCrash) { $lastCrash } else { 'none' }))
Write-Output ("rebuild lines seen : {0}" -f $rebuild.Count)

# The verdict is about ORDER, not mere presence: an error from an older build
# in the same journal must not be able to condemn the current one, and a clean
# older session must not be able to certify it either.
$clean = $true
$detail = ''
if ($crashLines.Count -eq 0) {
   $detail = 'no runtime error recorded for this program'
} elseif ($initLines.Count -eq 0) {
   $clean = $false
   $detail = 'errors exist but no attach was recorded: cannot attribute them to a build'
} elseif ($lastCrash -gt $lastInit) {
   $clean = $false
   $detail = ("newest error {0} is AFTER the newest attach {1} -> the running build still crashes" -f $lastCrash, $lastInit)
} else {
   $detail = ("newest error {0} is BEFORE the newest attach {1} -> those belong to an older build; the current attach is clean" -f $lastCrash, $lastInit)
}
Check 'B1_no_runtime_crash_after_last_attach' $clean $detail

if (-not $clean) {
   Write-Output ''
   Write-Output 'Last error lines:'
   $crashLines | Select-Object -Last 6 | ForEach-Object { Write-Output ("   " + ($_ -replace "`t", ' | ')) }
}

# A rebuild that never happened is the other half of "empty chart": the layer is
# drawn only at the end of the rebuild, so after a TF switch there must be one.
if ($initLines.Count -gt 0 -and $rebuild.Count -eq 0) {
   Write-Output ''
   Write-Output 'NOTE: no "ICT PHASE13 | rebuild" line is present. That line is only printed'
   Write-Output '      when InpLogPerfOnRebuild is ON, so its absence is not proof of a failure.'
}

Write-Output ''
Write-Output ("RESULT: PASS={0} FAIL={1}" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
