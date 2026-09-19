param(
    [Parameter(Mandatory=$true)][string]$ReferencePath,
    [Parameter(Mandatory=$true)][string]$CandidatePath
)

$ErrorActionPreference = 'Stop'
$header = @('EventId','EventTime','EventType','Direction','Price','ConfirmationShift','BrokenSwingId','ProtectedSwingId','DisplacementId','SweepId','IsHTF')

function Read-Ledger([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Ledger not found: $Path" }
    $rows = @(Import-Csv -LiteralPath $Path -Delimiter ';' -Header $header)
    $map = @{}
    foreach ($row in $rows) {
        if ($map.ContainsKey($row.EventId)) { throw "Duplicate EventId in ${Path}: $($row.EventId)" }
        $map[$row.EventId] = ($header | ForEach-Object { "$($_)=$($row.$_)" }) -join '|'
    }
    return $map
}

$reference = Read-Ledger $ReferencePath
$candidate = Read-Ledger $CandidatePath
$missing = @($reference.Keys | Where-Object { -not $candidate.ContainsKey($_) })
$added = @($candidate.Keys | Where-Object { -not $reference.ContainsKey($_) })
$changed = @($reference.Keys | Where-Object {
    $candidate.ContainsKey($_) -and $candidate[$_] -ne $reference[$_]
})

Write-Output "Reference events: $($reference.Count)"
Write-Output "Candidate events: $($candidate.Count)"
Write-Output "Missing candidate events: $($missing.Count)"
Write-Output "Added candidate events: $($added.Count)"
Write-Output "Changed event payloads: $($changed.Count)"
if ($missing.Count -gt 0) { Write-Output "First missing: $($missing[0])" }
if ($added.Count -gt 0) { Write-Output "First added: $($added[0])" }
if ($changed.Count -gt 0) { Write-Output "First changed: $($changed[0])" }

if ($missing.Count -gt 0 -or $added.Count -gt 0 -or $changed.Count -gt 0) {
    Write-Output 'Replay comparison: FAILED'
    exit 1
}
Write-Output 'Replay comparison: PASSED'
