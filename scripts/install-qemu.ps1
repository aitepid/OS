$ErrorActionPreference = 'Continue'

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

function Print-ManualHelp {
    Write-Host ''
    Write-Host 'Manual fix steps:' -ForegroundColor Yellow
    Write-Host '1) Install QEMU from official Windows build (or winget/choco/scoop).' -ForegroundColor Yellow
    Write-Host '2) Ensure qemu-system-x86_64.exe exists, e.g. C:\Program Files\qemu\qemu-system-x86_64.exe' -ForegroundColor Yellow
    Write-Host '3) Set environment variable (current session):' -ForegroundColor Yellow
    Write-Host '   $env:QEMU_HOME="C:\Program Files\qemu"' -ForegroundColor Yellow
    Write-Host '4) Re-run:' -ForegroundColor Yellow
    Write-Host '   powershell -ExecutionPolicy Bypass -File .\scripts\boot-and-run.ps1 -NoDisplay' -ForegroundColor Yellow
}

$qemuPath = Resolve-Qemu
if ($qemuPath) {
    Write-Host "QEMU already available: $qemuPath" -ForegroundColor Green
    exit 0
}

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    Write-Host 'winget not found. Please install QEMU manually.' -ForegroundColor Red
    Print-ManualHelp
    exit 1
}

Write-Host 'Resetting winget sources...' -ForegroundColor Cyan
winget source reset --force | Out-Null

$packageIds = @('QEMU.QEMU','SoftwareFreedomConservancy.QEMU')

foreach ($pkg in $packageIds) {
    Write-Host "Trying winget package: $pkg (user scope)..." -ForegroundColor Cyan
    winget install -e --id $pkg --scope user -h --accept-package-agreements --accept-source-agreements
    $qemuPath = Resolve-Qemu
    if ($qemuPath) {
        Write-Host "QEMU install success: $qemuPath" -ForegroundColor Green
        exit 0
    }

    Write-Host "Trying winget package: $pkg (default scope)..." -ForegroundColor Cyan
    winget install -e --id $pkg -h --accept-package-agreements --accept-source-agreements
    $qemuPath = Resolve-Qemu
    if ($qemuPath) {
        Write-Host "QEMU install success: $qemuPath" -ForegroundColor Green
        exit 0
    }
}

Write-Host 'QEMU installation could not be confirmed automatically.' -ForegroundColor Red
Print-ManualHelp
exit 1
