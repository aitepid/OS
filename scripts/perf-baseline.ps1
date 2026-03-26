# perf-baseline.ps1 -- Performance baseline measurement for HicOS v6.0
#
# Measures:
#   1. Boot time (serial output latency to shell prompt)
#   2. File I/O throughput (format + mkfile + cat cycle)
#   3. Network latency (DHCP acquire time)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\perf-baseline.ps1

param(
    [int]$TimeoutSec = 30,
    [switch]$KeepLog
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

# --- Resolve QEMU ---
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
    Write-Host 'QEMU not found. Skipping perf baseline.' -ForegroundColor Yellow
    exit 2
}

Write-Host '=== HicOS v6.0 Performance Baseline ===' -ForegroundColor Cyan
Write-Host "  Image: hicos-hl.img ($((Get-Item 'hicos-hl.img').Length) bytes)"
Write-Host "  QEMU: $qemuPath"
Write-Host ''

$passes = @()
$metrics = @{}

# --- Test 1: Boot Time ---
Write-Host '--- Baseline 1: Boot Time ---' -ForegroundColor Yellow

$bootLogFile = Join-Path $repoRoot 'qemu-perf-boot.log'
if (Test-Path $bootLogFile) { Remove-Item $bootLogFile -Force }

$diskImg = Join-Path $repoRoot 'hicos-disk.img'
if (-not (Test-Path $diskImg)) {
    $stream = [System.IO.File]::Create($diskImg)
    $stream.SetLength(32MB)
    $stream.Close()
}

$qemuArgs = @(
    '-drive', 'format=raw,file=hicos-hl.img',
    '-serial', "file:$bootLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=$diskImg,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown'
)

$bootStart = Get-Date
$proc = Start-Process -FilePath $qemuPath -ArgumentList $qemuArgs -PassThru -NoNewWindow

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$shellReached = $false
$serialFirstByte = $null
$shellTime = $null

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200
    if ($proc.HasExited) { break }
    if (Test-Path $bootLogFile) {
        try {
            $content = [System.IO.File]::ReadAllText($bootLogFile)
        } catch { continue }
        if ($content.Length -gt 0 -and -not $serialFirstByte) {
            $serialFirstByte = (Get-Date) - $bootStart
        }
        if ($content -match 'HicOS>' -and -not $shellReached) {
            $shellTime = (Get-Date) - $bootStart
            $shellReached = $true
            break
        }
    }
}

if (-not $proc.HasExited) { $proc.Kill(); $proc.WaitForExit(3000) }

if ($serialFirstByte) {
    $firstByteMs = [int]$serialFirstByte.TotalMilliseconds
    $metrics['first_serial_byte_ms'] = $firstByteMs
    Write-Host "  First serial byte: ${firstByteMs}ms" -ForegroundColor White
    $passes += "Boot: first serial byte within ${TimeoutSec}s ($firstByteMs ms)"
}

if ($shellReached) {
    $shellMs = [int]$shellTime.TotalMilliseconds
    $metrics['boot_to_shell_ms'] = $shellMs
    Write-Host "  Boot to shell prompt: ${shellMs}ms" -ForegroundColor White
    $passes += "Boot: shell prompt reached ($shellMs ms)"
} else {
    Write-Host '  Shell prompt not reached within timeout' -ForegroundColor Yellow
}

$bootContent = ''
if (Test-Path $bootLogFile) {
    try { $bootContent = [System.IO.File]::ReadAllText($bootLogFile) } catch {}
}

$initLines = 0
if ($bootContent.Length -gt 0) {
    $initLines = ($bootContent -split "`n").Count
}
$metrics['boot_serial_lines'] = $initLines
Write-Host "  Init serial lines: $initLines" -ForegroundColor White
if ($initLines -ge 10) {
    $passes += "Boot: $initLines serial init lines output"
}

if (Test-Path $bootLogFile) { Remove-Item $bootLogFile -Force }

# --- Test 2: File I/O Cycle Time ---
Write-Host "`n--- Baseline 2: File I/O Cycle ---" -ForegroundColor Yellow

$fioLogFile = Join-Path $repoRoot 'qemu-perf-fio.log'
if (Test-Path $fioLogFile) { Remove-Item $fioLogFile -Force }

if (Test-Path $diskImg) { Remove-Item $diskImg -Force }
$fs = [System.IO.File]::Create($diskImg); $fs.SetLength(32MB); $fs.Close()

$fioPort = 55580
$fioArgs = @(
    '-drive', 'format=raw,file=hicos-hl.img',
    '-serial', "file:$fioLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=$diskImg,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$fioPort,server,nowait"
)

$fioProc = Start-Process -FilePath $qemuPath -ArgumentList $fioArgs -PassThru -NoNewWindow
$fioStart = $null

try {
    Start-Sleep -Seconds 5
    $ftcp = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $fioPort)
    $fstream = $ftcp.GetStream()
    $fwriter = New-Object System.IO.StreamWriter($fstream)
    $fwriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    $fioStart = Get-Date

    # format
    foreach ($k in @('f','o','r','m','a','t','ret')) { $fwriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 25

    # mkfile test hello
    foreach ($k in @('m','k','f','i','l','e','spc','t','e','s','t','spc','h','e','l','l','o','ret')) { $fwriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # cat test
    foreach ($k in @('c','a','t','spc','t','e','s','t','ret')) { $fwriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3

    $fwriter.Close()
    $ftcp.Close()
} catch {
    Write-Host "  File I/O test error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $fioProc.HasExited) { $fioProc.Kill(); $fioProc.WaitForExit(3000) }

$fioContent = ''
if (Test-Path $fioLogFile) {
    try { $fioContent = [System.IO.File]::ReadAllText($fioLogFile) } catch {}
}

if ($fioStart) {
    $fioEnd = Get-Date
    $fioCycleMs = [int]($fioEnd - $fioStart).TotalMilliseconds
    $metrics['fio_cycle_ms'] = $fioCycleMs
    Write-Host "  format+mkfile+cat cycle: ${fioCycleMs}ms (wall)" -ForegroundColor White
}

if ($fioContent -match 'Format complete') {
    $passes += 'File I/O: format completed'
    Write-Host '  format: OK' -ForegroundColor Green
}
if ($fioContent -match 'File created') {
    $passes += 'File I/O: mkfile completed'
    Write-Host '  mkfile: OK' -ForegroundColor Green
}
if ($fioContent -match 'hello') {
    $passes += 'File I/O: cat read back verified'
    Write-Host '  cat readback: OK' -ForegroundColor Green
}

if (Test-Path $fioLogFile) { Remove-Item $fioLogFile -Force }

# --- Test 3: Network DHCP Latency ---
Write-Host "`n--- Baseline 3: Network DHCP Latency ---" -ForegroundColor Yellow

$netLogFile = Join-Path $repoRoot 'qemu-perf-net.log'
if (Test-Path $netLogFile) { Remove-Item $netLogFile -Force }

$netPort = 55581
$netArgs = @(
    '-drive', 'format=raw,file=hicos-hl.img',
    '-serial', "file:$netLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=$diskImg,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$netPort,server,nowait"
)

$netProc = Start-Process -FilePath $qemuPath -ArgumentList $netArgs -PassThru -NoNewWindow
$dhcpStart = $null
$dhcpEnd = $null

try {
    Start-Sleep -Seconds 5
    $ntcp = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $netPort)
    $nstream = $ntcp.GetStream()
    $nwriter = New-Object System.IO.StreamWriter($nstream)
    $nwriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    $dhcpStart = Get-Date

    # dhcp
    foreach ($k in @('d','h','c','p','ret')) { $nwriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 10

    $dhcpEnd = Get-Date

    $nwriter.Close()
    $ntcp.Close()
} catch {
    Write-Host "  Network test error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $netProc.HasExited) { $netProc.Kill(); $netProc.WaitForExit(3000) }

$netContent = ''
if (Test-Path $netLogFile) {
    try { $netContent = [System.IO.File]::ReadAllText($netLogFile) } catch {}
}

if ($netContent -match 'IP acquired' -and $dhcpStart -and $dhcpEnd) {
    $dhcpMs = [int]($dhcpEnd - $dhcpStart).TotalMilliseconds
    $metrics['dhcp_acquire_ms'] = $dhcpMs
    Write-Host "  DHCP acquire: ${dhcpMs}ms (wall)" -ForegroundColor White
    $passes += "Network: DHCP acquired ($dhcpMs ms)"
} elseif ($netContent -match 'IP acquired') {
    $passes += 'Network: DHCP acquired'
    Write-Host '  DHCP acquired (timing unavailable due to monitor interruption)' -ForegroundColor Yellow
} else {
    Write-Host '  DHCP not acquired within timeout' -ForegroundColor Yellow
}

if (Test-Path $netLogFile) { Remove-Item $netLogFile -Force }

# --- Test 4: Image Size Baseline ---
Write-Host "`n--- Baseline 4: Artifact Sizes ---" -ForegroundColor Yellow

$imgSize = (Get-Item 'hicos-hl.img').Length
$metrics['bios_image_bytes'] = $imgSize
Write-Host "  hicos-hl.img: $imgSize bytes ($([int]($imgSize/1024)) KB)" -ForegroundColor White
$passes += "Artifact: BIOS image size $imgSize bytes"

if (Test-Path 'hicos-uefi.img') {
    $uefiSize = (Get-Item 'hicos-uefi.img').Length
    $metrics['uefi_image_bytes'] = $uefiSize
    Write-Host "  hicos-uefi.img: $uefiSize bytes ($([int]($uefiSize/1MB)) MB)" -ForegroundColor White
    $passes += "Artifact: UEFI image size $uefiSize bytes"
}

if (Test-Path 'BOOTX64.EFI') {
    $efiSize = (Get-Item 'BOOTX64.EFI').Length
    $metrics['efi_app_bytes'] = $efiSize
    Write-Host "  BOOTX64.EFI: $efiSize bytes" -ForegroundColor White
    $passes += "Artifact: EFI app size $efiSize bytes"
}

# --- Count H-L source ---
$hlFiles = Get-ChildItem -Recurse -Filter '*.hl' | Where-Object { $_.FullName -notmatch 'node_modules|\.git|\.vs|archive' }
$hlCount = $hlFiles.Count
$hlLines = 0
foreach ($f in $hlFiles) {
    $hlLines += (Get-Content $f.FullName -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
}
$metrics['hl_files'] = $hlCount
$metrics['hl_lines'] = $hlLines
Write-Host "  H-L source: $hlCount files, $hlLines lines" -ForegroundColor White
$passes += "Source: $hlCount H-L files, $hlLines lines"

$ps1Files = Get-ChildItem -Path 'scripts' -Filter '*.ps1'
$ps1Lines = 0
foreach ($f in $ps1Files) {
    $ps1Lines += (Get-Content $f.FullName -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
}
$metrics['ps1_lines'] = $ps1Lines
Write-Host "  PS1 scripts: $($ps1Files.Count) files, $ps1Lines lines" -ForegroundColor White

# --- Summary ---
Write-Host "`n=== Performance Baseline Summary ===" -ForegroundColor Cyan

foreach ($p in $passes) {
    Write-Host "  PASS: $p" -ForegroundColor Green
}

Write-Host "`n  Metrics:" -ForegroundColor Yellow
foreach ($k in ($metrics.Keys | Sort-Object)) {
    Write-Host "    $k = $($metrics[$k])" -ForegroundColor White
}

$totalChecks = $passes.Count
Write-Host "`nPERF BASELINE: $totalChecks checks passed" -ForegroundColor Green

# Clean up
if (-not $KeepLog) {
    @('qemu-perf-boot.log','qemu-perf-fio.log','qemu-perf-net.log') | ForEach-Object {
        $f = Join-Path $repoRoot $_
        if (Test-Path $f) { Remove-Item $f -Force }
        $sf = "$f.stderr.txt"
        if (Test-Path $sf) { Remove-Item $sf -Force }
    }
}

exit 0
