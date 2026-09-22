# =====================================================================
# Split-CanonicalIntoModules.ps1
#
#   One-time (but repeatable) decomposition of the monolithic canonical
#   source into per-family modules, WITHOUT changing a single byte of code.
#
# HOW THE GUARANTEE WORKS
# -----------------------
# The modules are CONTIGUOUS slices of the original file, emitted in the
# original order. MQL5's preprocessor pastes an #include textually, so the
# translation unit stays exactly:
#
#     lines 1..32  (header + #property + #define)   <- kept in the shell
#     module 1 .. module 30                          <- the original lines 33..N
#
# Nothing is moved, renamed or reordered, so global-variable declaration
# order and struct/enum dependency order are untouched. That is what makes
# "no logic change" a provable statement rather than a promise: this script
# reassembles the slices in memory and compares them to the original bytes
# BEFORE it writes anything. If the compare fails, nothing is written.
#
# All I/O is byte-level on purpose: the source is pure LF, and text-mode
# cmdlets would rewrite line endings (Set-Content emits CRLF on Windows) and
# silently corrupt every file.
#
# Verify the result any time with tools/Verify-ModuleSplit.ps1.
# =====================================================================
param(
   [string]$Source     = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5",
   [string]$ModulesDir = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/modules",
   [string]$ShellOut   = "",
   [string]$FooterFile = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/modules/_shell-footer.txt",
   [int]$HeaderLines   = 32,
   [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ShellOut)) { $ShellOut = $Source }
if (-not (Test-Path -LiteralPath $Source)) { throw "Canonical source not found: $Source" }

# ---- module map: ordered (file name, first line of the slice) ----------------
# Every cut line is the opening banner of a section that already existed in the
# monolith, so each module is a real family, not an arbitrary chunk.
$map = @(
   @{ Name = '01_HeaderAndInputs.mqh';     Start =    33 },  # INPUTS (groups + 259 inputs)
   @{ Name = '02_Types.mqh';               Start =   431 },  # ENUMS + DATA STRUCTS
   @{ Name = '03_GlobalState.mqh';         Start =   617 },  # GLOBAL STORAGE (single registries)
   @{ Name = '04_Utilities.mqh';           Start =   934 },  # perf probe + held diagnostics handles + helpers
   @{ Name = '05_TimeBase.mqh';            Start =  1268 },  # broker GMT offset, NY clock, DST rules
   @{ Name = '06_MultiTimeframe.mqh';      Start =  1318 },  # phases 16-21: the six remaining families
   @{ Name = '07_AuctionProfile.mqh';      Start =  2394 },  # phase 34: IB, TPO, day types, naked POC
   @{ Name = '08_Lifecycle.mqh';           Start =  3030 },  # OnInit / OnDeinit
   @{ Name = '09_SwingAndStructure.mqh';   Start =  3353 },  # no-repaint pivots + BOS/CHoCH/MSS engine
   @{ Name = '10_Liquidity.mqh';           Start =  3531 },  # liquidity registry
   @{ Name = '11_Sweep.mqh';               Start =  3758 },  # sweep / stop hunt engine
   @{ Name = '12_Displacement.mqh';        Start =  3812 },  # displacement engine
   @{ Name = '13_FairValueGap.mqh';        Start =  3909 },  # FVG engine: standard, implied, micro, volume imbalance
   @{ Name = '14_OrderBlocks.mqh';         Start =  4053 },  # OB engine + breaker / mitigation block
   @{ Name = '15_ReverseRisk.mqh';         Start =  4437 },  # phase 32 reversal-risk scoring
   @{ Name = '16_HtfStructure.mqh';        Start =  4732 },  # HTF confirmed vs protected structure
   @{ Name = '17_Sessions.mqh';            Start =  4844 },  # sessions / killzones
   @{ Name = '18_LegAndDol.mqh';           Start =  4985 },  # dealing-range leg + draw on liquidity
   @{ Name = '19_SetupEngine.mqh';         Start =  5178 },  # setup construction + phase 15 lifecycle
   @{ Name = '20_SmcMmm.mqh';              Start =  5668 },  # phase 12: SMC / MMM coverage
   @{ Name = '21_ReversalGate.mqh';        Start =  6351 },  # phase 11: reversal gate
   @{ Name = '22_LoadStamp.mqh';           Start =  6653 },  # build stamp + numeric evidence ledger
   @{ Name = '23_Drawing.mqh';             Start =  6762 },  # drawing + chart object layer
   @{ Name = '24_RedrawReconcile.mqh';     Start =  7015 },  # phase 14: reconciling redraw
   @{ Name = '25_Explain.mqh';             Start =  8138 },  # explain mode (indicator + teacher)
   @{ Name = '26_PersianRender.mqh';       Start =  8204 },  # Persian shaping / RTL rendering engine
   @{ Name = '27_Dashboard.mqh';           Start =  9595 },  # dashboard + phase 35 risk strip
   @{ Name = '28_ClosedBarPipeline.mqh';   Start = 10158 },  # shared live + replay analysis path
   @{ Name = '29_BehaviorSelfTest.mqh';    Start = 10424 },  # phase 37: synthetic-data behavior harness
   @{ Name = '30_OnCalculate.mqh';         Start = 10921 }   # OnCalculate
)

# ---- read the source as bytes and index line starts -------------------------
$bytes = [System.IO.File]::ReadAllBytes($Source)
$lineStart = New-Object 'System.Collections.Generic.List[int]'
$lineStart.Add(0)
for ($i = 0; $i -lt $bytes.Length; $i++) {
   if ($bytes[$i] -eq 10) { $lineStart.Add($i + 1) }
}
# lineStart[k] = offset of line k+1. With a trailing LF the last entry equals the
# file length, which represents an empty final line.
$lineCount = $lineStart.Count - 1
if ($lineCount -le 0) { throw "Could not index lines in $Source" }

Write-Output ("Source   : {0}" -f $Source)
Write-Output ("Size     : {0} bytes, {1} lines" -f $bytes.Length, $lineCount)

function Get-Slice([int]$from, [int]$to) {
   # 1-based inclusive line range -> raw bytes (LF terminators preserved)
   if ($from -lt 1) { throw "slice start $from is out of range" }
   if ($to -gt $lineCount) { throw "slice end $to exceeds $lineCount lines" }
   $a = $lineStart[$from - 1]
   $b = $lineStart[$to]            # exclusive end == start of line to+1
   $len = $b - $a
   $out = New-Object byte[] $len
   [Array]::Copy($bytes, $a, $out, 0, $len)
   return ,$out
}

# ---- build every slice and reassemble in memory ------------------------------
$slices = @()
for ($k = 0; $k -lt $map.Count; $k++) {
   $from = $map[$k].Start
   $to   = if ($k + 1 -lt $map.Count) { $map[$k + 1].Start - 1 } else { $lineCount }
   if ($from -gt $to) { throw ("module {0}: start {1} is past end {2}" -f $map[$k].Name, $from, $to) }

   # every slice must begin with the banner that named it (guards a wrong manifest)
   $first = [System.Text.Encoding]::UTF8.GetString($bytes, $lineStart[$from - 1], 40)
   if ($first -notmatch '^//={20,}') {
      throw ("module {0}: line {1} is not a section banner - the module map is stale" -f $map[$k].Name, $from)
   }

   $slices += ,@{ Name = $map[$k].Name; From = $from; To = $to; Bytes = (Get-Slice $from $to) }
}

$header = Get-Slice 1 $HeaderLines
$flatLen = $header.Length
foreach ($s in $slices) { $flatLen += $s.Bytes.Length }
if ($flatLen -ne $bytes.Length) {
   throw ("reassembly length mismatch: {0} bytes vs original {1}" -f $flatLen, $bytes.Length)
}

$flat = New-Object byte[] $flatLen
$pos = 0
[Array]::Copy($header, 0, $flat, 0, $header.Length); $pos += $header.Length
foreach ($s in $slices) { [Array]::Copy($s.Bytes, 0, $flat, $pos, $s.Bytes.Length); $pos += $s.Bytes.Length }

$sha = [System.Security.Cryptography.SHA256]::Create()
$flatHash = ([System.BitConverter]::ToString($sha.ComputeHash($flat))).Replace('-', '')
$origHash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
Write-Output ("Original SHA256 : {0}" -f $origHash)
Write-Output ("Reassembled     : {0}" -f $flatHash)

$identical = $true
for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -ne $flat[$i]) { $identical = $false; break } }
if (-not $identical -or $flatHash -ne $origHash) {
   throw 'ABORTED: the reassembled modules are not byte-identical to the original. Nothing was written.'
}
Write-Output 'Reassembly proof: byte-identical to the original source.'

if ($WhatIf) {
   Write-Output ''
   Write-Output ('--- plan ({0} modules) ---' -f $slices.Count)
   foreach ($s in $slices) {
      Write-Output ("  {0,-26} lines {1,6}-{2,6}  ({3,6} bytes)" -f $s.Name, $s.From, $s.To, $s.Bytes.Length)
   }
   Write-Output ''
   Write-Output 'WhatIf: nothing written.'
   exit 0
}

# ---- write the modules ------------------------------------------------------
if (-not (Test-Path -LiteralPath $ModulesDir)) {
   New-Item -ItemType Directory -Path $ModulesDir -Force | Out-Null
}
foreach ($s in $slices) {
   [System.IO.File]::WriteAllBytes((Join-Path $ModulesDir $s.Name), $s.Bytes)
}

# ---- write the shell --------------------------------------------------------
# Exactly: original lines 1..HeaderLines, then one #include per module in the
# original order, then a blank line and a comment block explaining the layout.
#
# The footer is read from a separate UTF-8 file instead of being written as a
# literal in this script: PowerShell 5.1 decodes a BOM-less .ps1 as ANSI, so
# Persian text embedded here would arrive as mojibake. Read with -Encoding UTF8
# from its own file, it survives intact.
$footer = ''
if (Test-Path -LiteralPath $FooterFile) {
   $footer = (Get-Content -LiteralPath $FooterFile -Raw -Encoding UTF8)
   if ($footer.Length -gt 0 -and $footer[0] -eq [char]0xFEFF) { $footer = $footer.Substring(1) }
   $footer = $footer.Replace("`r`n", "`n")
   if (-not $footer.EndsWith("`n")) { $footer += "`n" }
}

$sb = New-Object System.Text.StringBuilder
$sb.Append([System.Text.Encoding]::UTF8.GetString($header)) | Out-Null
foreach ($s in $slices) {
   $sb.Append(('#include "modules/{0}"' -f $s.Name)) | Out-Null
   $sb.Append("`n") | Out-Null
}
if ($footer.Length -gt 0) {
   $sb.Append("`n") | Out-Null
   $sb.Append($footer) | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ShellOut, $sb.ToString(), $utf8NoBom)

Write-Output ''
Write-Output ("Modules written : {0} files -> {1}" -f $slices.Count, $ModulesDir)
Write-Output ("Shell written   : {0}" -f $ShellOut)
Write-Output ("Shell lines     : {0}" -f (($sb.ToString() -split "`n").Count - 1))
Write-Output 'Now run tools/Verify-ModuleSplit.ps1 to re-prove the split from disk.'
