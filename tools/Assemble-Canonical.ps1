# =====================================================================
# Assemble-Canonical.ps1  --  byte-level assembler for the module tree
#
#   The compiled translation unit is: the shell's header lines (everything
#   before the first #include) followed by the 30 modules in include order.
#   That is exactly how the MQL5 preprocessor builds it, and exactly what
#   Verify-ModuleSplit.ps1 hashes.
#
#   This tool exists so a *deliberate* logic change can be justified by an
#   external diff instead of by editing the frozen hash on faith:
#
#     # 1. assemble the current tree and a frozen copy
#     powershell -File tools/Assemble-Canonical.ps1 -Out .tmp/now.mq5
#     powershell -File tools/Assemble-Canonical.ps1 `
#        -Shell 08_FINAL_PACKAGE/ICT_Assistant_Canonical_v0_1/ICT_Assistant_Canonical_v0_1.mq5 `
#        -ModulesDir 08_FINAL_PACKAGE/ICT_Assistant_Canonical_v0_1/modules -Out .tmp/before.mq5
#
#     # 2. the diff must show ONLY the intended change
#     diff -u .tmp/before.mq5 .tmp/now.mq5
#
#     # 3. only then re-freeze the hash inside Verify-ModuleSplit.ps1,
#     #    and record the diff in the project technical notes
#
#   Bytes are handled directly: PowerShell text cmdlets normalise line
#   endings and would corrupt the LF-only, BOM'd source invisibly.
# =====================================================================
param(
   [string]$Shell      = "D:/ICT_indicator/01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5",
   [string]$ModulesDir = "",
   [string]$Out        = ""
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Shell)) { throw "Shell not found: $Shell" }
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulesDir)) {
   $ModulesDir = Join-Path (Split-Path -Parent $Shell) 'modules'
}
if (-not (Test-Path -LiteralPath $ModulesDir)) { throw "Modules dir not found: $ModulesDir" }

$shellBytes = [System.IO.File]::ReadAllBytes($Shell)
$lineStart = New-Object 'System.Collections.Generic.List[int]'
$lineStart.Add(0)
for ($i = 0; $i -lt $shellBytes.Length; $i++) {
   if ($shellBytes[$i] -eq 10) { $lineStart.Add($i + 1) }
}
$shellLineCount = $lineStart.Count - 1
$latin1 = [System.Text.Encoding]::GetEncoding(28591)

function Get-ShellLine([int]$n) {
   $a = $lineStart[$n - 1]
   $b = if ($n -lt $lineStart.Count) { $lineStart[$n] } else { $shellBytes.Length }
   $len = $b - $a
   while ($len -gt 0 -and ($shellBytes[$a + $len - 1] -eq 10 -or $shellBytes[$a + $len - 1] -eq 13)) { $len-- }
   if ($len -le 0) { return '' }
   return $latin1.GetString($shellBytes, $a, $len)
}
function Get-ShellLineBytes([int]$n) {
   $a = $lineStart[$n - 1]
   $b = if ($n -lt $lineStart.Count) { $lineStart[$n] } else { $shellBytes.Length }
   $len = $b - $a
   $out = New-Object byte[] $len
   [Array]::Copy($shellBytes, $a, $out, 0, $len)
   return ,$out
}

$includeLines = @()
$includeNames = @()
for ($n = 1; $n -le $shellLineCount; $n++) {
   $m = [regex]::Match((Get-ShellLine $n), '^\s*#include\s+"([^"]+)"\s*$')
   if ($m.Success) { $includeLines += $n; $includeNames += $m.Groups[1].Value }
}
if ($includeNames.Count -eq 0) { throw "No #include lines found in $Shell" }

$firstInc = $includeLines[0]
$buf = New-Object 'System.Collections.Generic.List[byte]'
for ($n = 1; $n -lt $firstInc; $n++) { $buf.AddRange((Get-ShellLineBytes $n)) }

$missing = @()
foreach ($rel in $includeNames) {
   $leaf = Split-Path -Leaf $rel
   $p = Join-Path $ModulesDir $leaf
   if (-not (Test-Path -LiteralPath $p)) { $missing += $leaf; continue }
   $buf.AddRange([System.IO.File]::ReadAllBytes($p))
}
if ($missing.Count -gt 0) { throw ("Modules missing in {0}: {1}" -f $ModulesDir, ($missing -join ',')) }

$assembled = $buf.ToArray()
$lines = 0
foreach ($b in $assembled) { if ($b -eq 10) { $lines++ } }
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = ([System.BitConverter]::ToString($sha.ComputeHash($assembled))).Replace('-', '')

Write-Output ("shell        : {0}" -f $Shell)
Write-Output ("modules dir  : {0}" -f $ModulesDir)
Write-Output ("includes     : {0}" -f $includeNames.Count)
Write-Output ("bytes        : {0}" -f $assembled.Length)
Write-Output ("lines        : {0}" -f $lines)
Write-Output ("sha256       : {0}" -f $hash)

if (-not [string]::IsNullOrWhiteSpace($Out)) {
   $dir = Split-Path -Parent $Out
   if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
   [System.IO.File]::WriteAllBytes($Out, $assembled)
   Write-Output ("written      : {0}" -f $Out)
}
exit 0
