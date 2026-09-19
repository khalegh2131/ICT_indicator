param(
    [string]$LedgerPath = "$env:APPDATA\MetaQuotes\Terminal\Common\Files\ICT_Assistant_V13_Events_v1.csv"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $LedgerPath)) {
    Write-Output "Ledger not found: $LedgerPath"
    Write-Output "Attach the V13 canonical indicator to a chart and process at least one new closed bar."
    exit 2
}

$rows = Import-Csv -LiteralPath $LedgerPath -Delimiter ';' -Header EventId,EventTime,EventType,Direction,Price,ConfirmationShift,BrokenSwingId,ProtectedSwingId,DisplacementId,SweepId,IsHTF
if ($rows.Count -eq 0) { throw 'Ledger is empty.' }

$duplicateIds = @($rows | Group-Object EventId | Where-Object Count -gt 1)
$missingType = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.EventType) })
$missingDirection = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.Direction) })
# LTF events confirm on chart shift 1; HTF as-of events use shift 0
# because CopyRatesAsOf has already removed the unfinished HTF bar.
$invalidShift = @($rows | Where-Object { $_.ConfirmationShift -notin @('0','1') })
$invalidTimes = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.EventTime) })

Write-Output "Ledger: $LedgerPath"
Write-Output "Events: $($rows.Count)"
Write-Output "Duplicate IDs: $($duplicateIds.Count)"
Write-Output "Missing event types: $($missingType.Count)"
Write-Output "Missing directions: $($missingDirection.Count)"
Write-Output "Non-closed confirmation shifts: $($invalidShift.Count)"
Write-Output "Missing event times: $($invalidTimes.Count)"

if ($duplicateIds.Count -gt 0 -or $missingType.Count -gt 0 -or $missingDirection.Count -gt 0 -or $invalidShift.Count -gt 0 -or $invalidTimes.Count -gt 0) {
    Write-Output 'V13 event ledger validation: FAILED'
    exit 1
}

Write-Output 'V13 event ledger validation: PASSED'
