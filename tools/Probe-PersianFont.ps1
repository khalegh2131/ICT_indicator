<#
Probe-PersianFont.ps1 — read-only glyph-coverage probe for Persian (Farsi) text on this machine.

WHY THIS EXISTS
---------------
The canonical indicator converts Persian text to Arabic *Presentation Forms*
before handing it to the MT5 chart renderer, because recent MT5 builds do not
perform bidi/shaping themselves. That only works if the chosen font actually
contains those code points. Tahoma on Windows carries Presentation Forms-B
(U+FE70..U+FEFF) but its coverage of Presentation Forms-A (U+FB50..U+FBFF —
which holds the Persian-specific letters PEH/TCHEH/JEH/KEHEH/GAF/FARSI-YEH and
the lam-alef ligatures) is incomplete on some Windows builds. When a glyph is
missing, GDI draws a fallback box, which the user sees as "not Persian at all".

This script asks GDI directly (GetGlyphIndicesW) which of the code points the
indicator can emit are really present, so the font choice stops being a guess.

It touches nothing: it opens a DC, queries, closes. Run:
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/Probe-PersianFont.ps1
#>

param(
    [string[]]$Fonts = @('Tahoma','Arial','Segoe UI','Times New Roman','Microsoft Sans Serif','Iranian Sans','B Nazanin','Vazirmatn')
)

$ErrorActionPreference = 'Stop'

Add-Type -Namespace IctFont -Name Native -MemberDefinition @'
[DllImport("gdi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern uint GetGlyphIndicesW(IntPtr hdc, string lpstr, int c, ushort[] pgi, uint fl);
[DllImport("gdi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern IntPtr CreateFontW(int cHeight, int cWidth, int cEscapement, int cOrientation,
    int cWeight, uint bItalic, uint bUnderline, uint bStrikeOut, uint iCharSet,
    uint iOutPrecision, uint iClipPrecision, uint iQuality, uint iPitchAndFamily, string pszFaceName);
[DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr h);
[DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
[DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
[DllImport("gdi32.dll", CharSet=CharSet.Unicode)]
public static extern int GetTextFaceW(IntPtr hdc, int nCount, System.Text.StringBuilder lpFaceName);
'@

# One representative code point per family of what the indicator emits.
$probes = [ordered]@{
    'Base  ALEF    U+0627' = 0x0627
    'Base  MEEM    U+0645' = 0x0645
    'Base  HEH     U+0647' = 0x0647
    'Base  F-YEH   U+06CC' = 0x06CC
    'Base  KEHEH   U+06A9' = 0x06A9
    'Base  PEH     U+067E' = 0x067E
    'FormB ALEF iso U+FE8D' = 0xFE8D
    'FormB BEH init U+FE91' = 0xFE91
    'FormB MEEM med U+FEE4' = 0xFEE4
    'FormB F-YEH iso U+FEF1' = 0xFEF1
    'FormA PEH iso  U+FB56' = 0xFB56
    'FormA KEHEH in U+FB90' = 0xFB90
    'FormA GAF med  U+FB94' = 0xFB94
    'FormA F-YEH md U+FBFF' = 0xFBFF
}

$hdc = [IctFont.Native]::GetDC([IntPtr]::Zero)
if ($hdc -eq [IntPtr]::Zero) { throw 'GetDC failed' }

$rows = @()
foreach ($font in $Fonts) {
    $hf = [IctFont.Native]::CreateFontW(-12, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 0, $font)
    if ($hf -eq [IntPtr]::Zero) { continue }
    $old = [IctFont.Native]::SelectObject($hdc, $hf)

    # A font that is not installed is SILENTLY substituted by CreateFontW, which
    # would make every probe look present. Ask GDI which face it really selected.
    $faceSb = New-Object System.Text.StringBuilder 64
    [void][IctFont.Native]::GetTextFaceW($hdc, 64, $faceSb)
    $realFace = $faceSb.ToString()

    $missing = @()
    $present = 0
    foreach ($k in $probes.Keys) {
        $cp = $probes[$k]
        $buf = New-Object 'System.UInt16[]' 1
        $n = [IctFont.Native]::GetGlyphIndicesW($hdc, [string][char]$cp, 1, $buf, 1)
        # 0xFFFF means "no glyph"; 0 (GGI_MARK_NONEXISTING_GLYPHS off) is also suspicious
        if ($n -eq 1 -and $buf[0] -ne 0xFFFF -and $buf[0] -ne 0) { $present++ }
        else { $missing += ($k.Substring(0, [Math]::Min(14, $k.Length))).Trim() }
    }
    [void][IctFont.Native]::SelectObject($hdc, $old)
    [void][IctFont.Native]::DeleteObject($hf)
    $rows +=    [pscustomobject]@{
        Font     = $font
        Resolved = $realFace
        SameFace = ($realFace -eq $font)
        Present  = $present
        Total    = $probes.Count
        Missing  = ($missing -join ', ')
    }
}
[void][IctFont.Native]::ReleaseDC([IntPtr]::Zero, $hdc)

$rows | Format-Table -AutoSize

Write-Output ''
Write-Output '--- verdict ---'
foreach ($r in $rows) {
    if (-not $r.SameFace) {
        Write-Output ("NOT INSTALLED {0} (GDI fell back to '{1}') - it is NOT available to MT5" -f $r.Font, $r.Resolved)
    }
    elseif ($r.Present -eq $r.Total) {
        Write-Output ("OK      {0}: all {1} probe code points have real glyphs" -f $r.Font, $r.Total)
    } else {
        Write-Output ("PARTIAL {0}: {1}/{2} present; missing -> {3}" -f $r.Font, $r.Present, $r.Total, $r.Missing)
    }
}
Write-Output ''
Write-Output 'Rules:'
Write-Output '  1) InpExplainFont must be installed (SameFace = True).'
Write-Output '  2) With InpExplainRenderMode = 0 (default) the panel is an OBJ_EDIT native'
Write-Output '     control that shapes and orders RTL itself, so the BASE code points are'
Write-Output '     what matter - they must all be present.'
Write-Output '  3) Only if you must use mode 2 (shaping in the indicator) do the FormA/FormB'
Write-Output '     code points matter as well.'
