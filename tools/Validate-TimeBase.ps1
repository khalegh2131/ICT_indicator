# ICT Canonical - offline time-base verifier (Phase 9)
# Mirrors the rules implemented in 01_CANONICAL_CANDIDATES/ICT_Assistant_Canonical.mq5:
#   NY_IsDST_UTC()        start = 2nd Sunday of March 07:00 UTC, end = 1st Sunday of November 06:00 UTC
#   NyOffsetSecondsUTC()  -4h (EDT) inside that interval, -5h (EST) outside
#   NYWallToServer()      NY wall clock -> broker server time (broker GMT offset in seconds)
# It does NOT touch MetaTrader; it is a pure rule check plus a window report.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File D:/ICT_indicator/tools/Validate-TimeBase.ps1 -BrokerOffsetMinutes 0

param(
    [int]$BrokerOffsetMinutes = 0
)

$script:fail = 0

function New-Utc([int]$y, [int]$mo, [int]$d, [int]$h, [int]$mi) {
    return (New-Object -TypeName System.DateTime -ArgumentList $y, $mo, $d, $h, $mi, 0, ([System.DateTimeKind]::Utc))
}

function Nth-Sunday([int]$year, [int]$month, [int]$nth) {
    $firstDow = [int](New-Object -TypeName System.DateTime -ArgumentList $year, $month, 1).DayOfWeek   # 0 = Sunday
    $firstSunday = 1 + ((7 - $firstDow) % 7)
    return $firstSunday + ($nth - 1) * 7
}

function Utc-Bound([int]$year, [int]$month, [int]$nth, [int]$hour, [int]$minute) {
    $day = Nth-Sunday $year $month $nth
    return (New-Utc $year $month $day $hour $minute)
}

function Ny-IsDstUtc([datetime]$utc) {
    if ($utc.Month -lt 3 -or $utc.Month -gt 11) { return $false }
    $startU = Utc-Bound $utc.Year 3 2 7 0
    $endU   = Utc-Bound $utc.Year 11 1 6 0
    return ($utc -ge $startU -and $utc -lt $endU)
}

function Ny-OffsetSeconds([datetime]$utc) {
    if (Ny-IsDstUtc $utc) { return -4 * 3600 } else { return -5 * 3600 }
}

function Ny-Wall([datetime]$utc) {
    return $utc.AddSeconds((Ny-OffsetSeconds $utc)).ToString("yyyy-MM-dd HH:mm:ss")
}

# Old (buggy) rule that Phase 9 replaced: the whole transition day counted as non-DST.
function Ny-IsDstUtcOld([datetime]$utc) {
    if ($utc.Month -lt 3 -or $utc.Month -gt 11) { return $false }
    if ($utc.Month -gt 3 -and $utc.Month -lt 11) { return $true }
    if ($utc.Month -eq 3) { return ($utc.Day -gt (Nth-Sunday $utc.Year 3 2)) }
    return ($utc.Day -lt (Nth-Sunday $utc.Year 11 1))
}

Write-Output "=== 1) transition dates vs published US rules ==="
$expected = @{ 2024 = @(10, 3); 2025 = @(9, 2); 2026 = @(8, 1); 2027 = @(14, 7); 2028 = @(12, 5) }
foreach ($y in ($expected.Keys | Sort-Object)) {
    $mStart = Nth-Sunday $y 3 2
    $nStart = Nth-Sunday $y 11 1
    $ok = ($mStart -eq $expected[$y][0] -and $nStart -eq $expected[$y][1])
    if (-not $ok) { $script:fail++ }
    $verdict = "OK"
    if (-not $ok) { $verdict = "MISMATCH" }
    Write-Output ("  {0}: DST start = Mar {1} (expected {2}) | DST end = Nov {3} (expected {4})  -> {5}" -f `
            $y, $mStart, $expected[$y][0], $nStart, $expected[$y][1], $verdict)
}

Write-Output ""
Write-Output "=== 2) boundary instants (UTC) -> NY wall clock ==="
foreach ($y in @(2026, 2027)) {
    $startU = Utc-Bound $y 3 2 7 0
    $endU   = Utc-Bound $y 11 1 6 0
    $cases = @(
        @{ label = "start -1s"; t = $startU.AddSeconds(-1); want = "EST" },
        @{ label = "start +0s"; t = $startU;                want = "EDT" },
        @{ label = "end   -1s"; t = $endU.AddSeconds(-1);   want = "EDT" },
        @{ label = "end   +0s"; t = $endU;                  want = "EST" }
    )
    foreach ($c in $cases) {
        $got = "EST"
        if (Ny-IsDstUtc $c.t) { $got = "EDT" }
        $ok = ($got -eq $c.want)
        if (-not $ok) { $script:fail++ }
        $verdict = "OK"
        if (-not $ok) { $verdict = "MISMATCH" }
        Write-Output ("  {0} {1}: UTC {2} -> NY {3} ({4}) expected {5} -> {6}" -f `
                $y, $c.label, $c.t.ToString("yyyy-MM-dd HH:mm:ss"), (Ny-Wall $c.t), $got, $c.want, $verdict)
    }
}

Write-Output ""
Write-Output "=== 3) old rule vs new rule around the 2026 transitions ==="
foreach ($b in @(@{ n = "March start"; t = (Utc-Bound 2026 3 2 7 0) }, @{ n = "November end"; t = (Utc-Bound 2026 11 1 6 0) })) {
    $wrong = 0
    for ($m = -720; $m -le 720; $m++) {
        $t = $b.t.AddMinutes($m)
        if ((Ny-IsDstUtc $t) -ne (Ny-IsDstUtcOld $t)) { $wrong++ }
    }
    Write-Output ("  {0}: old rule disagreed with the correct rule for {1} minute(s) around the transition" -f $b.n, $wrong)
    if ($wrong -eq 0) { $script:fail++ }
}

Write-Output ""
Write-Output ("=== 4) NY session windows -> server time (broker GMT offset = {0} min) ===" -f $BrokerOffsetMinutes)
$regimes = @(
    @{ n = "EDT (summer)"; d = (New-Utc 2026 7 15 12 0) },
    @{ n = "EST (winter)"; d = (New-Utc 2026 1 15 12 0) }
)
$windows = @(
    @{ n = "Asian KZ       "; sh = 20; sm = 0;  eh = 0;  em = 0 },
    @{ n = "London KZ      "; sh = 2;  sm = 0;  eh = 5;  em = 0 },
    @{ n = "NY AM KZ       "; sh = 7;  sm = 0;  eh = 10; em = 0 },
    @{ n = "London Close   "; sh = 10; sm = 0;  eh = 12; em = 0 },
    @{ n = "NY PM KZ       "; sh = 13; sm = 30; eh = 16; em = 0 },
    @{ n = "Silver Bullet 1"; sh = 3;  sm = 0;  eh = 4;  em = 0 },
    @{ n = "Silver Bullet 2"; sh = 10; sm = 0;  eh = 11; em = 0 },
    @{ n = "Silver Bullet 3"; sh = 14; sm = 0;  eh = 15; em = 0 }
)
foreach ($reg in $regimes) {
    $nyOffSec = Ny-OffsetSeconds $reg.d
    Write-Output ("  -- NY offset {0} ({1} s) --" -f $reg.n, $nyOffSec)
    foreach ($w in $windows) {
        $s = [int]($w.sh * 3600 + $w.sm * 60)
        $e = [int]($w.eh * 3600 + $w.em * 60)
        $crosses = $false
        if ($e -le $s) { $e += 86400; $crosses = $true }
        $srvS = $s - $nyOffSec + ($BrokerOffsetMinutes * 60)
        $srvE = $e - $nyOffSec + ($BrokerOffsetMinutes * 60)
        $sTxt = "{0:00}:{1:00}" -f ([math]::Floor(($srvS % 86400) / 3600)), ([math]::Floor(($srvS % 3600) / 60))
        $eTxt = "{0:00}:{1:00}" -f ([math]::Floor(($srvE % 86400) / 3600)), ([math]::Floor(($srvE % 3600) / 60))
        $note = ""
        if ($crosses) { $note = "  (crosses midnight)" }
        Write-Output ("     {0} NY {1:00}:{2:00}-{3:00}:{4:00}  ->  server {5}-{6}{7}" -f `
                $w.n, $w.sh, $w.sm, $w.eh, $w.em, $sTxt, $eTxt, $note)
    }
}

Write-Output ""
if ($script:fail -eq 0) {
    Write-Output "RESULT: all rule checks passed (0 mismatches)"
} else {
    Write-Output ("RESULT: {0} check(s) FAILED" -f $script:fail)
}
