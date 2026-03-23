param(
    [switch]$RequireHlBootstrap,
    [string]$HlBootstrapCmd = '.\hl-bootstrap.cmd',
    [switch]$SkipQemu,
    [switch]$RequireQemu
)

$ErrorActionPreference = 'Stop'

if ($SkipQemu -and $RequireQemu) {
    Write-Host 'Cannot use -SkipQemu and -RequireQemu together.' -ForegroundColor Red
    exit 1
}

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

$qemuCheckNames = @('QEMU boot test', 'QEMU UEFI test')

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
$skipped = @()
$skipReasons = @{}

if ($SkipQemu) {
    $checks = $checks | Where-Object { $qemuCheckNames -notcontains $_.Name }
    foreach ($name in $qemuCheckNames) {
        $skipped += $name
        $skipReasons[$name] = 'explicitly skipped by -SkipQemu'
    }
}

foreach ($c in $checks) {
    Write-Host "==> Running: $($c.Name)" -ForegroundColor Cyan
    cmd /c $c.Cmd
    if ($LASTEXITCODE -eq 2) {
        if ($RequireQemu -and ($qemuCheckNames -contains $c.Name)) {
            $failed += $c.Name
            Write-Host "Failed: $($c.Name) (QEMU/OVMF required but prerequisite missing)" -ForegroundColor Red
        } else {
            $skipped += $c.Name
            $skipReasons[$c.Name] = 'prerequisite missing'
            Write-Host "Skipped: $($c.Name) (prerequisite missing)" -ForegroundColor Yellow
        }
    } elseif ($LASTEXITCODE -ne 0) {
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
if ($skipped -contains 'QEMU boot test') {
    Write-Host "- QEMU boot test: SKIPPED ($($skipReasons['QEMU boot test']))" -ForegroundColor Yellow
} else {
    Write-Host '- QEMU boot test: OK'
}
if ($skipped -contains 'QEMU UEFI test') {
    Write-Host "- QEMU UEFI test: SKIPPED ($($skipReasons['QEMU UEFI test']))" -ForegroundColor Yellow
} else {
    Write-Host '- QEMU UEFI test: OK'
}
Write-Host '- performance baseline: OK'
Write-Host '- release validation: OK'
if ($hlCmdExists) {
    Write-Host '- hl-bootstrap build/test: OK'
}
if ($skipped.Count -gt 0) {
    Write-Host '- skipped checks:' -ForegroundColor Yellow
    $skipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
