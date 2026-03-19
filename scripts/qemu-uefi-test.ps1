# qemu-uefi-test.ps1 -- Boot UEFI image with OVMF and check serial output

param(
    [int]$TimeoutSec = 12,
    [switch]$KeepLog
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

Write-Host '=== QEMU UEFI Boot Test ===' -ForegroundColor Cyan

$img = Join-Path $repoRoot 'hicos-uefi.img'
if (-not (Test-Path $img)) {
    Write-Host 'hicos-uefi.img not found. Run build-uefi-image.ps1 first.' -ForegroundColor Red
    exit 1
}

$qemu = 'C:\Program Files\qemu\qemu-system-x86_64.exe'
if (-not (Test-Path $qemu)) {
    Write-Host 'QEMU not found' -ForegroundColor Red
    exit 1
}

# Find OVMF firmware
$ovmfPaths = @(
    'C:\Program Files\qemu\share\edk2-x86_64-code.fd',
    'C:\Program Files\qemu\share\OVMF.fd',
    'C:\Program Files\qemu\share\OVMF_CODE.fd'
)
$ovmf = $null
foreach ($p in $ovmfPaths) {
    if (Test-Path $p) { $ovmf = $p; break }
}
if (-not $ovmf) {
    Write-Host 'OVMF firmware not found' -ForegroundColor Red
    exit 1
}

# Copy OVMF to a path without spaces (QEMU path handling workaround)
$localOvmf = Join-Path $repoRoot 'ovmf-code.fd'
if (-not (Test-Path $localOvmf)) {
    Copy-Item $ovmf $localOvmf
}

$serialLog = Join-Path $repoRoot 'qemu-uefi-serial.log'
if (Test-Path $serialLog) { Remove-Item $serialLog -Force }

Write-Host "  Image: $((Get-Item $img).Length) bytes"
Write-Host "  OVMF: $ovmf"
Write-Host "  Timeout: ${TimeoutSec}s"

$qemuArgs = @(
    '-drive', "if=pflash,format=raw,unit=0,readonly=on,file=$localOvmf",
    '-drive', "file=$img,format=raw,if=ide",
    '-display', 'none',
    '-serial', "file:$serialLog",
    '-no-reboot',
    '-m', '256M'
)

$proc = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -NoNewWindow
Write-Host "`nWaiting for serial output..."
Start-Sleep -Seconds $TimeoutSec

if (-not $proc.HasExited) {
    Write-Host 'Stopping QEMU (timeout)...'
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

$serialContent = ''
if (Test-Path $serialLog) {
    $serialContent = Get-Content $serialLog -Raw -ErrorAction SilentlyContinue
}

Write-Host "`n--- Serial Output ---" -ForegroundColor Yellow
if ($serialContent) {
    $serialContent.Split("`n") | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host '  (no output)' -ForegroundColor DarkGray
}
Write-Host '--- End ---' -ForegroundColor Yellow

# Check results
$passes = @()
if ($serialContent -match 'HicOS') {
    $passes += 'HicOS string detected in UEFI serial output'
}
if ($serialContent -match 'UEFI') {
    $passes += 'UEFI keyword in output'
}
if ($serialContent -match 'OK') {
    $passes += 'OK status in output'
}

Write-Host "`n=== UEFI Boot Test Results ===" -ForegroundColor Cyan
foreach ($p in $passes) {
    Write-Host "  PASS: $p" -ForegroundColor Green
}

$total = $passes.Count
if ($total -ge 3) {
    Write-Host "`nUEFI BOOT TEST: PASSED ($total checks)" -ForegroundColor Green
} elseif ($total -gt 0) {
    Write-Host "`nUEFI BOOT TEST: PARTIAL ($total/3 checks)" -ForegroundColor Yellow
} else {
    Write-Host "`nUEFI BOOT TEST: FAILED (no output)" -ForegroundColor Red
    exit 1
}

if (-not $KeepLog -and (Test-Path $serialLog)) {
    Remove-Item $serialLog -Force
}
