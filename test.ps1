# Checks out a test server slot, builds and deploys the plugin and its suite, runs the suite
# unattended, scans every log the run touched for errors, then cleans and checks the slot in.
#   .\test.ps1                 full run; exit code 0 = all passed and logs clean, 1 = fail, 2 = could not start
#   .\test.ps1 -InjectError    self-check: the suite logs a deliberate error, so this run MUST fail
param(
    [switch]$InjectError,
    [string]$SlotTool = 'C:\Users\user\srcds-slot.ps1',
    [string]$Owner = 'SourceMod-sm_silenceron/test',
    [string]$Map = 'de_dust2',
    [int]$TimeoutSec = 240
)

# Lines that look like errors but are normal on this server.
$benign = @(
    'metamod[\\/]bin[\\/]win64[\\/]server',      # x64 VDF on a 32-bit server
    'vscript_convar_allowlist\.txt',
    '\[(PASS|FAIL)\]', 'tests (started|finished)',   # the suite's own output (judged separately)
    'SilencerTest', 'sm_silenceron test done',       # the fake client's name and kick reason
    'sv_gravity" is not a setting of this plugin'    # C_CFG_FOREIGN writes this line on purpose
)
# Always a failure: script errors, plugins or extensions that did not load, engine faults.
$hard = '\[SM\] (Exception|Blaming|Call stack|Unable to load|Failed to load|Plugin .* failed|Fatal)|' +
        'Exception reported|Native ".*" (reported|was not found)|Script execution timed out|' +
        '<(Failed|Error|Bad Load)>|Could not find required file|Host_Error|Engine Error|' +
        'Segmentation fault|Access violation|Failed to load plugin|Plugin failed to load|required extension'
# Reported as a warning for a human to judge.
$soft = '\b(error|errors|exception|failed|failure|unable to|could not|cannot|invalid|not found|missing|warning|deprecated|leak)\b'

# Text appended to a log since the snapshot (the whole file if it is new or was rotated).
function Get-NewLines([string]$path, $before) {
    if (-not (Test-Path $path)) { return @() }
    $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { $bytes = New-Object byte[] $fs.Length; [void]$fs.Read($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
    $from = 0
    if ($before.ContainsKey($path) -and $before[$path] -le $bytes.Length) { $from = $before[$path] }
    if ($from -ge $bytes.Length) { return @() }
    $text = [Text.Encoding]::UTF8.GetString($bytes, $from, $bytes.Length - $from)
    return @($text -split "`r?`n" | Where-Object { $_.Trim() })
}

function Test-Benign([string]$line) {
    foreach ($b in $benign) { if ($line -match $b) { return $true } }
    return $false
}

$checkout = & $SlotTool checkout -Owner $Owner
if ($LASTEXITCODE -ne 0 -or "$checkout" -notmatch 'slot=(\d+) dir=(\S+) port=(\d+) tvport=(\d+) clientport=(\d+)') {
    Write-Error "no test slot: $checkout"; exit 2
}
$slot = $Matches[1]; $serverDir = $Matches[2]; $port = $Matches[3]; $tvPort = $Matches[4]; $clientPort = $Matches[5]
Write-Host $checkout

$game = Join-Path $serverDir 'cstrike'
$sm = Join-Path $game 'addons\sourcemod'
$smLogs = Join-Path $sm 'logs'
$consoleLog = Join-Path $game 'console.log'
$testLog = Join-Path $smLogs 'sm_silenceron_tests.log'
$added = @(
    (Join-Path $sm 'plugins\sm_silenceron.smx'),
    (Join-Path $sm 'plugins\sm_silenceron_tests.smx'),
    (Join-Path $sm 'configs\sm_silenceron.cfg')
)
$problems = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$exitCode = 1
$proc = $null

try {
    $buildOut = & "$PSScriptRoot\build.ps1" -Deploy -SourceModDir $sm 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { $buildOut | Write-Host; throw 'build failed' }
    foreach ($l in $buildOut) {
        if ($l -match ' : (warning|error) \d+') { $warnings.Add("compiler: " + ($l -replace '^.*\\', '')) }
    }

    $before = @{}
    foreach ($f in @(Get-ChildItem $smLogs -Filter *.log -ErrorAction SilentlyContinue) + @(Get-Item $consoleLog -ErrorAction SilentlyContinue)) {
        $before[$f.FullName] = $f.Length
    }

    $srcdsArgs = "-console -game cstrike -condebug -tickrate 100 -port $port +tv_port $tvPort +clientport $clientPort " +
                 "+sv_lan 1 +maxplayers 10 +bot_quota 0 " +
                 "+sm_silenceron_test_autorun 1 +sm_silenceron_test_inject_error $([int][bool]$InjectError) +map $Map"
    Write-Host "Starting srcds on slot $slot ($Map); the suite takes about 1 minute..."
    $proc = Start-Process (Join-Path $serverDir 'srcds.exe') -ArgumentList $srcdsArgs -WorkingDirectory $serverDir -PassThru
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        Stop-Process -Id $proc.Id -Force
        $problems.Add("server did not quit within ${TimeoutSec}s (suite hung or never started); it was killed")
    }

    # --- the suite's own results ---
    $results = Get-NewLines $testLog $before
    $passed = @($results | Where-Object { $_ -match '\[PASS\]' })
    $failed = @($results | Where-Object { $_ -match '\[FAIL\]' })
    $started = @($results | Where-Object { $_ -match 'tests started \((\d+) cases\)' }) | Select-Object -Last 1
    if (-not $results.Count) { $problems.Add('the suite wrote nothing to sm_silenceron_tests.log (test plugin not loaded?)') }
    elseif (-not ($results | Where-Object { $_ -match 'tests finished:' })) { $problems.Add('the suite never reached its summary line') }
    if ($started -match 'tests started \((\d+) cases\)' -and ($passed.Count + $failed.Count) -lt [int]$Matches[1]) {
        $problems.Add("only $($passed.Count + $failed.Count) of $($Matches[1]) cases reported a result")
    }
    foreach ($l in $failed) { $problems.Add('test: ' + ($l -replace '^.*?(\[FAIL\])', '$1')) }

    # --- every other log the run touched ---
    $logs = @(Get-ChildItem $smLogs -Filter *.log -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $testLog })
    if (Test-Path $consoleLog) { $logs += Get-Item $consoleLog }
    $scanned = 0
    foreach ($f in $logs) {
        $isErrorLog = $f.Name -like 'errors_*'
        foreach ($l in (Get-NewLines $f.FullName $before)) {
            $scanned++
            if (Test-Benign $l) { continue }
            if ($isErrorLog -or $l -match $hard) { $problems.Add("$($f.Name): $l") }
            elseif ($l -match $soft) { $warnings.Add("$($f.Name): $l") }
        }
    }

    Write-Host ''
    foreach ($l in $passed) { Write-Host ($l -replace '^.*?(\[PASS\])', '$1') -ForegroundColor DarkGreen }
    foreach ($l in $failed) { Write-Host ($l -replace '^.*?(\[FAIL\])', '$1') -ForegroundColor Red }
    Write-Host ''
    Write-Host "Cases: $($passed.Count) passed, $($failed.Count) failed. Scanned $scanned new log lines in $($logs.Count) files."
    $exitCode = 0
}
catch {
    $problems.Add("run aborted: $_")
}
finally {
    # Teardown: leave the slot as the template has it, then release it.
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force; $proc.WaitForExit(10000) | Out-Null }
    foreach ($f in $added) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    $checkin = & $SlotTool checkin -Slot $slot -Owner $Owner
    Write-Host "`n$checkin"
    if ($LASTEXITCODE -ne 0) { $problems.Add("slot $slot not clean after teardown: $checkin") }
}

if ($warnings.Count) {
    Write-Host "`nWarnings ($($warnings.Count)):" -ForegroundColor Yellow
    $warnings | Select-Object -Unique | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}
if ($problems.Count -or $exitCode -ne 0) {
    Write-Host "`nProblems ($($problems.Count)):" -ForegroundColor Red
    $problems | Select-Object -Unique | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host "`nRESULT: FAIL" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: PASS" -ForegroundColor Green
exit 0
