param(
    [string]$LedgerPath = ""
)

$ErrorActionPreference = 'Stop'

# 2026-09-18: the live ledger is now scoped per symbol
# (ICT_Assistant_V13_Events_v1_<SYMBOL>.csv) because several charts/symbols
# previously appended into one shared file, which made the audit trail
# unreadable (rows from a 179.x symbol inside the XAUUSD ledger) and broke any
# time-ordering check. Auto-discover the newest symbol-scoped ledger and fall
# back to the legacy shared file when none exists yet.
if ([string]::IsNullOrWhiteSpace($LedgerPath)) {
    $common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
    $candidate = Get-ChildItem -LiteralPath $common -Filter 'ICT_Assistant_V13_Events_v1_*.csv' -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate) {
        $LedgerPath = $candidate.FullName
        Write-Output "Ledger (auto-discovered, newest symbol-scoped): $LedgerPath"
    } else {
        $LedgerPath = Join-Path $common 'ICT_Assistant_V13_Events_v1.csv'
        Write-Output "Ledger (legacy shared file): $LedgerPath"
    }
}

if (-not (Test-Path -LiteralPath $LedgerPath)) {
    Write-Output "Ledger not found: $LedgerPath"
    Write-Output "Attach the canonical indicator and allow at least one closed bar to be processed."
    exit 2
}

# The canonical source writes this exact 11-column structure-event schema.
$rows = @(Import-Csv -LiteralPath $LedgerPath -Delimiter ';' -Header `
    EventId,EventTime,EventType,Direction,Price,ConfirmationShift,
    BrokenSwingId,ProtectedSwingId,DisplacementId,SweepId,IsHTF)
if ($rows.Count -eq 0) { throw 'Ledger is empty.' }

$duplicateIds = @($rows | Group-Object EventId | Where-Object Count -gt 1)
$missingType = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.EventType) })
$missingDirection = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.Direction) })
# Live processing uses shift 1; historical replay uses the source bar's positive shift.
$invalidShift = @($rows | Where-Object {
    $parsed = 0
    -not [int]::TryParse($_.ConfirmationShift, [ref]$parsed) -or $parsed -le 0
})
$invalidIds = @($rows | Where-Object {
    $parsed = 0L
    -not [long]::TryParse($_.EventId, [ref]$parsed)
})
$invalidTimes = @($rows | Where-Object {
    $parsed = [datetime]::MinValue
    -not [datetime]::TryParse($_.EventTime, [ref]$parsed)
})

$times = @($rows | ForEach-Object {
    $parsed = [datetime]::MinValue
    [datetime]::TryParse($_.EventTime, [ref]$parsed) | Out-Null
    $parsed
})
# ---------------------------------------------------------------------------
# Multi-timeframe ledger (2026-09-18 fix):
# Rows are appended in *event-creation* order. An H4 (IsHTF=true) event created
# after an M15 event legitimately carries an EARLIER bar time, so strict global
# monotonicity is NOT a valid invariant for this ledger. Monotonicity is checked
# within each timeframe; cross-timeframe interleaving is reported as
# informational only.
# ---------------------------------------------------------------------------
$ltfTimes = @($rows | Where-Object { -not ($_.IsHTF -match '(?i)^true$') } | ForEach-Object {
    $p = [datetime]::MinValue
    [datetime]::TryParse($_.EventTime, [ref]$p) | Out-Null
    $p
})
$htfTimes = @($rows | Where-Object { $_.IsHTF -match '(?i)^true$' } | ForEach-Object {
    $p = [datetime]::MinValue
    [datetime]::TryParse($_.EventTime, [ref]$p) | Out-Null
    $p
})
$ltfOutOfOrder = 0
for ($i = 1; $i -lt $ltfTimes.Count; $i++) { if ($ltfTimes[$i] -lt $ltfTimes[$i - 1]) { $ltfOutOfOrder++ } }
$htfOutOfOrder = 0
for ($i = 1; $i -lt $htfTimes.Count; $i++) { if ($htfTimes[$i] -lt $htfTimes[$i - 1]) { $htfOutOfOrder++ } }
$nonMonotonic = 0
for ($index = 1; $index -lt $times.Count; $index++) {
    if ($times[$index] -lt $times[$index - 1]) { $nonMonotonic++ }
}

Write-Output "Ledger: $LedgerPath"
Write-Output "Schema: 11-column structure event ledger"
Write-Output "Events: $($rows.Count)"
Write-Output "Duplicate IDs: $($duplicateIds.Count)"
Write-Output "Invalid IDs: $($invalidIds.Count)"
Write-Output "Missing event types: $($missingType.Count)"
Write-Output "Missing directions: $($missingDirection.Count)"
Write-Output "Non-closed/non-positive confirmation shifts: $($invalidShift.Count)"
Write-Output "Invalid event times: $($invalidTimes.Count)"
Write-Output "Out-of-order LTF rows: $ltfOutOfOrder"
Write-Output "Out-of-order HTF rows: $htfOutOfOrder"
Write-Output "Cross-timeframe interleaved rows (informational): $nonMonotonic"

if ($duplicateIds.Count -gt 0 -or $invalidIds.Count -gt 0 -or
    $missingType.Count -gt 0 -or $missingDirection.Count -gt 0 -or
    $invalidShift.Count -gt 0 -or $invalidTimes.Count -gt 0 -or
    $ltfOutOfOrder -gt 0 -or $htfOutOfOrder -gt 0) {
    Write-Output 'Canonical event ledger validation: FAILED'
    exit 1
}

Write-Output 'Canonical event ledger validation: PASSED'
