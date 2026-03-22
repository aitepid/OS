param(
    [switch]$RequireHlBootstrap,
    [string]$HlBootstrapCmd = '.\hl-bootstrap.cmd'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$checks = @(
    @{ Name = 'Workspace validation'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\validate-workspace.ps1' },
    @{ Name = 'Boot chain readiness'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\boot-readiness.ps1' },
    @{ Name = 'Runtime path readiness'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\runtime-path-readiness.ps1' },
    @{ Name = 'Image layout readiness'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\image-layout-readiness.ps1' },
    @{ Name = 'Boot binary analysis'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\boot-binary-analysis.ps1' },
    @{ Name = 'QEMU boot test'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\qemu-boot-test.ps1 -TimeoutSec 12' },
    @{ Name = 'QEMU UEFI test'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\qemu-uefi-test.ps1 -TimeoutSec 12' },
    @{ Name = 'Performance baseline'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\perf-baseline.ps1' },
    @{ Name = 'Release validation'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1' }
)

$hlCmdExists = $false
if (Test-Path $HlBootstrapCmd) {
    $hlCmdExists = $true
} elseif (Get-Command $HlBootstrapCmd -ErrorAction SilentlyContinue) {
    $hlCmdExists = $true
}

if ($hlCmdExists) {
    $checks += @{ Name = 'hl-bootstrap build/test'; Cmd = "powershell -ExecutionPolicy Bypass -File .\\scripts\\hl-bootstrap-build-test.ps1 -HlBootstrapCmd `"$HlBootstrapCmd`"" }
} elseif ($RequireHlBootstrap) {
    $checks += @{ Name = 'hl-bootstrap build/test'; Cmd = "powershell -ExecutionPolicy Bypass -File .\\scripts\\hl-bootstrap-build-test.ps1 -HlBootstrapCmd `"$HlBootstrapCmd`"" }
} else {
    Write-Host 'Warning: hl-bootstrap command not found, skipping hl-bootstrap build/test step.' -ForegroundColor Yellow
}

$failed = @()

foreach ($c in $checks) {
    Write-Host "==> Running: $($c.Name)" -ForegroundColor Cyan
    cmd /c $c.Cmd
    if ($LASTEXITCODE -ne 0) {
        $failed += $c.Name
    }
}

if ($failed.Count -gt 0) {
    Write-Host 'Full gate failed:' -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'Full gate passed.' -ForegroundColor Green
Write-Host '- workspace validation: OK'
Write-Host '- boot chain readiness: OK'
Write-Host '- runtime path readiness: OK'
Write-Host '- image layout readiness: OK'
Write-Host '- boot binary analysis: OK'
Write-Host '- QEMU boot test: OK'
Write-Host '- QEMU UEFI test: OK'
Write-Host '- performance baseline: OK'
Write-Host '- release validation: OK'
if ($hlCmdExists) {
    Write-Host '- hl-bootstrap build/test: OK'
}
