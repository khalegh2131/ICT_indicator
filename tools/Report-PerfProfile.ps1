# =====================================================================
# Report-PerfProfile.ps1 -- read the rebuild performance lines back out of
#                           the MetaTrader journal (Phase 24 evidence)
#
# The indicator prints, once per history rebuild:
#   ICT PHASE13 | rebuild <bars> bars in <ms> ms | events ... | EQ skips ...
#   ICT PHASE24 | profile (top 16, us) | name=<us> ...
# This script decodes the terminal journal (UTF-16LE) and shows the newest
# lines, so a speed claim can be checked instead of believed.
#
# Usage:
#   powershell -File tools/Report-PerfProfile.ps1            # newest 4 rebuilds
#   powershell -File tools/Report-PerfProfile.ps1 -Count 10
# =====================================================================
param(
   [int]$Count = 4,
   [string]$LogDir = "C:\Users\Khaleq\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Logs"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $LogDir)) {
   Write-Output ("Journal folder not found: {0}" -f $LogDir)
   Write-Output 'Pass -LogDir <path to <terminal-id>\MQL5\Logs>'
   exit 1
}

$files = Get-ChildItem -Path $LogDir -Filter *.log | Sort-Object LastWriteTime -Descending
if ($files.Count -eq 0) { Write-Output 'No journal files found.'; exit 0 }

$lines = @()
foreach ($f in $files) {
   # MQL5 journals are UTF-16LE and the running terminal keeps them open,
   # so they must be read with a shared handle (ReadAllText fails with lock)
   $fs = $null; $sr = $null
   try {
      $fs = [System.IO.File]::Open($f.FullName, [System.IO.FileMode]::Open,
                                   [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
      $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Unicode)
      $text = $sr.ReadToEnd()
   } finally {
      if ($sr) { $sr.Close() }
      if ($fs) { $fs.Close() }
   }
   foreach ($ln in ($text -split "`r?`n")) {
      if ($ln -match 'ICT PHASE13 \| rebuild' -or $ln -match 'ICT PHASE24 \| profile') {
         $lines += [pscustomobject]@{ File = $f.Name; Line = $ln.Trim() }
      }
   }
   if ($lines.Count -ge ($Count * 3)) { break }
}

if ($lines.Count -eq 0) {
   Write-Output 'No rebuild performance lines yet.'
   Write-Output 'Reload the indicator on the chart (Remove -> Refresh -> Add) and run this again.'
   exit 0
}

$rebuilds = @($lines | Where-Object { $_.Line -match 'ICT PHASE13' })
$start = [Math]::Max(0, $rebuilds.Count - $Count)
Write-Output ("Rebuild log lines: {0} total, showing the newest {1}" -f $rebuilds.Count, ($rebuilds.Count - $start))
Write-Output ''

for ($i = $start; $i -lt $rebuilds.Count; $i++) {
   $rb = $rebuilds[$i]
   Write-Output ("[{0}] {1}" -f $rb.File, $rb.Line)
   # the profile line for this rebuild is the first PHASE24 entry that follows it
   $idx = $lines.IndexOf($rb)
   for ($j = $idx + 1; $j -lt [Math]::Min($idx + 4, $lines.Count); $j++) {
      if ($lines[$j].Line -match 'ICT PHASE24') { Write-Output ("        {0}" -f $lines[$j].Line) }
   }
   if ($rb.Line -match 'in (\d+) ms') {
      $ms = [int]$Matches[1]
      Write-Output ("        -> {0} ms per rebuild  ({1:N1} ms per processed bar if 600 bars)" -f $ms, ($ms / 600.0))
   }
   Write-Output ''
}
