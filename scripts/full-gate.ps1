param(
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
    @{ Name = 'Robustness lint (R1/R2/R4/R5)'; Cmd = 'powershell -ExecutionPolicy Bypass -File .\scripts\lint-robustness.ps1' },
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

$failed = @()
$skipped = @()
$skipReasons = @{}

if ($SkipQemu) {
    $checks = @($checks | Where-Object { $qemuCheckNames -notcontains $_.Name })
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
$allNames = @($checks | ForEach-Object { $_.Name })
foreach ($s in $skipped) { if ($allNames -notcontains $s) { $allNames += $s } }
foreach ($n in $allNames) {
    if ($skipped -contains $n) {
        Write-Host "- ${n}: SKIPPED ($($skipReasons[$n]))" -ForegroundColor Yellow
    } else {
        Write-Host "- ${n}: OK"
    }
}
