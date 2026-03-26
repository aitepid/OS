param(
    [switch]$NoDisplay
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

if (-not (Test-Path 'hicos-hl.img')) {
    Write-Host 'Missing hicos-hl.img' -ForegroundColor Red
    exit 1
}

$qemuPath = Resolve-Qemu
if (-not $qemuPath) {
    Write-Host 'qemu-system-x86_64 not found (PATH/common locations).' -ForegroundColor Red
    Write-Host 'Install QEMU or set QEMU_HOME, then re-run this script.' -ForegroundColor Yellow
    exit 1
}

$qemuArgs = @(
    '-drive','format=raw,file=hicos-hl.img',
    '-serial','stdio',
    '-m','128',
    '-device','virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive','id=disk0,file=hicos-disk.img,format=raw,if=none',
    '-netdev','user,id=net0',
    '-device','virtio-net-pci,netdev=net0,disable-modern=on'
)
if ($NoDisplay) {
    $qemuArgs += @('-display','none')
}

# Create test disk if missing
if (-not (Test-Path 'hicos-disk.img')) {
    Write-Host 'Creating test disk (32 MB)...' -ForegroundColor Yellow
    $stream = [System.IO.File]::Create('hicos-disk.img')
    $stream.SetLength(32MB)
    $stream.Close()
}

Write-Host "Launching HicOS in QEMU: $qemuPath" -ForegroundColor Cyan
& $qemuPath @qemuArgs
exit $LASTEXITCODE
