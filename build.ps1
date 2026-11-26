# Compiles sm_silenceron.sp and the test suite (tests\*.sp) into plugins\*.smx using the spcomp
# that ships with the SourceMod install on the local test server.
#   .\build.ps1            compile only
#   .\build.ps1 -Deploy    compile, then copy the .smx files to the server
# Shared includes come from the incs submodule (github.com/Ballganda/SourceMod-Incs):
#   git submodule update --init
param(
    [switch]$Deploy,
    [string]$SourceModDir = $(if ($env:SOURCEMOD_DIR) { $env:SOURCEMOD_DIR } else { 'C:\Users\user\cssds\cstrike\addons\sourcemod' })
)

$spcomp = Join-Path $SourceModDir 'scripting\spcomp.exe'
if (-not (Test-Path $spcomp)) { Write-Error "spcomp not found at $spcomp"; exit 1 }

$incs = Join-Path $PSScriptRoot 'incs\scripting\include'
if (-not (Test-Path (Join-Path $incs 'instance_config.inc'))) {
    Write-Error "Shared includes missing at $incs. Run: git submodule update --init"; exit 1
}
$out = Join-Path $PSScriptRoot 'plugins'
New-Item -ItemType Directory -Force $out | Out-Null

$failed = 0
$targets = @(Get-Item (Join-Path $PSScriptRoot 'sm_silenceron.sp')) +
           @(Get-ChildItem (Join-Path $PSScriptRoot 'tests') -Filter *.sp -ErrorAction SilentlyContinue)
foreach ($sp in $targets) {
    $smx = Join-Path $out ($sp.BaseName + '.smx')
    & $spcomp $sp.FullName "-i$incs" "-i$SourceModDir\scripting\include" "-o$smx"
    if ($LASTEXITCODE -ne 0) { $failed++; continue }
    if ($Deploy) {
        Copy-Item $smx (Join-Path $SourceModDir 'plugins') -Force
        Write-Host "Deployed $($sp.BaseName).smx"
    }
}
if ($failed) { Write-Error "$failed plugin(s) failed to compile"; exit 1 }
