param(
    [string]$MetaEditor = 'C:\Program Files\MetaTrader 5\MetaEditor64.exe'
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot '..\01_CANONICAL_CANDIDATES\ICT_Assistant_Canonical.mq5'
$package = Join-Path $PSScriptRoot '..\08_FINAL_PACKAGE\ICT_Assistant_Canonical_v0_1\ICT_Assistant_Canonical_v0_1.mq5'
$mirror = 'C:\Users\Khaleq\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Indicators\khaleq\newICT\ICT_Assistant_Canonical_v0_1.mq5'

if (-not (Test-Path $source)) { throw "Canonical source not found: $source" }
if (-not (Test-Path $MetaEditor)) { throw "MetaEditor not found: $MetaEditor" }

$running = @(Get-Process -Name 'metaeditor64','metaeditor' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Write-Output ("NOTE: MetaEditor is already running (PID {0}). Command-line compilation is often ignored in that state; if the log stays stale this script will fail instead of reporting a false success." -f ($running.Id -join ','))
}

Copy-Item -LiteralPath $source -Destination $package -Force
Copy-Item -LiteralPath $source -Destination $mirror -Force

$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$packageHash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
$mirrorHash = (Get-FileHash -LiteralPath $mirror -Algorithm SHA256).Hash
if ($sourceHash -ne $packageHash -or $sourceHash -ne $mirrorHash) {
    throw 'Copy verification failed before compilation; generated files are not synchronized.'
}

# A stale log from an earlier successful build must never be able to pass the check below.
$log = [System.IO.Path]::ChangeExtension($mirror, '.log')
$ex5 = [System.IO.Path]::ChangeExtension($mirror, '.ex5')
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

& $MetaEditor "/compile:$mirror" /log

# Wait until the log is not only present but finished (the file appears before it is written).
$logText = ''
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $log) {
        $logText = Get-Content -LiteralPath $log -Raw
        if ($logText -match 'Result:') { break }
    }
    Start-Sleep -Milliseconds 400
}
if ($logText -notmatch 'Result:') {
    throw 'MetaEditor produced no completed compile log. Close MetaEditor completely and run again.'
}
if ($logText -notmatch 'Result:\s*0 errors, 0 warnings') {
    $logText | Select-String -Pattern 'error|warning|Result' -CaseSensitive:$false
    throw 'MetaEditor compilation did not pass with zero errors and warnings.'
}

# The compiler writes the log first and the .ex5 right after it, so allow a short settle time.
$deadlineEx5 = (Get-Date).AddSeconds(30)
while (-not (Test-Path -LiteralPath $ex5) -and (Get-Date) -lt $deadlineEx5) {
    Start-Sleep -Milliseconds 300
}
if (-not (Test-Path -LiteralPath $ex5)) { throw "Compiled artifact not found: $ex5" }
$ex5Time = (Get-Item -LiteralPath $ex5).LastWriteTime
$mirrorTime = (Get-Item -LiteralPath $mirror).LastWriteTime
if ($ex5Time -lt $mirrorTime) {
    throw "Compiled .ex5 ($ex5Time) is older than the source ($mirrorTime): the compile did not really run."
}

$hashes = @(
    $sourceHash,
    $packageHash,
    $mirrorHash
)
if (($hashes | Select-Object -Unique).Count -ne 1) {
    throw 'Canonical source, package, and MT5 mirror hashes do not match.'
}

Write-Output 'Canonical source synchronized and compiled successfully.'
Write-Output 'Result: 0 errors, 0 warnings'
Write-Output "SHA256: $($hashes[0])"
Write-Output "Artifact: $ex5 ($($ex5Time.ToString('yyyy-MM-dd HH:mm:ss')))"