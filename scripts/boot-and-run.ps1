param(
    [switch]$Strict,
    [switch]$NoDisplay
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$preflightArgs = @('-ExecutionPolicy','Bypass','-File','.\scripts\boot-preflight.ps1')
if ($Strict) { $preflightArgs += '-Strict' }

powershell @preflightArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Preflight failed, aborting boot.' -ForegroundColor Red
    exit $LASTEXITCODE
}

$runArgs = @('-ExecutionPolicy','Bypass','-File','.\scripts\run-qemu.ps1')
if ($NoDisplay) { $runArgs += '-NoDisplay' }

powershell @runArgs
exit $LASTEXITCODE
