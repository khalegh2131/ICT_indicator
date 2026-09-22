# =====================================================================
# CanonicalSource.ps1  --  shared helper for every validator
#
#   The canonical indicator is no longer one file: the .mq5 is a shell whose
#   body is a list of #include directives, one per strategy family
#   (01_CANONICAL_CANDIDATES/modules/*.mqh).
#
#   The validators grep the SOURCE TEXT, so they must see what the MQL5
#   preprocessor sees: the shell with each include replaced, in order, by the
#   module it names. This helper performs exactly that substitution.
#
#   Two reasons it is a substitution and not a concatenation:
#     1. Line numbers stay identical to the pre-split monolith, because each
#        include line is replaced one-for-one by the module's lines. Any
#        validator that indexes $lines[N] keeps working unchanged.
#     2. Only the modules the shell actually includes are pulled in, so
#        deleting an include changes the flattened text - the file list and
#        the compiled unit cannot drift apart.
#
#   Usage from a validator:
#       . "$PSScriptRoot/CanonicalSource.ps1"
#       $src   = Get-CanonicalSourceText  -Path $Source
#       $lines = Get-CanonicalSourceLines -Path $Source
# =====================================================================

function Get-CanonicalSourceText {
   param(
      [Parameter(Mandatory = $true)][string]$Path
   )

   if (-not (Test-Path -LiteralPath $Path)) { throw "Canonical source not found: $Path" }
   $root = Split-Path -Parent (Resolve-Path -LiteralPath $Path).Path
   $shellLines = [System.IO.File]::ReadAllLines($Path)   # UTF-8 + BOM detected and stripped

   $sb = New-Object System.Text.StringBuilder
   $depth = 0
   foreach ($line in $shellLines) {
      $m = [regex]::Match($line, '^\s*#include\s+"([^"]+)"\s*$')
      if (-not $m.Success) {
         [void]$sb.Append($line)
         [void]$sb.Append("`n")
         continue
      }
      $rel = $m.Groups[1].Value
      $modPath = Join-Path $root $rel
      if (-not (Test-Path -LiteralPath $modPath)) {
         throw ("Included module not found: {0} (declared in {1})" -f $modPath, $Path)
      }
      $depth++
      if ($depth -gt 200) { throw 'Include expansion is too deep - possible include cycle.' }
      foreach ($ml in [System.IO.File]::ReadAllLines($modPath)) {
         [void]$sb.Append($ml)
         [void]$sb.Append("`n")
      }
      $depth--
   }
   return $sb.ToString()
}

function Get-CanonicalSourceLines {
   param(
      [Parameter(Mandatory = $true)][string]$Path
   )
   $text = Get-CanonicalSourceText -Path $Path
   $arr = $text -split "`n"
   # Get-Content drops the empty element a trailing newline would produce; mirror that.
   if ($arr.Count -gt 0 -and $arr[$arr.Count - 1] -eq '') {
      if ($arr.Count -eq 1) { return @() }
      $arr = $arr[0..($arr.Count - 2)]
   }
   return $arr
}
