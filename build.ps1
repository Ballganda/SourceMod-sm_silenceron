# Compiles sm_silenceron.sp into plugins\sm_silenceron.smx using the spcomp that ships
# with the SourceMod install on the local test server.
#   .\build.ps1            compile only
#   .\build.ps1 -Deploy    compile, then copy the .smx to the server
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

$sp = Join-Path $PSScriptRoot 'sm_silenceron.sp'
$smx = Join-Path $out 'sm_silenceron.smx'
& $spcomp $sp "-i$incs" "-i$SourceModDir\scripting\include" "-o$smx"
if ($LASTEXITCODE -ne 0) { Write-Error 'sm_silenceron failed to compile'; exit 1 }

if ($Deploy) {
    Copy-Item $smx (Join-Path $SourceModDir 'plugins') -Force
    Write-Host 'Deployed sm_silenceron.smx'
}
