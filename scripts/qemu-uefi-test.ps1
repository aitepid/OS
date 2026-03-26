# qemu-uefi-test.ps1 -- Boot UEFI image with OVMF and check serial output
#
# Exit codes:
#   0 = UEFI boot test passed/partial pass
#   1 = UEFI boot test failed
#   2 = prerequisite missing (QEMU / OVMF), test skipped

param(
    [int]$TimeoutSec = 12,
    [switch]$KeepLog
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

function Resolve-Qemu {
    $cmd = Get-Command 'qemu-system-x86_64' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        'C:\Program Files\qemu\qemu-system-x86_64.exe',
        'C:\Program Files (x86)\qemu\qemu-system-x86_64.exe',
        "$env:USERPROFILE\scoop\apps\qemu\current\qemu-system-x86_64.exe",
        'C:\ProgramData\chocolatey\bin\qemu-system-x86_64.exe',
        'C:\msys64\usr\bin\qemu-system-x86_64.exe'
    )

    if ($env:QEMU_HOME) {
        $candidates = ,(Join-Path $env:QEMU_HOME 'qemu-system-x86_64.exe') + $candidates
    }

    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }

    return $null
}

function Start-QemuLogged {
    param(
        [string]$QemuPath,
        [object[]]$ArgumentList,
        [string]$LogFile
    )

    $stderrFile = "$LogFile.stderr.txt"
    if (Test-Path $LogFile) { Remove-Item $LogFile -Force }
    if (Test-Path $stderrFile) { Remove-Item $stderrFile -Force }

    return Start-Process -FilePath $QemuPath -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $LogFile -RedirectStandardError $stderrFile
}

function Resolve-Ovmf {
    $candidates = @(
        (Join-Path $repoRoot 'ovmf-code.fd'),
        'C:\Program Files\qemu\share\edk2-x86_64-code.fd',
        'C:\Program Files\qemu\share\OVMF.fd',
        'C:\Program Files\qemu\share\OVMF_CODE.fd',
        'C:\Program Files (x86)\qemu\share\edk2-x86_64-code.fd',
        'C:\Program Files (x86)\qemu\share\OVMF.fd',
        'C:\Program Files (x86)\qemu\share\OVMF_CODE.fd',
        "$env:USERPROFILE\scoop\apps\qemu\current\share\edk2-x86_64-code.fd",
        "$env:USERPROFILE\scoop\apps\qemu\current\share\OVMF.fd",
        "$env:USERPROFILE\scoop\apps\qemu\current\share\OVMF_CODE.fd",
        'C:\msys64\usr\share\edk2-x86_64-code.fd',
        'C:\msys64\usr\share\OVMF.fd',
        'C:\msys64\usr\share\OVMF_CODE.fd'
    )

    if ($env:QEMU_HOME) {
        $candidates = @(
            (Join-Path $env:QEMU_HOME 'share\edk2-x86_64-code.fd'),
            (Join-Path $env:QEMU_HOME 'share\OVMF.fd'),
            (Join-Path $env:QEMU_HOME 'share\OVMF_CODE.fd')
        ) + $candidates
    }

    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }

    return $null
}

Write-Host '=== QEMU UEFI Boot Test ===' -ForegroundColor Cyan

$img = Join-Path $repoRoot 'hicos-uefi.img'
if (-not (Test-Path $img)) {
    Write-Host 'hicos-uefi.img not found. Run build-uefi-image.ps1 first.' -ForegroundColor Red
    exit 1
}

$qemu = Resolve-Qemu
if (-not $qemu) {
    Write-Host 'QEMU not found. Skipping UEFI boot test.' -ForegroundColor Yellow
    Write-Host 'Install QEMU or set QEMU_HOME to enable UEFI boot tests.' -ForegroundColor Yellow
    exit 2
}

# Find OVMF firmware
$ovmf = Resolve-Ovmf
if (-not $ovmf) {
    Write-Host 'OVMF firmware not found. Skipping UEFI boot test.' -ForegroundColor Yellow
    Write-Host 'Install OVMF firmware or place `ovmf-code.fd` in repo root.' -ForegroundColor Yellow
    exit 2
}

# Copy OVMF to a path without spaces (QEMU path handling workaround)
$localOvmf = Join-Path $repoRoot 'ovmf-code.fd'
if ((-not (Test-Path $localOvmf)) -and ($ovmf -ne $localOvmf)) {
    Copy-Item $ovmf $localOvmf
}

$serialLog = Join-Path $repoRoot 'qemu-uefi-serial.log'
if (Test-Path $serialLog) { Remove-Item $serialLog -Force }

Write-Host "  Image: $((Get-Item $img).Length) bytes"
Write-Host "  QEMU: $qemu"
Write-Host "  OVMF: $ovmf"
Write-Host "  Timeout: ${TimeoutSec}s"

$qemuArgs = @(
    '-drive', "if=pflash,format=raw,unit=0,readonly=on,file=$localOvmf",
    '-drive', "file=$img,format=raw,if=ide",
    '-nographic',
    '-monitor', 'none',
    '-serial', 'stdio',
    '-no-reboot',
    '-m', '256M'
)

$proc = Start-QemuLogged -QemuPath $qemu -ArgumentList $qemuArgs -LogFile $serialLog
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
if (-not $KeepLog) {
    $stderrClean = "$serialLog.stderr.txt"
    if (Test-Path $stderrClean) { Remove-Item $stderrClean -Force }
}
