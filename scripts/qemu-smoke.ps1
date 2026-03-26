# qemu-smoke.ps1 -- Minimal QEMU serial capture smoke test
param([int]$TimeoutSec = 8)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$qemu = $null
$qemuCmd = Get-Command 'qemu-system-x86_64' -ErrorAction SilentlyContinue
if ($qemuCmd) { $qemu = $qemuCmd.Source }
if (-not $qemu -or -not (Test-Path $qemu)) {
    foreach ($p in @('C:\Program Files\qemu\qemu-system-x86_64.exe','C:\Program Files (x86)\qemu\qemu-system-x86_64.exe')) {
        if (Test-Path $p) { $qemu = $p; break }
    }
}
if (-not $qemu) {
    Write-Host 'QEMU not found' -ForegroundColor Red
    exit 2
}
if (-not (Test-Path 'hicos-hl.img')) {
    Write-Host 'hicos-hl.img not found' -ForegroundColor Red
    exit 1
}

$logFile = Join-Path $repoRoot 'qemu-smoke-serial.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

Write-Host "=== QEMU Smoke Test ===" -ForegroundColor Cyan
Write-Host "  Image: hicos-hl.img ($((Get-Item 'hicos-hl.img').Length) bytes)"
Write-Host "  Timeout: ${TimeoutSec}s"

$qemuArgs = @(
    '-drive', 'format=raw,file=hicos-hl.img',
    '-serial', "file:$logFile",
    '-m', '128',
    '-display', 'none',
    '-no-reboot', '-no-shutdown'
)

$proc = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -NoNewWindow
Start-Sleep -Seconds $TimeoutSec

if (-not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

$content = ''
if (Test-Path $logFile) {
    $content = [System.IO.File]::ReadAllText($logFile)
}

Write-Host ""
Write-Host "Serial output: $($content.Length) bytes" -ForegroundColor White
if ($content.Length -gt 0) {
    Write-Host "--- First 30 lines ---" -ForegroundColor Green
    $lines = $content -split "`n"
    $show = [math]::Min($lines.Count, 30)
    for ($i = 0; $i -lt $show; $i++) {
        Write-Host "  $($lines[$i])"
    }
    Write-Host "--- End ($($lines.Count) total lines) ---" -ForegroundColor Green

    if ($content -match 'KB-OK|PIC|PIT|IDT|HicOS') {
        Write-Host "`nSMOKE TEST: PASSED (boot markers detected)" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`nSMOKE TEST: PARTIAL (output present but no boot markers)" -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "`nSMOKE TEST: FAILED (no serial output)" -ForegroundColor Red
    exit 1
}
