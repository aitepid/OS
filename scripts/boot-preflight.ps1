param(
    [switch]$Strict,
    [switch]$SkipFullGate
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$errors = @()
$warnings = @()

function Check-Command {
    param([string]$Name)
    if (Test-Path (".\\" + $Name)) { return $true }
    if (Test-Path (".\\" + $Name + '.cmd')) { return $true }
    if (Test-Path (".\\" + $Name + '.ps1')) { return $true }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

if (-not (Test-Path 'hicos-hl.img')) {
    $errors += 'Missing hicos-hl.img'
}

function Resolve-Qemu {
    $cmd = Get-Command 'qemu-system-x86_64' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        'C:\Program Files\qemu\qemu-system-x86_64.exe',
        'C:\Program Files (x86)\qemu\qemu-system-x86_64.exe'
    )

    if ($env:QEMU_HOME) {
        $candidates = ,(Join-Path $env:QEMU_HOME 'qemu-system-x86_64.exe') + $candidates
    }

    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }

    return $null
}

$qemuPath = Resolve-Qemu
if (-not $qemuPath) {
    $warnings += 'qemu-system-x86_64 not found (PATH/common locations).'
}

$hasHlBootstrapCmd = Check-Command 'hl-bootstrap'
$hasHlBootstrapSource = Test-Path 'hl-bootstrap.hl'

if (-not $hasHlBootstrapCmd -and -not $hasHlBootstrapSource) {
    $warnings += 'hl-bootstrap not found in PATH and hl-bootstrap.hl is missing'
}
if (-not $hasHlBootstrapCmd -and $hasHlBootstrapSource) {
    $warnings += 'hl-bootstrap command not found; only source file hl-bootstrap.hl exists'
}

if (-not $SkipFullGate) {
    powershell -ExecutionPolicy Bypass -File '.\scripts\full-gate.ps1'
    if ($LASTEXITCODE -ne 0) {
        $errors += 'full-gate failed'
    }
}

if ($Strict -and $warnings.Count -gt 0) {
    foreach ($w in $warnings) { $errors += $w }
}

if ($errors.Count -gt 0) {
    Write-Host 'Boot preflight failed:' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
    exit 1
}

if ($warnings.Count -gt 0) {
    Write-Host 'Boot preflight warnings:' -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "- $_" -ForegroundColor Yellow }
}

Write-Host 'Boot preflight passed.' -ForegroundColor Green
Write-Host '- image: OK'
Write-Host '- gate: OK'
if ($qemuPath) {
    Write-Host ("- qemu: OK (" + $qemuPath + ")")
}
Write-Host '- recommended boot command:'
Write-Host '  qemu-system-x86_64 -drive format=raw,file=hicos-hl.img -serial stdio -display none'
