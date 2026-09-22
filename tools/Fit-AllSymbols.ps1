<#
  Fit-AllSymbols.ps1  --  fit the signal grade for EVERY symbol/timeframe that has data

  WHY
    The grade table was fitted once, on one symbol. Phase 49 made the indicator read a
    per-symbol calibration file when one exists and say so honestly when none does.
    This driver is what fills those files in - one per symbol AND timeframe, because
    each live chart writes its own ledger and pooling two timeframes measures neither.

    The ledgers live in the terminal COMMON folder, not in this repo: they are the
    user's own accumulated evidence. So this script only reads them and writes the
    calibration next to them.

  WHAT IT DOES NOT DO
    It does not invent numbers and it does not lower the bar: a ledger with fewer than
    -MinRows usable rows is skipped by name, not silently fitted from a handful of
    bars. A feature whose bucket is below the fitter's own sample floor keeps a zero
    lift, which is the same rule the frozen reference table follows.

  USAGE
    # dry run - show what would be fitted, write nothing
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/Fit-AllSymbols.ps1

    # write the calibration files into the terminal COMMON folder
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/Fit-AllSymbols.ps1 -Apply

    # one timeframe only, and a higher evidence bar
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/Fit-AllSymbols.ps1 -OnlyTF M15 -MinRows 1000 -Apply

  NOTE: ASCII-only by design (PowerShell 5.1 misreads non-BOM UTF-8 sources).
#>

param(
   [string]$FilesDir = (Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'),
   [int]$MinRows = 300,
   [string]$OnlyTF = '',
   [switch]$Apply
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$prefix = 'ICT_Assistant_Canonical_ReverseRisk_'
$fit = Join-Path $PSScriptRoot 'Fit-SignalGrade.ps1'

# Longest first, so M15 is not read as M1 and H4 is not read as H1.
$tfList = @('MN1','W1','D1','H12','H8','H6','H4','H3','H2','H1',
            'M30','M20','M15','M12','M10','M6','M5','M4','M3','M2','M1')

$files = @(Get-ChildItem -LiteralPath $FilesDir -Filter ($prefix + '*.csv') -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) { Write-Host ("no ledgers in " + $FilesDir); exit 0 }

Write-Host ("=== fit candidates (" + $files.Count + " ledgers) ===")
$todo = New-Object System.Collections.ArrayList
foreach ($f in ($files | Sort-Object Name)) {
   $rest = $f.Name.Substring($prefix.Length)
   $rest = $rest.Substring(0, $rest.Length - 4)              # drop ".csv"
   $tf = ''
   foreach ($t in $tfList) {
      if ($rest.EndsWith('_' + $t)) { $tf = $t; $rest = $rest.Substring(0, $rest.Length - $t.Length - 1); break }
   }
   if (-not [string]::IsNullOrWhiteSpace($OnlyTF) -and $tf -ne $OnlyTF) { continue }

   $symbol = $rest
   $base = ([regex]::Match($symbol, '^[A-Za-z0-9]+')).Value
   if ([string]::IsNullOrEmpty($base)) { $base = $symbol }

   # Usable rows = data rows. The first field of a data row is a date; a header is not.
   $rows = 0
   foreach ($ln in [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::Unicode)) {
      if ($ln -match '^\d{4}\.\d{2}\.\d{2}') { $rows++ }
   }
   $outName = if ([string]::IsNullOrEmpty($tf)) { 'ICT_Assistant_Canonical_GradeCalib_' + $base + '.csv' }
              else                                { 'ICT_Assistant_Canonical_GradeCalib_' + $base + '_' + $tf + '.csv' }
   $outPath = Join-Path $FilesDir $outName
   $verdict = if ($rows -ge $MinRows) { 'FIT' } else { 'SKIP (below -MinRows)' }
   Write-Host ("  {0,-46} rows={1,7}  tf={2,-4} -> {3,-24} {4}" -f $f.Name, $rows, $(if ($tf) { $tf } else { 'ALL' }), $outName, $verdict)
   if ($rows -ge $MinRows) {
      [void]$todo.Add([pscustomobject]@{ Symbol = $symbol; TF = $tf; Path = $f.FullName; Out = $outPath; Rows = $rows })
   }
}

if ($todo.Count -eq 0) { Write-Host 'nothing to fit'; exit 0 }

Write-Host ''
if (-not $Apply) {
   Write-Host ("DRY RUN: {0} calibration file(s) would be written. Re-run with -Apply." -f $todo.Count)
   foreach ($t in $todo) {
      Write-Host ("  powershell -NoProfile -ExecutionPolicy Bypass -File tools/Fit-SignalGrade.ps1 -Symbol `"{0}`" -LedgerPath `"{1}`" -EmitCalib `"{2}`"" -f $t.Symbol, $t.Path, $t.Out)
   }
   exit 0
}

$ok = 0; $bad = 0; $thin = 0
foreach ($t in $todo) {
   Write-Host ("--- fitting " + $t.Symbol + " / " + $(if ($t.TF) { $t.TF } else { 'ALL' }) + " (" + $t.Rows + " ledger rows) ---")
   $out = (& $fit -Symbol $t.Symbol -LedgerPath $t.Path -EmitCalib $t.Out 2>&1 | Out-String)
   $rc = $LASTEXITCODE
   # The sample count is read from the written file, not parsed out of the fitter's
   # console text: the file is the artifact the chart will actually read.
   $samples = 0; $baseWin = ''
   if (Test-Path -LiteralPath $t.Out) {
      $calTxt = [System.IO.File]::ReadAllText($t.Out)
      if ($calTxt -match '(?m)^rows;(\d+)')    { $samples = [int]$Matches[1] }
      if ($calTxt -match '(?m)^basewin;([0-9.]+)') { $baseWin = $Matches[1] }
   }
   foreach ($line in ($out -split "`n")) {
      if ($line -match 'samples=|^A\+|^A\s|^B\+|^B\s|^C\s|REFUSING') { Write-Host ('    ' + ($line -replace "`r", '').TrimEnd()) }
   }
   # The file on disk is the authority. The exit code is only a second opinion: a
   # script that ends without an explicit exit leaves the previous value behind.
   if (-not (Test-Path -LiteralPath $t.Out)) {
      $thin++
      Write-Host ("    SKIPPED: usable samples = {0}, fitter refused (exit {1}) - nothing written" -f $samples, $rc) -ForegroundColor Yellow
      continue
   }
   Write-Host ("    fitted on {0} usable samples (baseline win {1}%)" -f $samples, $baseWin)
   if (Test-Path -LiteralPath $t.Out) {
      $ok++
      # Every written file must be re-readable by the loader's rules: ASCII, LF, and
      # keys from the loader's own list. A file that fails this is a file the chart
      # will silently ignore, so it is reported rather than counted as success.
      $txt = [System.IO.File]::ReadAllText($t.Out)
      $nonAscii = ([regex]::Matches($txt, '[^\x00-\x7F]')).Count
      $crlf     = ([regex]::Matches($txt, "`r")).Count
      $keys     = ([regex]::Matches($txt, '(?m)^(lift\.f[1-7]\.|thr\.|win\.|n\.|basewin|basen)')).Count
      Write-Host ("    wrote {0} bytes ; keys={1} ; non-ascii={2} ; CR={3}" -f $txt.Length, $keys, $nonAscii, $crlf)
      if ($keys -lt 10 -or $nonAscii -gt 0 -or $crlf -gt 0) { $bad++; Write-Host '    WARNING: this file does not match the loader format' -ForegroundColor Yellow }
   } else {
      $bad++
      Write-Host '    FAILED to write' -ForegroundColor Red
   }
}

Write-Host ''
Write-Host ("summary: written={0}  insufficient-evidence={1}  suspect={2}" -f $ok, $thin, $bad)
Write-Host 'The indicator picks a calibration file up on the next chart reload.'
if ($bad -gt 0) { exit 1 }
exit 0
