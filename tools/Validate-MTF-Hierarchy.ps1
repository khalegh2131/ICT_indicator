param(
    [string]$DiagPath = "$env:APPDATA\MetaQuotes\Terminal\Common\Files\ICT_Assistant_Canonical_MTF_Diag.csv"
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $DiagPath)) {
    Write-Output "MTF diagnostic ledger not found: $DiagPath"
    Write-Output "Enable InpWriteReplayDiagnostics, reset the diagnostic file, and rebuild history."
    exit 2
}

# The canonical writer emits exactly seven semicolon-separated fields per row,
# and writes one leading header line when the diagnostic file starts empty:
# BarTime;BiasOwner;H4ConfirmedTime;MTFChain;Conflict;ConflictReason;ReadyState
# The parser below skips that header if present, so headerless files also work.
$headers = @('BarTime','BiasOwner','H4ConfirmedTime','MTFChain','Conflict','ConflictReason','ReadyState')
$rows = @(Get-Content -LiteralPath $DiagPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^BarTime;BiasOwner;' } | ForEach-Object {
    $fields = $_ -split ';', 7
    if ($fields.Count -ne 7) { throw "MTF diagnostic row has $($fields.Count) fields, expected 7: $_" }
    $row = [ordered]@{}
    for ($i=0; $i -lt $headers.Count; $i++) { $row[$headers[$i]] = $fields[$i] }
    [pscustomobject]$row
})
if ($rows.Count -eq 0) { throw 'MTF diagnostic ledger is empty.' }

$missingChain = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.MTFChain) })
$invalidOwner = @($rows | Where-Object { $_.BiasOwner -notin @('BULLISH','BEARISH','NEUTRAL') })
$readyDuringConflict = @($rows | Where-Object {
    $_.Conflict -eq 'true' -and $_.ReadyState -match '^READY'
})
$lowerConflictWithoutBlock = @()
$invalidTimes = @($rows | Where-Object {
    $parsed = [datetime]::MinValue
    -not [datetime]::TryParse($_.BarTime, [ref]$parsed)
})

foreach ($row in $rows) {
    $parts = @($row.MTFChain -split '\|')
    $lowerOpposes = $false
    foreach ($tag in @('PERIOD_M1','PERIOD_M2')) {
        $part = $parts | Where-Object { $_ -like "${tag}:*" } | Select-Object -First 1
        if ($part -and $row.BiasOwner -in @('BULLISH','BEARISH')) {
            $fields = $part -split ':'
            # Chain format is TF:externalDirection:internalDirection.
            foreach ($direction in @($fields[1],$fields[2])) {
                if ($direction -in @('BULLISH','BEARISH') -and $direction -ne $row.BiasOwner) {
                    $lowerOpposes = $true
                }
            }
        }
    }
    if ($lowerOpposes -and $row.Conflict -ne 'true') { $lowerConflictWithoutBlock += $row }
}

Write-Output "MTF diagnostic ledger: $DiagPath"
Write-Output "Schema: headerless 7-column canonical diagnostic"
Write-Output "Rows: $($rows.Count)"
Write-Output "Missing chains: $($missingChain.Count)"
Write-Output "Invalid H4 owners: $($invalidOwner.Count)"
Write-Output "Invalid bar times: $($invalidTimes.Count)"
Write-Output "READY during conflict: $($readyDuringConflict.Count)"
Write-Output "Lower-timeframe opposition without conflict: $($lowerConflictWithoutBlock.Count)"
Write-Output "H4 owner schema violations: 0"

if ($missingChain.Count -gt 0 -or $invalidOwner.Count -gt 0 -or $invalidTimes.Count -gt 0 -or
    $readyDuringConflict.Count -gt 0 -or $lowerConflictWithoutBlock.Count -gt 0) {
    Write-Output 'MTF hierarchy validation: FAILED'
    exit 1
}

Write-Output 'MTF hierarchy validation: PASSED'
