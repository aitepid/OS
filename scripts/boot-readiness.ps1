$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$errors = @()

$required = @(
    'bare-kernel/hl/stage1.hl',
    'bare-kernel/hl/stage2.hl',
    'bare-kernel/hl/kernel_entry.hl',
    'bare-kernel/hl/kernel_init.hl',
    'bare-kernel/hl/shell.hl',
    'bare-kernel/hl/build.hl',
    'hicos-hl.img'
)

foreach ($f in $required) {
    if (-not (Test-Path $f)) {
        $errors += "Missing required boot file: $f"
    }
}

if (Test-Path 'hicos-hl.img') {
    $img = Get-Item 'hicos-hl.img'
    if ($img.Length -lt 512) {
        $errors += 'Boot image size is too small (<512 bytes).'
    }
}

$kernelInit = Get-Content 'bare-kernel/hl/kernel_init.hl' -Raw
$mustCalls = @(
    'serial_init(',
    'kmalloc_init(',
    'vfs_init(',
    'pci_scan(',
    'tss_init(',
    'smp_init(',
    'shell_main('
)

foreach ($c in $mustCalls) {
    if ($kernelInit -notmatch [regex]::Escape($c)) {
        $errors += "kernel_init missing call: $c"
    }
}

$build = Get-Content 'bare-kernel/hl/build.hl' -Raw
$mustBuildRefs = @(
    'bare-kernel/hl/stage1.hl',
    'bare-kernel/hl/stage2.hl',
    'bare-kernel/hl/kernel_entry.hl',
    'bare-kernel/hl/kernel_init.hl',
    'bare-kernel/hl/shell.hl'
)

foreach ($r in $mustBuildRefs) {
    if ($build -notmatch [regex]::Escape($r)) {
        $errors += "build.hl missing reference: $r"
    }
}

if ($errors.Count -gt 0) {
    Write-Host 'Boot readiness check failed:' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'Boot readiness check passed.' -ForegroundColor Green
Write-Host '- boot chain files: OK'
Write-Host '- kernel init critical calls: OK'
Write-Host '- build script references: OK'
Write-Host '- boot image presence/size: OK'
