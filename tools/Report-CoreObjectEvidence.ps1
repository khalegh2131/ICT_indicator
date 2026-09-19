<#
  Report-CoreObjectEvidence.ps1
  ------------------------------------------------------------------
  READ-ONLY evidence report for phase 8 acceptance criteria, built from the
  CSV files that MT5 itself writes. It changes nothing on disk or on charts.

  Inputs (MetaQuotes common Files folder):
     ICT_Assistant_Canonical_Explain.csv      (UTF-16, ';' delimited)
     ICT_Assistant_Canonical_ReplayLedger.csv (UTF-16, ';' delimited, no header)

  NOTE: this script intentionally contains no non-ASCII literals, because
  Windows PowerShell 5.1 misreads non-BOM UTF-8 source files. State tokens are
  matched against a whitelist of the ASCII words the indicator itself emits;
  Persian words used as values are built from code points.

  Usage:
     powershell -NoProfile -ExecutionPolicy Bypass -File tools/Report-CoreObjectEvidence.ps1
     powershell ... -File tools/Report-CoreObjectEvidence.ps1 -FilesDir "D:\...\Common\Files"
#>
param(
   [string]$FilesDir = (Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files')
)

$ErrorActionPreference = 'Stop'
$explainPath = Join-Path $FilesDir 'ICT_Assistant_Canonical_Explain.csv'
$ledgerPath  = Join-Path $FilesDir 'ICT_Assistant_Canonical_ReplayLedger.csv'

# ASCII state words the indicator prints after ": ". Anything else (PERIOD_H4,
# BOS, an id, a number) is rejected so that explanatory sentences never win.
$stateWords = @('FRESH','SWEPT','INVALID','MITIGATED','BROKEN','BREAKER','VALID','TOUCHED','IFVG')

# Persian "yes"/"no" used in "Causal=" built from code points (ASCII-safe source)
$persianYes = ([char]0x0628).ToString() + ([char]0x0644) + ([char]0x0647)
$persianNo  = ([char]0x062E).ToString() + ([char]0x06CC) + ([char]0x0631)

function Get-Stamp([string]$Path) {
   if (-not (Test-Path $Path)) { return 'missing' }
   return (Get-Item $Path).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-Lines([string]$Path) {
   if (-not (Test-Path $Path)) { return @() }
   return @(Get-Content -Path $Path -Encoding Unicode)
}

# ExpAddWrapped splits long lines and the CSV joins them with ' ~ ', so a ': FRESH'
# or 'Displacement #id' pair can arrive as ': ~ FRESH' / 'Displacement ~ #id'.
# Without the optional '~' the metric silently reads 0 (a false negative).
function Get-State([string]$Summary) {
   foreach ($m in [regex]::Matches($Summary, ':\s*(?:~\s*)?([A-Za-z][A-Za-z_]+)')) {
      $tok = $m.Groups[1].Value.ToUpper()
      if ($stateWords -contains $tok) { return $tok }
   }
   return 'UNPARSED'
}

Write-Output '=== Phase 8 core-object evidence (read-only) ==='
Write-Output ("Files dir   : " + $FilesDir)
Write-Output ("Explain.csv : " + (Get-Stamp $explainPath))
Write-Output ("Ledger.csv  : " + (Get-Stamp $ledgerPath))
Write-Output ''

# ---------------------------------------------------------------- Explain.csv
$explainLines = Get-Lines $explainPath
if ($explainLines.Count -eq 0) {
   Write-Output 'Explain.csv not found - reload the indicator on the chart first.'
   exit 1
}

$kindTotal = @{}
$stateByKind = @{}
$fvgLinked = 0
$fvgMinus1 = 0
$fvgCausalYes = 0
$fvgCausalNo = 0
$fvgCausalUnreadable = 0
$obRows = 0
$obBreakerRows = 0

foreach ($line in $explainLines) {
   $parts = $line -split ';'
   if ($parts.Count -lt 2) { continue }
   $obj = $parts[0]
   if ($obj -notmatch '^ICTv13_([A-Z]+)_') { continue }
   $kind = $Matches[1]
   $sum = if ($parts.Count -gt 4) { ($parts[4..($parts.Count - 1)] -join ';') } else { '' }
   if ([string]::IsNullOrWhiteSpace($sum)) { continue }

   if (-not $kindTotal.ContainsKey($kind)) { $kindTotal[$kind] = 0; $stateByKind[$kind] = @{} }
   $kindTotal[$kind]++
   $state = Get-State $sum
   if (-not $stateByKind[$kind].ContainsKey($state)) { $stateByKind[$kind][$state] = 0 }
   $stateByKind[$kind][$state]++

   if ($kind -eq 'FVG') {
      $dm = [regex]::Match($sum, 'Displacement\s*(?:~\s*)?#(-?\d+)')
      if ($dm.Success) {
         if ($dm.Groups[1].Value -eq '-1') { $fvgMinus1++ } else { $fvgLinked++ }
      }
      $cm = [regex]::Match($sum, 'Causal=(\S+)')
      if ($cm.Success) {
         $v = $cm.Groups[1].Value
         if ($v.StartsWith($persianYes)) { $fvgCausalYes++ }
         elseif ($v.StartsWith($persianNo)) { $fvgCausalNo++ }
         else { $fvgCausalUnreadable++ }
      }
   }

   if ($kind -eq 'OB') {
      $obRows++
      if ($state -eq 'BREAKER') { $obBreakerRows++ }
   }
}

Write-Output '--- 1) object states from Explain.csv ---'
foreach ($kind in ($kindTotal.Keys | Sort-Object)) {
   $pairs = $stateByKind[$kind].GetEnumerator() | Sort-Object -Property Value -Descending |
      ForEach-Object { "$($_.Key)=$($_.Value)" }
   Write-Output ("{0,-9} rows={1,-4} {2}" -f $kind, $kindTotal[$kind], ($pairs -join ' '))
}

Write-Output ''
Write-Output '--- 2) FVG linkage (#26 / #27) ---'
Write-Output ("FVG rows with a linked displacement : " + $fvgLinked)
Write-Output ("FVG rows with displacement #-1      : " + $fvgMinus1)
Write-Output ("FVG rows Causal=yes                 : " + $fvgCausalYes)
Write-Output ("FVG rows Causal=no                  : " + $fvgCausalNo)
if ($fvgCausalUnreadable -gt 0) {
   Write-Output ("FVG rows Causal unparsed            : " + $fvgCausalUnreadable)
}

Write-Output ''
Write-Output '--- 3) OB / Breaker ratio (#39) ---'
if ($obRows -gt 0) {
   $pct = [math]::Round(100.0 * $obBreakerRows / $obRows, 1)
   Write-Output ("OB rows=$obRows  BREAKER rows=$obBreakerRows  -> $pct% breaker")
} else {
   Write-Output 'No OB rows in Explain.csv'
}

# ------------------------------------------------------------- ReplayLedger
$ledgerLines = Get-Lines $ledgerPath
Write-Output ''
Write-Output '--- 4) structure events from ReplayLedger (#4) ---'
if ($ledgerLines.Count -eq 0) {
   Write-Output 'ReplayLedger.csv not found (needs InpWriteReplayDiagnostics=true plus a chart reload).'
} else {
   $typeCount = @{}
   $rows = 0
   foreach ($line in $ledgerLines) {
      $p = $line -split ';'
      if ($p.Count -lt 3) { continue }
      if ($p[0] -notmatch '^\d+$') { continue }
      $t = $p[2].Trim()
      if ($t -eq '') { continue }
      if (-not $typeCount.ContainsKey($t)) { $typeCount[$t] = 0 }
      $typeCount[$t]++
      $rows++
   }
   Write-Output ("ledger events = " + $rows)
   $typeCount.GetEnumerator() | Sort-Object -Property Value -Descending |
      ForEach-Object { Write-Output ("{0,-8} {1}" -f $_.Key, $_.Value) }
}

# ------------------------------------------------- live structure events (#4)
# The ReplayLedger only exists while InpWriteReplayDiagnostics=true, so #4 used to
# be unmeasurable by default. Every drawn event object carries its type in its own
# title ("EVENT CHoCH #..."), so the same ratio can be read straight from
# Explain.csv for the events currently on the chart.
$structTypes = @{}
$structRows = 0
foreach ($line in $explainLines) {
   $p = $line -split ';'
   if ($p.Count -lt 2) { continue }
   if ($p[0] -notmatch '^ICTv13_EVT_[0-9]+$') { continue }
   $m = [regex]::Match($p[1], '^EVENT\s+([A-Za-z_]+)')
   if (-not $m.Success) { continue }
   $t = $m.Groups[1].Value.ToUpper()
   if (-not $structTypes.ContainsKey($t)) { $structTypes[$t] = 0 }
   $structTypes[$t]++
   $structRows++
}
Write-Output ''
Write-Output '--- 5) structure event types drawn on the chart (#4) ---'
if ($structRows -eq 0) {
   Write-Output 'No event objects on the chart right now (nothing to read for #4).'
} else {
   Write-Output ("event objects = " + $structRows)
   $structTypes.GetEnumerator() | Sort-Object -Property Value -Descending |
      ForEach-Object { Write-Output ("{0,-8} {1}" -f $_.Key, $_.Value) }
   $ch = if ($structTypes.ContainsKey('CHOCH')) { $structTypes['CHOCH'] } else { 0 }
   $bo = if ($structTypes.ContainsKey('BOS'))   { $structTypes['BOS'] }   else { 0 }
   Write-Output ("CHoCH=$ch  BOS=$bo  -> " + $(if ($bo -gt $ch) { 'BOS still dominates (check #4)' } else { 'CHoCH >= BOS, matches the #4 fix' }))
}

Write-Output ''
Write-Output '--- acceptance reminders ---'
Write-Output 'FVG : a FRESH state must appear again (before phase 8 every FVG was MITIGATED at birth).'
Write-Output 'FVG : Causal must not be 100% while most displacements are still energy-only.'
Write-Output 'OB  : BREAKER must be a minority of all OB rows (was ~75% before phase 8).'
Write-Output 'LIQ : INVALID must be reachable, and FRESH/SWEPT levels must stay drawn.'
Write-Output 'EVT : BOS without a prior trend is now labelled CHoCH, so CHoCH should dominate early history.'
