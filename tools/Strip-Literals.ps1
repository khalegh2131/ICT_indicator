# =====================================================================
# Strip-Literals.ps1  --  reduce a translation unit to its logic
#
#   WHY THIS EXISTS
#     The module split is guarded by a frozen hash (Verify-ModuleSplit.ps1),
#     which is exactly right for a pure refactor: the assembled unit must be
#     byte-identical. But phase 42 was a DELIBERATE change - the teaching text
#     and the engine's note/reason/status strings were rewritten so that no
#     Latin word sits inside a Persian clause. Such a change cannot be
#     justified by a hash, and editing the frozen hash "because the build
#     failed" is faith, not evidence.
#
#     So the justification is an external diff: strip everything that cannot
#     affect behaviour, then diff. What survives is the logic.
#
#   WHAT IS REMOVED
#     1. every string literal (replaced by "")
#     2. every comment (line and block)
#     3. insignificant whitespace (runs of spaces/tabs, blank lines, trailing
#        spaces) - because a shortened literal legitimately shifts the
#        continuation-line alignment of the arguments after it
#
#   WHAT SURVIVES
#     Every identifier, operator, number, condition, loop, call and buffer
#     index - i.e. anything that can change a drawn price, a score, a registry
#     write or a branch.
#
#   USAGE (the exact procedure used to re-freeze the hash)
#     powershell -File tools/Assemble-Canonical.ps1 -Out .tmp/cur.mq5
#     powershell -File tools/Assemble-Canonical.ps1 `
#        -Shell 08_FINAL_PACKAGE/ICT_Assistant_Canonical_v0_1/ICT_Assistant_Canonical_v0_1.mq5 `
#        -ModulesDir 08_FINAL_PACKAGE/ICT_Assistant_Canonical_v0_1/modules -Out .tmp/before.mq5
#     powershell -File tools/Strip-Literals.ps1 -Path .tmp/before.mq5 > .tmp/before.logic
#     powershell -File tools/Strip-Literals.ps1 -Path .tmp/cur.mq5    > .tmp/cur.logic
#     diff .tmp/before.logic .tmp/cur.logic      # must contain only text rows
#
#   Read-only. No build. Writes stdout only.
#
#   NOTE  the string-aware scanner is deliberate, not a regex: a regex would
#         mistake an escaped quote (\") for the end of a literal and then treat
#         the rest of the line as code.
# =====================================================================
param(
   [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }

# Read as UTF-8 and drop a BOM if present, so the token stream starts clean.
$s = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
if ($s.Length -gt 0 -and [int]$s[0] -eq 0xFEFF) { $s = $s.Substring(1) }

$sb = New-Object System.Text.StringBuilder
$i = 0
$n = $s.Length

while ($i -lt $n) {
   $c = $s[$i]

   # ---- string literal -> "" -------------------------------------------
   if ($c -eq '"') {
      [void]$sb.Append('""')
      $i++
      while ($i -lt $n) {
         if ($s[$i] -eq '\') { $i += 2; continue }   # escaped char inside literal
         if ($s[$i] -eq '"') { $i++; break }
         $i++
      }
      continue
   }

   # ---- block comment -----------------------------------------------
   if ($c -eq '/' -and $i + 1 -lt $n -and $s[$i + 1] -eq '*') {
      $i += 2
      while ($i + 1 -lt $n -and -not ($s[$i] -eq '*' -and $s[$i + 1] -eq '/')) { $i++ }
      $i += 2
      continue
   }

   # ---- line comment -------------------------------------------------
   if ($c -eq '/' -and $i + 1 -lt $n -and $s[$i + 1] -eq '/') {
      while ($i -lt $n -and $s[$i] -ne "`n") { $i++ }
      continue
   }

   [void]$sb.Append($c)
   $i++
}

$t = $sb.ToString()

# ---- whitespace normalisation -------------------------------------
$t = [regex]::Replace($t, '[ \t]+', ' ')
$t = [regex]::Replace($t, "(\r?\n)\s*(\r?\n)+", "`n")

# Empty/whitespace-only lines carry no information and their count changes when
# a literal gets shorter (a wrapped call becomes one line), so they are dropped.
$lines = $t -split "`n" |
         ForEach-Object { $_.TrimEnd() } |
         Where-Object { $_.Trim().Length -gt 0 }

$lines -join "`n"
