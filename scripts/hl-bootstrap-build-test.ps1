$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

Write-Host 'Running hl-bootstrap build...' -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File '.\scripts\boot-readiness.ps1'
if ($LASTEXITCODE -ne 0) {
    Write-Host "hl-bootstrap build failed with code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}
powershell -ExecutionPolicy Bypass -File '.\scripts\image-layout-readiness.ps1'
if ($LASTEXITCODE -ne 0) {
    Write-Host "hl-bootstrap build failed with code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Phase 1: Compilation pipeline (lex all kernel modules)
Write-Host 'Running compilation pipeline (Phase 1: Lex)...' -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File '.\scripts\hl-compile-pipeline.ps1'
if ($LASTEXITCODE -ne 0) {
    Write-Host "hl-bootstrap compile-pipeline failed with code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

powershell -ExecutionPolicy Bypass -File '.\scripts\rebuild-image.ps1'
if ($LASTEXITCODE -ne 0) {
    Write-Host "hl-bootstrap build failed with code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host 'Running hl-bootstrap tests...' -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File '.\scripts\validate-workspace.ps1' -StrictLanguagePurity
if ($LASTEXITCODE -ne 0) {
    Write-Host "hl-bootstrap tests failed with code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}
powershell -ExecutionPolicy Bypass -File '.\scripts\runtime-path-readiness.ps1'
if ($LASTEXITCODE -ne 0) {
    Write-Host "hl-bootstrap tests failed with code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host 'hl-bootstrap build/test passed.' -ForegroundColor Green
