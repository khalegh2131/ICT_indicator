param(
    [string]$MetaEditor = 'C:\Program Files\MetaTrader 5\MetaEditor64.exe',
    [string]$RepoRoot  = '',                 # defaults to the parent of tools/
    [switch]$SkipSplitCheck
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Layout
#
# The canonical indicator is a shell (.mq5) whose body is a list of #include
# directives, one per strategy family, plus the modules themselves. MQL5
# resolves a quoted include relative to the INCLUDING file's directory, so the
# shell and its modules/ folder must always travel together and keep the same
# relative position. This script mirrors both, then compiles the shell.
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Split-Path -Parent $PSScriptRoot }

$sourceShell   = Join-Path $RepoRoot '01_CANONICAL_CANDIDATES\ICT_Assistant_Canonical.mq5'
$sourceModules = Join-Path $RepoRoot '01_CANONICAL_CANDIDATES\modules'

$packageDir     = Join-Path $RepoRoot '08_FINAL_PACKAGE\ICT_Assistant_Canonical_v0_1'
$packageShell   = Join-Path $packageDir 'ICT_Assistant_Canonical_v0_1.mq5'
$packageModules = Join-Path $packageDir 'modules'

$mirrorDir     = 'C:\Users\Khaleq\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Indicators\khaleq\newICT'
$mirrorShell   = Join-Path $mirrorDir 'ICT_Assistant_Canonical_v0_1.mq5'
$mirrorModules = Join-Path $mirrorDir 'modules'

if (-not (Test-Path -LiteralPath $sourceShell))   { throw "Canonical shell not found: $sourceShell" }
if (-not (Test-Path -LiteralPath $sourceModules)) { throw "Module folder not found: $sourceModules" }
if (-not (Test-Path -LiteralPath $MetaEditor))    { throw "MetaEditor not found: $MetaEditor" }

$running = @(Get-Process -Name 'metaeditor64','metaeditor' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Write-Output ("NOTE: MetaEditor is already running (PID {0}). Command-line compilation is often ignored in that state; if the log stays stale this script will fail instead of reporting a false success." -f ($running.Id -join ','))
}

# ---------------------------------------------------------------------------
# Pre-flight: the split must still reassemble to the frozen pre-split source.
# Compiling a module tree that no longer equals the reviewed source would make
# every other guarantee in this repository meaningless, so it is checked before
# anything is copied.
# ---------------------------------------------------------------------------
if (-not $SkipSplitCheck) {
    $verify = Join-Path $PSScriptRoot 'Verify-ModuleSplit.ps1'
    if (-not (Test-Path -LiteralPath $verify)) { throw "Split verifier not found: $verify" }
    $verifyOut  = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verify -Shell $sourceShell -ModulesDir $sourceModules
    $verifyText = ($verifyOut | Out-String)
    if ($verifyText -notmatch 'RESULT: PASS=\d+ FAIL=0') {
        $verifyText | Select-String -Pattern 'FAIL|RESULT' -CaseSensitive:$false
        throw 'Module split verification failed; refusing to build.'
    }
    $splitLine = ($verifyText -split "`n" | Where-Object { $_ -match 'Assembled SHA256' } | Select-Object -First 1)
    Write-Output ("Split check: OK  {0}" -f (($splitLine -replace '\s+', ' ').Trim()))
}

# ---------------------------------------------------------------------------
# Mirror the tree (shell + every module) to the package and to the MT5 folder.
# Module files that no longer exist in the repository are removed from the
# destinations; otherwise a deleted module would keep compiling from a stale
# copy and the build would not reflect the source.
# ---------------------------------------------------------------------------
function Sync-ModuleTree {
    param([string]$Destination)
    if (-not (Test-Path -LiteralPath $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    $wanted = @{}
    foreach ($m in Get-ChildItem -LiteralPath $sourceModules -Filter '*.mqh' -File) { $wanted[$m.Name] = $true }
    foreach ($existing in Get-ChildItem -LiteralPath $Destination -Filter '*.mqh' -File) {
        if (-not $wanted.ContainsKey($existing.Name)) {
            Remove-Item -LiteralPath $existing.FullName -Force
            Write-Output ("  removed stale module: {0}" -f $existing.Name)
        }
    }
    foreach ($name in $wanted.Keys) {
        Copy-Item -LiteralPath (Join-Path $sourceModules $name) -Destination (Join-Path $Destination $name) -Force
    }
    return $wanted.Keys.Count
}

foreach ($dest in @(@{ Dir = $packageDir; Label = 'package' }, @{ Dir = $mirrorDir; Label = 'MT5' })) {
    if (-not (Test-Path -LiteralPath $dest.Dir)) { New-Item -ItemType Directory -Path $dest.Dir -Force | Out-Null }
    Copy-Item -LiteralPath $sourceShell -Destination (Join-Path $dest.Dir (Split-Path -Leaf $packageShell)) -Force
    $n = Sync-ModuleTree -Destination (Join-Path $dest.Dir 'modules')
    Write-Output ("Mirrored shell + {0} modules -> {1}" -f $n, $dest.Label)
}

# ---------------------------------------------------------------------------
# Verify the mirror really matches the source, file by file.
# ---------------------------------------------------------------------------
function Assert-SameBytes {
    param([string]$A, [string]$B, [string]$Label)
    if (-not (Test-Path -LiteralPath $B)) { throw "$Label missing: $B" }
    $ha = (Get-FileHash -LiteralPath $A -Algorithm SHA256).Hash
    $hb = (Get-FileHash -LiteralPath $B -Algorithm SHA256).Hash
    if ($ha -ne $hb) { throw "$Label does not match the source: $B" }
    return $ha
}

$shellHash = Assert-SameBytes -A $sourceShell -B $packageShell -Label 'package shell'
$null      = Assert-SameBytes -A $sourceShell -B $mirrorShell  -Label 'MT5 shell'

$moduleHashes = @()
foreach ($m in Get-ChildItem -LiteralPath $sourceModules -Filter '*.mqh' -File | Sort-Object Name) {
    $null = Assert-SameBytes -A $m.FullName -B (Join-Path $packageModules $m.Name) -Label ("package module $($m.Name)")
    $null = Assert-SameBytes -A $m.FullName -B (Join-Path $mirrorModules  $m.Name) -Label ("MT5 module $($m.Name)")
    $moduleHashes += (Get-FileHash -LiteralPath $m.FullName -Algorithm SHA256).Hash
}
Write-Output ("Copy verification: shell + {0} modules identical in source, package and MT5 folder" -f $moduleHashes.Count)

# A stale log from an earlier successful build must never be able to pass the check below.
$log = [System.IO.Path]::ChangeExtension($mirrorShell, '.log')
$ex5 = [System.IO.Path]::ChangeExtension($mirrorShell, '.ex5')
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

& $MetaEditor "/compile:$mirrorShell" /log

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
$newestInput = (Get-Item -LiteralPath $mirrorShell).LastWriteTime
foreach ($m in Get-ChildItem -LiteralPath $mirrorModules -Filter '*.mqh' -File) {
    if ($m.LastWriteTime -gt $newestInput) { $newestInput = $m.LastWriteTime }
}
if ($ex5Time -lt $newestInput) {
    throw ("Compiled .ex5 ({0}) is older than the newest source file ({1}): the compile did not really run." -f $ex5Time, $newestInput)
}

# ---------------------------------------------------------------------------
# Delete the compile log. MetaEditor writes it next to the target as UTF-16 text,
# and a stale .log in the indicator folder is a real trap: if the log happens to be
# the active document when someone presses Compile, MetaEditor compiles the log
# itself and reports dozens of bogus syntax errors ("'C' - unexpected token" on the
# path line, "invalid suffix '_HeaderAndInputs'" on the include lines, "cpu" inside
# the Result line) that look like they come from the indicator. Everything worth
# keeping from this log has already been asserted above and is echoed below.
# ---------------------------------------------------------------------------
Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue

Write-Output 'Canonical source synchronized and compiled successfully.'
Write-Output 'Result: 0 errors, 0 warnings'
Write-Output ("Shell SHA256      : {0}" -f $shellHash)
Write-Output ("Modules           : {0} files, all mirrored and verified" -f $moduleHashes.Count)
Write-Output ("Artifact          : {0} ({1})" -f $ex5, $ex5Time.ToString('yyyy-MM-dd HH:mm:ss'))
Write-Output ("Artifact SHA256   : {0}" -f (Get-FileHash -LiteralPath $ex5 -Algorithm SHA256).Hash)
