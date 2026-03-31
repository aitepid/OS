# qemu-visual-test.ps1 -- Launch HicOS in QEMU with graphical display
#
# Opens a QEMU window showing VGA output + optional serial log.
# The VM stays open for interactive testing until manually closed.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\qemu-visual-test.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\qemu-visual-test.ps1 -Uefi
#   powershell -ExecutionPolicy Bypass -File .\scripts\qemu-visual-test.ps1 -Memory 256

param(
    [int]$Memory = 128,
    [switch]$Uefi,
    [switch]$NoNet,
    [switch]$NoDisk
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

# --- Resolve QEMU ---
$qemu = $null
$searchPaths = @(
    'C:\msys64\ucrt64\bin\qemu-system-x86_64.exe',
    'C:\msys64\usr\bin\qemu-system-x86_64.exe',
    'C:\Program Files\qemu\qemu-system-x86_64.exe',
    'C:\Program Files (x86)\qemu\qemu-system-x86_64.exe',
    "$env:USERPROFILE\scoop\apps\qemu\current\qemu-system-x86_64.exe",
    'C:\ProgramData\chocolatey\bin\qemu-system-x86_64.exe'
)
$qemuCmd = Get-Command 'qemu-system-x86_64' -ErrorAction SilentlyContinue
if ($qemuCmd) { $qemu = $qemuCmd.Source }
if (-not $qemu -or -not (Test-Path $qemu)) {
    foreach ($p in $searchPaths) {
        if (Test-Path $p) { $qemu = $p; break }
    }
}
if (-not $qemu) {
    Write-Host 'ERROR: QEMU not found.' -ForegroundColor Red
    Write-Host 'Search paths:' -ForegroundColor Yellow
    foreach ($p in $searchPaths) { Write-Host "  $p" }
    Write-Host 'Install QEMU or add it to PATH.' -ForegroundColor Yellow
    exit 2
}

# --- Select image ---
if ($Uefi) {
    $imgFile = 'hicos-uefi.img'
} else {
    $imgFile = 'hicos-hl.img'
}
if (-not (Test-Path $imgFile)) {
    Write-Host "ERROR: $imgFile not found." -ForegroundColor Red
    exit 1
}
$imgSize = (Get-Item $imgFile).Length
$imgSectors = [math]::Ceiling($imgSize / 512)

# --- Prepare serial log ---
$logFile = Join-Path $repoRoot 'qemu-visual-serial.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# --- Create test disk if needed ---
$diskFile = Join-Path $repoRoot 'hicos-disk.img'
if (-not (Test-Path $diskFile) -and -not $NoDisk) {
    Write-Host "  Creating test disk (32 MB)..." -ForegroundColor Gray
    $stream = [System.IO.File]::Create($diskFile)
    $stream.SetLength(32MB)
    $stream.Close()
}

# --- Build QEMU arguments ---
$qemuArgs = [System.Collections.ArrayList]::new()

if ($Uefi) {
    # UEFI: boot from GPT disk image directly
    $ovmfCode = $null
    $ovmfPaths = @(
        'C:\msys64\ucrt64\share\qemu\edk2-x86_64-code.fd',
        'C:\msys64\ucrt64\share\edk2\ovmf\OVMF_CODE.fd',
        'C:\Program Files\qemu\share\edk2-x86_64-code.fd'
    )
    foreach ($op in $ovmfPaths) {
        if (Test-Path $op) { $ovmfCode = $op; break }
    }
    if ($ovmfCode) {
        [void]$qemuArgs.AddRange(@('-bios', $ovmfCode))
    } else {
        Write-Host "  WARNING: OVMF firmware not found, UEFI boot may fail." -ForegroundColor Yellow
    }
    [void]$qemuArgs.AddRange(@('-drive', "format=raw,file=$imgFile"))
} else {
    # BIOS: boot from raw MBR image
    [void]$qemuArgs.AddRange(@('-drive', "format=raw,file=$imgFile"))
}

# Memory
[void]$qemuArgs.AddRange(@('-m', "$Memory"))

# Serial output to both file and stdio
[void]$qemuArgs.AddRange(@('-serial', "file:$logFile"))

# VGA display (SDL window)
[void]$qemuArgs.AddRange(@('-display', 'sdl'))
[void]$qemuArgs.AddRange(@('-vga', 'std'))

# VirtIO disk for installation testing
if (-not $NoDisk -and (Test-Path $diskFile)) {
    [void]$qemuArgs.AddRange(@(
        '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
        '-drive', "id=disk0,file=$diskFile,format=raw,if=none"
    ))
}

# Network
if (-not $NoNet) {
    [void]$qemuArgs.AddRange(@(
        '-netdev', 'user,id=net0',
        '-device', 'virtio-net-pci,netdev=net0,disable-modern=on'
    ))
}

# Safety
[void]$qemuArgs.AddRange(@('-no-reboot', '-no-shutdown'))

# --- Display info ---
Write-Host ""
Write-Host "=== HicOS Visual QEMU Test ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Image:   $imgFile ($imgSize bytes, $imgSectors sectors)" -ForegroundColor White
Write-Host "  Memory:  ${Memory} MB" -ForegroundColor White
Write-Host "  Display: SDL (graphical window)" -ForegroundColor White
Write-Host "  Serial:  $logFile" -ForegroundColor White
Write-Host "  QEMU:    $qemu" -ForegroundColor Gray
Write-Host "  Mode:    $(if ($Uefi) { 'UEFI' } else { 'BIOS (MBR)' })" -ForegroundColor White
if (-not $NoDisk) { Write-Host "  Disk:    $diskFile (32 MB VirtIO)" -ForegroundColor White }
if (-not $NoNet) { Write-Host "  Net:     VirtIO-net (user mode)" -ForegroundColor White }
Write-Host ""
Write-Host "  The QEMU window will open now." -ForegroundColor Yellow
Write-Host "  Close the window or press Ctrl+C to stop." -ForegroundColor Yellow
Write-Host ""

# --- Launch QEMU ---
$argsStr = $qemuArgs -join ' '
Write-Host "  CMD: qemu-system-x86_64 $argsStr" -ForegroundColor DarkGray
Write-Host ""

try {
    $proc = Start-Process -FilePath $qemu -ArgumentList $qemuArgs.ToArray() -PassThru
    Write-Host "  QEMU started (PID: $($proc.Id))" -ForegroundColor Green
    Write-Host "  Waiting for QEMU to exit..." -ForegroundColor Gray
    $proc.WaitForExit()
    Write-Host ""
    Write-Host "  QEMU exited (code: $($proc.ExitCode))" -ForegroundColor $(if ($proc.ExitCode -eq 0) { 'Green' } else { 'Yellow' })
} catch {
    Write-Host "  ERROR: Failed to start QEMU: $_" -ForegroundColor Red
    exit 1
}

# --- Show serial log summary ---
if (Test-Path $logFile) {
    $content = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
    if ($content) {
        $lineCount = ($content -split "`n").Count
        Write-Host ""
        Write-Host "=== Serial Output ($lineCount lines) ===" -ForegroundColor Cyan
        $lines = $content -split "`n" | Select-Object -First 40
        foreach ($line in $lines) {
            $trimmed = $line.TrimEnd()
            if ($trimmed -match 'error|fail|panic' ) {
                Write-Host "  $trimmed" -ForegroundColor Red
            } elseif ($trimmed -match 'ok|pass|init|ready') {
                Write-Host "  $trimmed" -ForegroundColor Green
            } else {
                Write-Host "  $trimmed"
            }
        }
        if ($lineCount -gt 40) {
            Write-Host "  ... ($($lineCount - 40) more lines, see $logFile)" -ForegroundColor Gray
        }
    } else {
        Write-Host ""
        Write-Host "  No serial output captured." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green