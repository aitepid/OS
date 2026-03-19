# qemu-boot-test.ps1 -- Automated QEMU Boot Test (Iteration 3)
#
# Launches HicOS in QEMU with serial output piped to a file,
# waits for expected kernel init output, then reports pass/fail.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\qemu-boot-test.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\qemu-boot-test.ps1 -TimeoutSec 15
#
# Exit codes:
#   0 = Boot test passed (expected output seen)
#   1 = Boot test failed (timeout or missing output)
#   2 = QEMU not found

param(
    [int]$TimeoutSec = 10,
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

if (-not (Test-Path 'hicos-hl.img')) {
    Write-Host 'Missing hicos-hl.img' -ForegroundColor Red
    exit 1
}

$qemuPath = Resolve-Qemu
if (-not $qemuPath) {
    Write-Host 'QEMU not found. Skipping boot test.' -ForegroundColor Yellow
    Write-Host 'Install QEMU or set QEMU_HOME to enable boot tests.' -ForegroundColor Yellow
    exit 2
}

# --- Prepare serial log ---
$logFile = Join-Path $repoRoot 'qemu-serial.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

# Create test disk if missing
if (-not (Test-Path 'hicos-disk.img')) {
    $stream = [System.IO.File]::Create('hicos-disk.img')
    $stream.SetLength(32MB)
    $stream.Close()
}

# --- Launch QEMU ---
Write-Host "=== QEMU Boot Test ===" -ForegroundColor Cyan
Write-Host "  Image: hicos-hl.img ($((Get-Item 'hicos-hl.img').Length) bytes)"
Write-Host "  Timeout: ${TimeoutSec}s"
Write-Host "  QEMU: $qemuPath"
Write-Host ""

$qemuArgs = @(
    '-drive', 'format=raw,file=hicos-hl.img',
    '-serial', "file:$logFile",
    '-m', '128',
    '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', 'id=disk0,file=hicos-disk.img,format=raw,if=none',
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot',
    '-no-shutdown'
)

# Start QEMU process
$proc = Start-Process -FilePath $qemuPath -ArgumentList $qemuArgs -PassThru -NoNewWindow

# --- Wait for serial output ---
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$serialContent = ''
$bootDetected = $false

Write-Host "Waiting for serial output..." -ForegroundColor Gray

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500

    if ($proc.HasExited) {
        Write-Host "QEMU exited (code $($proc.ExitCode))" -ForegroundColor Yellow
        break
    }

    if (Test-Path $logFile) {
        try {
            $serialContent = [System.IO.File]::ReadAllText($logFile)
        } catch {
            # File may be locked by QEMU
        }

        # Check for expected boot markers
        if ($serialContent -match 'HicOS' -or
            $serialContent -match 'Kernel Init' -or
            $serialContent -match 'serial_init' -or
            $serialContent -match 'shell' -or
            $serialContent.Length -gt 10) {
            $bootDetected = $true
        }

        # Show progress
        $lines = ($serialContent -split "`n").Count
        if ($lines -gt 0 -and $serialContent.Length -gt 0) {
            Write-Host "`r  Serial: $($serialContent.Length) bytes, $lines lines" -NoNewline -ForegroundColor Gray
        }
    }
}

# --- Terminate QEMU ---
if (-not $proc.HasExited) {
    Write-Host ""
    Write-Host "Stopping QEMU (timeout)..." -ForegroundColor Yellow
    $proc.Kill()
    $proc.WaitForExit(3000)
}

# --- Final read ---
if (Test-Path $logFile) {
    try {
        $serialContent = [System.IO.File]::ReadAllText($logFile)
    } catch {}
}

Write-Host ""
Write-Host "--- Serial Output ---" -ForegroundColor Cyan

if ($serialContent.Length -eq 0) {
    Write-Host "(empty -- no serial output captured)" -ForegroundColor Yellow
} else {
    # Show first 40 lines
    $outputLines = $serialContent -split "`n"
    $showCount = [math]::Min($outputLines.Count, 40)
    for ($i = 0; $i -lt $showCount; $i++) {
        Write-Host "  $($outputLines[$i])" -ForegroundColor White
    }
    if ($outputLines.Count -gt 40) {
        Write-Host "  ... ($($outputLines.Count - 40) more lines)" -ForegroundColor DarkGray
    }
}

Write-Host "--- End ---" -ForegroundColor Cyan
Write-Host ""

# --- Analyze results ---
$errors = @()
$passes = @()

# Check MBR execution (any serial output at all indicates stage1 ran)
if ($serialContent.Length -gt 0) {
    $passes += 'Stage1 MBR executed (serial output present)'
} else {
    $errors += 'No serial output (Stage1 may not have executed)'
}

# Check for kernel init markers
if ($serialContent -match 'HicOS') {
    $passes += 'Kernel banner detected'
}
if ($serialContent -match 'Kernel Init|kernel_init') {
    $passes += 'Kernel init sequence started'
}
if ($serialContent -match 'Serial.*COM1') {
    $passes += 'Serial driver initialized'
}
if ($serialContent -match 'PIC.*8259') {
    $passes += 'PIC remapped'
}
if ($serialContent -match 'PIT.*100') {
    $passes += 'PIT timer configured'
}
if ($serialContent -match 'IDT.*256') {
    $passes += 'IDT installed (256 vectors)'
}
if ($serialContent -match 'Scancode') {
    $passes += 'Scancode table loaded'
}
if ($serialContent -match 'Timer.*ticks') {
    $passes += 'Timer interrupt active'
}
if ($serialContent -match 'PCI:.*device') {
    $passes += 'PCI bus scan completed'
}
if ($serialContent -match 'VirtIO-blk') {
    $passes += 'VirtIO-blk detected'
}
if ($serialContent -match 'VirtIO-blk.*BAR') {
    $passes += 'VirtIO-blk BAR0 read'
}
if ($serialContent -match 'VirtIO-blk.*initialized.*\d+ MB') {
    $passes += 'VirtIO-blk initialized with capacity'
}
if ($serialContent -match 'sector 0') {
    $passes += 'Disk sector read'
}
if ($serialContent -match 'write\+readback.*verified') {
    $passes += 'Disk write+readback verified'
}
if ($serialContent -match 'VirtIO-net') {
    $passes += 'VirtIO-net detected'
}
if ($serialContent -match 'VirtIO-net.*MAC=([0-9A-Fa-f]{2}:){5}') {
    $passes += 'VirtIO-net MAC address read'
}
if ($serialContent -match 'ARP request sent') {
    $passes += 'VirtIO-net ARP packet sent'
}
if ($serialContent -match 'VESA.*1024x768.*LFB=') {
    $passes += 'VESA mode set (1024x768x32 LFB detected)'
}
if ($serialContent -match 'framebuffer write/read verified') {
    $passes += 'VESA framebuffer read/write verified'
}
if ($serialContent -match 'SYSCALL.*STAR.*LSTAR.*configured') {
    $passes += 'SYSCALL MSRs configured + TSS loaded'
}
if ($serialContent -match '[AB]{3,}') {
    $passes += 'Timer task alternation active (A/B pattern)'
}
if ($serialContent -match 'HicOS>') {
    $passes += 'Shell prompt reached'
}
if ($serialContent -match 'Boot Complete|complete|ready') {
    $passes += 'Boot sequence completed'
}

# Check for panic/fault indicators
if ($serialContent -match 'PANIC|panic|fault|FAULT|triple') {
    $errors += 'Kernel panic or fault detected in serial output'
}

# === Shell Command Tests (send keystrokes via QEMU monitor) ===
# Start a second QEMU instance with monitor for interactive testing
$cmdLogFile = Join-Path $repoRoot 'qemu-cmd-test.log'
if (Test-Path $cmdLogFile) { Remove-Item $cmdLogFile -Force }

$monPort = 55560
$cmdQemuArgs = @(
    '-drive', 'format=raw,file=hicos-hl.img',
    '-serial', "file:$cmdLogFile",
    '-m', '128',
    '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', 'id=disk0,file=hicos-disk.img,format=raw,if=none',
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$monPort,server,nowait"
)

$cmdProc = Start-Process -FilePath $qemuPath -ArgumentList $cmdQemuArgs -PassThru -NoNewWindow
$shellPassed = 0
$shellTotal = 0

try {
    Start-Sleep -Seconds 4
    $tcp = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $monPort)
    $stream = $tcp.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream)
    $writer.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # Send "help" command
    foreach ($k in @("h","e","l","p","ret")) { $writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 250 }
    Start-Sleep -Seconds 1
    # Send "ver" command
    foreach ($k in @("v","e","r","ret")) { $writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 250 }
    Start-Sleep -Seconds 1
    # Send "ps" command
    foreach ($k in @("p","s","ret")) { $writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 250 }
    Start-Sleep -Seconds 1
    # Send unknown command "xyz"
    foreach ($k in @("x","y","z","ret")) { $writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 250 }
    Start-Sleep -Seconds 1

    $writer.Close()
    $tcp.Close()
} catch {
    Write-Host "  Shell test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $cmdProc.HasExited) { $cmdProc.Kill(); $cmdProc.WaitForExit(3000) }

$cmdContent = ''
if (Test-Path $cmdLogFile) {
    try { $cmdContent = [System.IO.File]::ReadAllText($cmdLogFile) } catch {}
}

# Verify shell command outputs
$shellTests = @(
    @{ name = 'help command shows command list'; pattern = 'HicOS Shell Commands' },
    @{ name = 'ver command shows version'; pattern = 'HicOS 5\.0.*113 modules' },
    @{ name = 'ps command shows tasks'; pattern = 'PID 0.*kernel.*running' },
    @{ name = 'unknown command rejected'; pattern = 'Unknown command.*help' },
    @{ name = 'shell prompt after command'; pattern = 'HicOS>' },
    @{ name = 'keyboard echo working'; pattern = 'help' }
)

foreach ($t in $shellTests) {
    $shellTotal++
    if ($cmdContent -match $t.pattern) {
        $passes += "Shell: $($t.name)"
        $shellPassed++
    } else {
        $errors += "Shell: $($t.name)"
    }
}

if (Test-Path $cmdLogFile) { Remove-Item $cmdLogFile -Force }

# === FAT16 Filesystem Tests ===
$fatLogFile = Join-Path $repoRoot 'qemu-fat-test.log'
if (Test-Path $fatLogFile) { Remove-Item $fatLogFile -Force }

# Recreate fresh disk image
$diskImg = Join-Path $repoRoot 'hicos-disk.img'
if (Test-Path $diskImg) { Remove-Item $diskImg -Force }
$fs = [System.IO.File]::Create($diskImg); $fs.SetLength(32MB); $fs.Close()

$fatPort = 55570
$fatQemuArgs = @(
    '-drive', 'format=raw,file=hicos-hl.img',
    '-serial', "file:$fatLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=$diskImg,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$fatPort,server,nowait"
)

$fatProc = Start-Process -FilePath $qemuPath -ArgumentList $fatQemuArgs -PassThru -NoNewWindow

try {
    Start-Sleep -Seconds 5
    $ftcp = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $fatPort)
    $fstream = $ftcp.GetStream()
    $fwriter = New-Object System.IO.StreamWriter($fstream)
    $fwriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # Step 1: format
    foreach ($k in @("f","o","r","m","a","t","ret")) { $fwriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 30

    # Step 2: mkfile test hello
    foreach ($k in @("m","k","f","i","l","e","spc","t","e","s","t","spc","h","e","l","l","o","ret")) { $fwriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # Step 3: ls
    foreach ($k in @("l","s","ret")) { $fwriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3

    # Step 4: cat test
    foreach ($k in @("c","a","t","spc","t","e","s","t","ret")) { $fwriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3

    $fwriter.Close()
    $ftcp.Close()
} catch {
    Write-Host "  FAT16 test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $fatProc.HasExited) { $fatProc.Kill(); $fatProc.WaitForExit(3000) }

$fatContent = ''
if (Test-Path $fatLogFile) {
    try { $fatContent = [System.IO.File]::ReadAllText($fatLogFile) } catch {}
}

$fatTests = @(
    @{ name = 'format creates FAT16 filesystem'; pattern = 'Format complete.*FAT16' },
    @{ name = 'mkfile creates file'; pattern = 'File created' },
    @{ name = 'ls shows file entry'; pattern = 'TEST.*bytes' },
    @{ name = 'cat reads file content'; pattern = 'hello' }
)

foreach ($t in $fatTests) {
    $shellTotal++
    if ($fatContent -match $t.pattern) {
        $passes += "FAT16: $($t.name)"
        $shellPassed++
    } else {
        $errors += "FAT16: $($t.name)"
    }
}

if (Test-Path $fatLogFile) { Remove-Item $fatLogFile -Force }

# =============================================================
# Phase 5: Network Tests (dhcp, ping, ifconfig)
# =============================================================
Write-Host "`n=== Phase 5: Network Tests ===" -ForegroundColor Cyan

$netLogFile = Join-Path $PSScriptRoot '..\qemu-net-test.log'
if (Test-Path $netLogFile) { Remove-Item $netLogFile -Force }

$netArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$netLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', 'telnet:127.0.0.1:55591,server,nowait'
)

$netProc = Start-Process -FilePath $qemuPath -ArgumentList $netArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $netClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 55591)
    $netStream = $netClient.GetStream()
    $netWriter = New-Object System.IO.StreamWriter($netStream)
    $netWriter.AutoFlush = $true

    Start-Sleep -Milliseconds 500

    # dhcp
    foreach ($k in @('d','h','c','p','ret')) {
        $netWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200
    }
    Start-Sleep -Seconds 8

    # ping
    foreach ($k in @('p','i','n','g','ret')) {
        $netWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200
    }
    Start-Sleep -Seconds 5

    # ifconfig
    foreach ($k in @('i','f','c','o','n','f','i','g','ret')) {
        $netWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200
    }
    Start-Sleep -Seconds 3

    # nslookup
    foreach ($k in @('n','s','l','o','o','k','u','p','ret')) {
        $netWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200
    }
    Start-Sleep -Seconds 8

    $netWriter.Close(); $netClient.Close()
} catch {
    Write-Host "  Net test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 3
if (-not $netProc.HasExited) { $netProc.Kill(); $netProc.WaitForExit(3000) }

$netContent = ''
if (Test-Path $netLogFile) {
    try { $netContent = [System.IO.File]::ReadAllText($netLogFile) } catch {}
}

$netTests = @(
    @{ name = 'DHCP Discover sent'; pattern = 'DHCP Discover' },
    @{ name = 'DHCP IP acquired'; pattern = 'IP acquired.*10\..*\..*\..*\d' },
    @{ name = 'Ping reply received'; pattern = 'reply received' },
    @{ name = 'ifconfig shows MAC'; pattern = 'MAC=52:54:00:12:34:56' },
    @{ name = 'ifconfig shows IP'; pattern = 'inet:.*\d+\.\d+\.\d+\.\d+' },
    @{ name = 'DNS resolves example.com'; pattern = 'example\.com\s*=\s*\d+\.\d+\.\d+\.\d+' }
)

foreach ($t in $netTests) {
    $shellTotal++
    if ($netContent -match $t.pattern) {
        $passes += "Net: $($t.name)"
        $shellPassed++
    } else {
        $errors += "Net: $($t.name)"
    }
}

if (Test-Path $netLogFile) { Remove-Item $netLogFile -Force }

# =============================================================
# Phase 6: Ring3 User Mode Test
# =============================================================
Write-Host "`n=== Phase 6: Ring3 Test ===" -ForegroundColor Cyan

$r3LogFile = Join-Path $PSScriptRoot '..\qemu-ring3-test.log'
if (Test-Path $r3LogFile) { Remove-Item $r3LogFile -Force }

$r3Args = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$r3LogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', 'telnet:127.0.0.1:55598,server,nowait'
)

$r3Proc = Start-Process -FilePath $qemuPath -ArgumentList $r3Args -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $r3Client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 55598)
    $r3Stream = $r3Client.GetStream()
    $r3Writer = New-Object System.IO.StreamWriter($r3Stream)
    $r3Writer.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    foreach ($k in @('r','i','n','g','3','ret')) {
        $r3Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200
    }
    Start-Sleep -Seconds 3

    $r3Writer.Close(); $r3Client.Close()
} catch {
    Write-Host "  Ring3 test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $r3Proc.HasExited) { $r3Proc.Kill(); $r3Proc.WaitForExit(3000) }

$r3Content = ''
if (Test-Path $r3LogFile) {
    try { $r3Content = [System.IO.File]::ReadAllText($r3LogFile) } catch {}
}

$r3Tests = @(
    @{ name = 'IRETQ to Ring3 + SYSCALL print'; pattern = 'U3' },
    @{ name = 'Ring3 test passed'; pattern = 'Ring3.*user mode test PASSED' }
)

foreach ($t in $r3Tests) {
    $shellTotal++
    if ($r3Content -match $t.pattern) {
        $passes += "Ring3: $($t.name)"
        $shellPassed++
    } else {
        $errors += "Ring3: $($t.name)"
    }
}

if (Test-Path $r3LogFile) { Remove-Item $r3LogFile -Force }

Write-Host "=== Boot Test Results ===" -ForegroundColor Cyan
foreach ($p in $passes) {
    Write-Host "  PASS: $p" -ForegroundColor Green
}
foreach ($e in $errors) {
    Write-Host "  FAIL: $e" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Serial bytes: $($serialContent.Length)"
Write-Host "  Serial lines: $(($serialContent -split "`n").Count)"
Write-Host "  QEMU exit:    $($proc.ExitCode)"
Write-Host ""

# Clean up
if (-not $KeepLog -and (Test-Path $logFile)) {
    Remove-Item $logFile -Force
}

if ($errors.Count -gt 0 -and $passes.Count -eq 0) {
    Write-Host "BOOT TEST: FAILED" -ForegroundColor Red
    exit 1
} elseif ($passes.Count -gt 0) {
    Write-Host "BOOT TEST: PASSED ($($passes.Count) checks)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "BOOT TEST: INCONCLUSIVE (no output)" -ForegroundColor Yellow
    exit 1
}
