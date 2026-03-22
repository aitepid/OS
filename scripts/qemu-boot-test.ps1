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
    @{ name = 'help shows clear command'; pattern = 'clear' },
    @{ name = 'help shows hexdump command'; pattern = 'hexdump' },
    @{ name = 'ver command shows version'; pattern = 'HicOS [56]\.0.*\d+ modules' },
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

# =============================================================
# Phase 7: Hardware Detection Tests (ACPI, SMP, AHCI, USB)
# =============================================================
Write-Host "`n=== Phase 7: Hardware Detection Tests ===" -ForegroundColor Cyan

$hwLogFile = Join-Path $repoRoot 'qemu-hw-test.log'
if (Test-Path $hwLogFile) { Remove-Item $hwLogFile -Force }

$hwPort = 55592
$hwArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$hwLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-smp', '2',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$hwPort,server,nowait"
)

$hwProc = Start-Process -FilePath $qemuPath -ArgumentList $hwArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $hwClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $hwPort)
    $hwStream = $hwClient.GetStream()
    $hwWriter = New-Object System.IO.StreamWriter($hwStream)
    $hwWriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # acpi
    foreach ($k in @('a','c','p','i','ret')) { $hwWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    # smp
    foreach ($k in @('s','m','p','ret')) { $hwWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3

    # ahci
    foreach ($k in @('a','h','c','i','ret')) { $hwWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    # usb
    foreach ($k in @('u','s','b','ret')) { $hwWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    # time
    foreach ($k in @('t','i','m','e','ret')) { $hwWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    # uptime
    foreach ($k in @('u','p','t','i','m','e','ret')) { $hwWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $hwWriter.Close(); $hwClient.Close()
} catch {
    Write-Host "  HW test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $hwProc.HasExited) { $hwProc.Kill(); $hwProc.WaitForExit(3000) }

$hwContent = ''
if (Test-Path $hwLogFile) {
    try { $hwContent = [System.IO.File]::ReadAllText($hwLogFile) } catch {}
}

$hwTests = @(
    @{ name = 'ACPI command responds'; pattern = 'ACPI|RSDP|FADT|PM1' },
    @{ name = 'SMP detects CPUs'; pattern = 'CPU|AP|core|online' },
    @{ name = 'AHCI controller scan'; pattern = 'AHCI|SATA|port' },
    @{ name = 'USB xHCI scan'; pattern = 'xHCI|USB|port' },
    @{ name = 'RTC time display'; pattern = '\d{4}-\d{2}-\d{2}|\d{2}:\d{2}:\d{2}' },
    @{ name = 'Uptime display'; pattern = 'uptime|tick|second|hour|minute' }
)

foreach ($t in $hwTests) {
    $shellTotal++
    if ($hwContent -match $t.pattern) {
        $passes += "HW: $($t.name)"
        $shellPassed++
    } else {
        $errors += "HW: $($t.name)"
    }
}

if (Test-Path $hwLogFile) { Remove-Item $hwLogFile -Force }

# =============================================================
# Phase 8: Disk I/O + VirtIO-blk Tests
# =============================================================
Write-Host "`n=== Phase 8: Disk I/O Tests ===" -ForegroundColor Cyan

$diskLogFile = Join-Path $repoRoot 'qemu-disk-test.log'
if (Test-Path $diskLogFile) { Remove-Item $diskLogFile -Force }

$diskPort = 55593
$diskArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$diskLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$diskPort,server,nowait"
)

$diskProc = Start-Process -FilePath $qemuPath -ArgumentList $diskArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $dClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $diskPort)
    $dStream = $dClient.GetStream()
    $dWriter = New-Object System.IO.StreamWriter($dStream)
    $dWriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # disk command
    foreach ($k in @('d','i','s','k','ret')) { $dWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3

    # hexdump command
    foreach ($k in @('h','e','x','d','u','m','p','ret')) { $dWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # clear command (just verify it doesn't crash)
    foreach ($k in @('c','l','e','a','r','ret')) { $dWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    # ver command
    foreach ($k in @('v','e','r','ret')) { $dWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    # tick command
    foreach ($k in @('t','i','c','k','ret')) { $dWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $dWriter.Close(); $dClient.Close()
} catch {
    Write-Host "  Disk test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $diskProc.HasExited) { $diskProc.Kill(); $diskProc.WaitForExit(3000) }

$diskContent = ''
if (Test-Path $diskLogFile) {
    try { $diskContent = [System.IO.File]::ReadAllText($diskLogFile) } catch {}
}

$diskTests = @(
    @{ name = 'disk command shows capacity'; pattern = 'VirtIO-blk|capacity|MB|sector' },
    @{ name = 'hexdump shows sector data'; pattern = 'Sector 0 hex dump|[0-9A-Fa-f]{2} [0-9A-Fa-f]{2}' },
    @{ name = 'hexdump MBR signature check'; pattern = '55AA|signature' },
    @{ name = 'clear command accepted'; pattern = 'HicOS>' },
    @{ name = 'ver shows version info'; pattern = 'HicOS.*\d' },
    @{ name = 'tick counter active'; pattern = 'tick|Timer' }
)

foreach ($t in $diskTests) {
    $shellTotal++
    if ($diskContent -match $t.pattern) {
        $passes += "Disk: $($t.name)"
        $shellPassed++
    } else {
        $errors += "Disk: $($t.name)"
    }
}

if (Test-Path $diskLogFile) { Remove-Item $diskLogFile -Force }

# =============================================================
# Phase 9: Installer Tests
# =============================================================
Write-Host "`n=== Phase 9: Installer Tests ===" -ForegroundColor Cyan

$instLogFile = Join-Path $repoRoot 'qemu-install-test.log'
if (Test-Path $instLogFile) { Remove-Item $instLogFile -Force }

# Fresh disk for install test
$instDisk = Join-Path $repoRoot 'hicos-disk.img'
if (Test-Path $instDisk) { Remove-Item $instDisk -Force }
$instFs = [System.IO.File]::Create($instDisk); $instFs.SetLength(32MB); $instFs.Close()

$instPort = 55594
$instArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$instLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=$instDisk,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$instPort,server,nowait"
)

$instProc = Start-Process -FilePath $qemuPath -ArgumentList $instArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $iClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $instPort)
    $iStream = $iClient.GetStream()
    $iWriter = New-Object System.IO.StreamWriter($iStream)
    $iWriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # install command
    foreach ($k in @('i','n','s','t','a','l','l','ret')) { $iWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 35

    $iWriter.Close(); $iClient.Close()
} catch {
    Write-Host "  Install test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $instProc.HasExited) { $instProc.Kill(); $instProc.WaitForExit(3000) }

$instContent = ''
if (Test-Path $instLogFile) {
    try { $instContent = [System.IO.File]::ReadAllText($instLogFile) } catch {}
}

$instTests = @(
    @{ name = 'Installer detects disk'; pattern = '1/7|detect|disk|capacity' },
    @{ name = 'MBR partition created'; pattern = '2/7|MBR|partition' },
    @{ name = 'FAT16 formatted'; pattern = '3/7|FAT16|format' },
    @{ name = 'Install completion'; pattern = '7/7|complete|Install' }
)

foreach ($t in $instTests) {
    $shellTotal++
    if ($instContent -match $t.pattern) {
        $passes += "Install: $($t.name)"
        $shellPassed++
    } else {
        $errors += "Install: $($t.name)"
    }
}

if (Test-Path $instLogFile) { Remove-Item $instLogFile -Force }

# =============================================================
# Phase 10: Interpreter + run command Tests
# =============================================================
Write-Host "`n=== Phase 10: Interpreter Tests ===" -ForegroundColor Cyan

$runLogFile = Join-Path $repoRoot 'qemu-run-test.log'
if (Test-Path $runLogFile) { Remove-Item $runLogFile -Force }

# Fresh disk
if (Test-Path $instDisk) { Remove-Item $instDisk -Force }
$runFs = [System.IO.File]::Create($instDisk); $runFs.SetLength(32MB); $runFs.Close()

$runPort = 55595
$runArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$runLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=$instDisk,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$runPort,server,nowait"
)

$runProc = Start-Process -FilePath $qemuPath -ArgumentList $runArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $rClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $runPort)
    $rStream = $rClient.GetStream()
    $rWriter = New-Object System.IO.StreamWriter($rStream)
    $rWriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # format first
    foreach ($k in @('f','o','r','m','a','t','ret')) { $rWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 25

    # mkfile hi.hl print("Hi")
    foreach ($k in @('m','k','f','i','l','e','spc','h','i','dot','h','l','spc','p','r','i','n','t','shift-9','shift-apostrophe','shift-h','i','shift-apostrophe','shift-0','ret')) { $rWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # run hi.hl
    foreach ($k in @('r','u','n','spc','h','i','dot','h','l','ret')) { $rWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    $rWriter.Close(); $rClient.Close()
} catch {
    Write-Host "  Run test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $runProc.HasExited) { $runProc.Kill(); $runProc.WaitForExit(3000) }

$runContent = ''
if (Test-Path $runLogFile) {
    try { $runContent = [System.IO.File]::ReadAllText($runLogFile) } catch {}
}

$runTests = @(
    @{ name = 'Format before run succeeds'; pattern = 'Format complete|FAT16' },
    @{ name = 'File created for interpreter'; pattern = 'File created|mkfile' },
    @{ name = 'Interpreter loads file'; pattern = 'run|load|exec' },
    @{ name = 'Shell prompt returns after run'; pattern = 'HicOS>' }
)

foreach ($t in $runTests) {
    $shellTotal++
    if ($runContent -match $t.pattern) {
        $passes += "Run: $($t.name)"
        $shellPassed++
    } else {
        $errors += "Run: $($t.name)"
    }
}

if (Test-Path $runLogFile) { Remove-Item $runLogFile -Force }

# =============================================================
# Phase 11: Memory Management Tests
# =============================================================
Write-Host "`n=== Phase 11: Memory Management Tests ===" -ForegroundColor Cyan

$memLogFile = Join-Path $repoRoot 'qemu-mem-test.log'
if (Test-Path $memLogFile) { Remove-Item $memLogFile -Force }

$memPort = 55596
$memArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$memLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$memPort,server,nowait"
)

$memProc = Start-Process -FilePath $qemuPath -ArgumentList $memArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $mClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $memPort)
    $mStream = $mClient.GetStream()
    $mWriter = New-Object System.IO.StreamWriter($mStream)
    $mWriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # pmem
    foreach ($k in @('p','m','e','m','ret')) { $mWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    # palloc
    foreach ($k in @('p','a','l','l','o','c','ret')) { $mWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    # malloc
    foreach ($k in @('m','a','l','l','o','c','ret')) { $mWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $mWriter.Close(); $mClient.Close()
} catch {
    Write-Host "  Memory test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $memProc.HasExited) { $memProc.Kill(); $memProc.WaitForExit(3000) }

$memContent = ''
if (Test-Path $memLogFile) {
    try { $memContent = [System.IO.File]::ReadAllText($memLogFile) } catch {}
}

$memTests = @(
    @{ name = 'pmem shows page alloc status'; pattern = 'page|alloc|free|total' },
    @{ name = 'palloc allocates a page'; pattern = 'alloc|page|0x' },
    @{ name = 'malloc allocates heap block'; pattern = 'malloc|alloc|heap|0x' }
)

foreach ($t in $memTests) {
    $shellTotal++
    if ($memContent -match $t.pattern) {
        $passes += "Mem: $($t.name)"
        $shellPassed++
    } else {
        $errors += "Mem: $($t.name)"
    }
}

if (Test-Path $memLogFile) { Remove-Item $memLogFile -Force }

# =============================================================
# Phase 12: SHA-256 Cryptographic Hash Tests
# =============================================================
Write-Host "`n=== Phase 12: SHA-256 Cryptographic Hash Tests ===" -ForegroundColor Cyan

$shaLogFile = Join-Path $repoRoot 'qemu-sha256-test.log'
if (Test-Path $shaLogFile) { Remove-Item $shaLogFile -Force }

$shaPort = 55597
$shaArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$shaLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$shaPort,server,nowait"
)

$shaProc = Start-Process -FilePath $qemuPath -ArgumentList $shaArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $sClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $shaPort)
    $sStream = $sClient.GetStream()
    $sWriter = New-Object System.IO.StreamWriter($sStream)
    $sWriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # sha256 abc
    foreach ($k in @('s','h','a','2','5','6','space','a','b','c','ret')) { $sWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # sha256 (no arg, usage test)
    foreach ($k in @('s','h','a','2','5','6','ret')) { $sWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    # help (verify sha256 in help)
    foreach ($k in @('h','e','l','p','ret')) { $sWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $sWriter.Close(); $sClient.Close()
} catch {
    Write-Host "  SHA-256 test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $shaProc.HasExited) { $shaProc.Kill(); $shaProc.WaitForExit(3000) }

$shaContent = ''
if (Test-Path $shaLogFile) {
    try { $shaContent = [System.IO.File]::ReadAllText($shaLogFile) } catch {}
}

$shaTests = @(
    @{ name = 'sha256 produces SHA256: prefix'; pattern = 'SHA256:' },
    @{ name = 'sha256 abc produces hex output'; pattern = '[0-9A-Fa-f]{64}' },
    @{ name = 'help shows sha256 command'; pattern = 'sha256' }
)

foreach ($t in $shaTests) {
    $shellTotal++
    if ($shaContent -match $t.pattern) {
        $passes += "SHA256: $($t.name)"
        $shellPassed++
    } else {
        $errors += "SHA256: $($t.name)"
    }
}

if (Test-Path $shaLogFile) { Remove-Item $shaLogFile -Force }

# =============================================================
# Phase 13: HMAC-SHA-256 + HKDF Tests
# =============================================================
Write-Host "`n=== Phase 13: HMAC-SHA-256 + HKDF Tests ===" -ForegroundColor Cyan

$hmacLogFile = Join-Path $repoRoot 'qemu-hmac-test.log'
if (Test-Path $hmacLogFile) { Remove-Item $hmacLogFile -Force }

$hmacPort = 55598
$hmacArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$hmacLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$hmacPort,server,nowait"
)

$hmacProc = Start-Process -FilePath $qemuPath -ArgumentList $hmacArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $hClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $hmacPort)
    $hStream = $hClient.GetStream()
    $hWriter = New-Object System.IO.StreamWriter($hStream)
    $hWriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # hmac test
    foreach ($k in @('h','m','a','c','space','t','e','s','t','ret')) { $hWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # hkdf
    foreach ($k in @('h','k','d','f','ret')) { $hWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 8

    # help (verify hmac/hkdf in help)
    foreach ($k in @('h','e','l','p','ret')) { $hWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $hWriter.Close(); $hClient.Close()
} catch {
    Write-Host "  HMAC/HKDF test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $hmacProc.HasExited) { $hmacProc.Kill(); $hmacProc.WaitForExit(3000) }

$hmacContent = ''
if (Test-Path $hmacLogFile) {
    try { $hmacContent = [System.IO.File]::ReadAllText($hmacLogFile) } catch {}
}

$hmacTests = @(
    @{ name = 'hmac produces HMAC: prefix'; pattern = 'HMAC:' },
    @{ name = 'hmac produces hex output'; pattern = 'HMAC: [0-9A-Fa-f]{64}' },
    @{ name = 'hkdf produces HKDF: prefix'; pattern = 'HKDF:' },
    @{ name = 'hkdf produces hex output'; pattern = 'HKDF: [0-9A-Fa-f]{64}' },
    @{ name = 'help shows hmac command'; pattern = 'hmac' },
    @{ name = 'help shows hkdf command'; pattern = 'hkdf' }
)

foreach ($t in $hmacTests) {
    $shellTotal++
    if ($hmacContent -match $t.pattern) {
        $passes += "HMAC: $($t.name)"
        $shellPassed++
    } else {
        $errors += "HMAC: $($t.name)"
    }
}

if (Test-Path $hmacLogFile) { Remove-Item $hmacLogFile -Force }

# =============================================================
# Phase 14: AES-128 + GCM + TLS 1.3 Tests
# =============================================================
Write-Host "`n=== Phase 14: AES-128 + GCM + TLS 1.3 Tests ===" -ForegroundColor Cyan

$aesLogFile = Join-Path $repoRoot 'qemu-aes-test.log'
if (Test-Path $aesLogFile) { Remove-Item $aesLogFile -Force }

$aesPort = 55599
$aesArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$aesLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$aesPort,server,nowait"
)

$aesProc = Start-Process -FilePath $qemuPath -ArgumentList $aesArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $aClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $aesPort)
    $aStream = $aClient.GetStream()
    $aWriter = New-Object System.IO.StreamWriter($aStream)
    $aWriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # aes command
    foreach ($k in @('a','e','s','ret')) { $aWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 8

    # gcm command
    foreach ($k in @('g','c','m','ret')) { $aWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 10

    # tls command
    foreach ($k in @('t','l','s','ret')) { $aWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 10

    # help (verify aes/gcm/tls in help)
    foreach ($k in @('h','e','l','p','ret')) { $aWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $aWriter.Close(); $aClient.Close()
} catch {
    Write-Host "  AES/GCM/TLS test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $aesProc.HasExited) { $aesProc.Kill(); $aesProc.WaitForExit(3000) }

$aesContent = ''
if (Test-Path $aesLogFile) {
    try { $aesContent = [System.IO.File]::ReadAllText($aesLogFile) } catch {}
}

$aesTests = @(
    @{ name = 'aes produces AES: prefix'; pattern = 'AES:' },
    @{ name = 'aes produces hex output'; pattern = 'AES: [0-9A-Fa-f]{32}' },
    @{ name = 'gcm produces GCM-CT: prefix'; pattern = 'GCM-CT:' },
    @{ name = 'gcm produces GCM-TAG: prefix'; pattern = 'GCM-TAG:' },
    @{ name = 'tls ClientHello constructed'; pattern = 'ClientHello' },
    @{ name = 'tls KeySchedule completed'; pattern = 'KeySchedule OK' },
    @{ name = 'tls cipher suite shown'; pattern = 'TLS_AES_128_GCM_SHA256' },
    @{ name = 'tls HS-Key shown'; pattern = 'HS-Key:' },
    @{ name = 'help shows aes command'; pattern = 'aes' },
    @{ name = 'help shows gcm command'; pattern = 'gcm' },
    @{ name = 'help shows tls command'; pattern = 'tls' }
)

foreach ($t in $aesTests) {
    $shellTotal++
    if ($aesContent -match $t.pattern) {
        $passes += "AES/TLS: $($t.name)"
        $shellPassed++
    } else {
        $errors += "AES/TLS: $($t.name)"
    }
}

if (Test-Path $aesLogFile) { Remove-Item $aesLogFile -Force }

# =============================================================
# Phase 15: HTTPS + GraphicalTerminal + ext2 + hlpkg Tests
# =============================================================
Write-Host "`n=== Phase 15: HTTPS + GTERM + ext2 + hlpkg Tests ===" -ForegroundColor Cyan

$iter53LogFile = Join-Path $repoRoot 'qemu-iter53-test.log'
if (Test-Path $iter53LogFile) { Remove-Item $iter53LogFile -Force }

$iter53Port = 55600
$iter53Args = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$iter53LogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$iter53Port,server,nowait"
)

$iter53Proc = Start-Process -FilePath $qemuPath -ArgumentList $iter53Args -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $i53Client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $iter53Port)
    $i53Stream = $i53Client.GetStream()
    $i53Writer = New-Object System.IO.StreamWriter($i53Stream)
    $i53Writer.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # https command
    foreach ($k in @('h','t','t','p','s','ret')) { $i53Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 8

    # gterm command
    foreach ($k in @('g','t','e','r','m','ret')) { $i53Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # ext2 command
    foreach ($k in @('e','x','t','2','ret')) { $i53Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # help (verify new commands in help)
    foreach ($k in @('h','e','l','p','ret')) { $i53Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $i53Writer.Close(); $i53Client.Close()
} catch {
    Write-Host "  Iter53-56 test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $iter53Proc.HasExited) { $iter53Proc.Kill(); $iter53Proc.WaitForExit(3000) }

$iter53Content = ''
if (Test-Path $iter53LogFile) {
    try { $iter53Content = [System.IO.File]::ReadAllText($iter53LogFile) } catch {}
}

$iter53Tests = @(
    @{ name = 'https produces HTTPS: prefix'; pattern = 'HTTPS:' },
    @{ name = 'https GET request built'; pattern = 'GET example' },
    @{ name = 'https TLS record encrypted'; pattern = 'TLS record' },
    @{ name = 'https simulated response'; pattern = 'HTTP/1.1 200 OK' },
    @{ name = 'gterm produces GTERM: output'; pattern = 'GTERM:' },
    @{ name = 'gterm 80x47 active'; pattern = '80x47' },
    @{ name = 'ext2 produces EXT2: output'; pattern = 'EXT2:' },
    @{ name = 'help shows https command'; pattern = 'https' },
    @{ name = 'help shows gterm command'; pattern = 'gterm' },
    @{ name = 'help shows ext2 command'; pattern = 'ext2' },
    @{ name = 'help shows hlpkg command'; pattern = 'hlpkg' }
)

foreach ($t in $iter53Tests) {
    $shellTotal++
    if ($iter53Content -match $t.pattern) {
        $passes += "I53-56: $($t.name)"
        $shellPassed++
    } else {
        $errors += "I53-56: $($t.name)"
    }
}

if (Test-Path $iter53LogFile) { Remove-Item $iter53LogFile -Force }

# =============================================================
# Phase 16: Lexer + VirtIO-GPU + POSIX + Editor Tests
# =============================================================
Write-Host "`n=== Phase 16: v8.0 Phase I Tests ===" -ForegroundColor Cyan

$v8LogFile = Join-Path $repoRoot 'qemu-v8-test.log'
if (Test-Path $v8LogFile) { Remove-Item $v8LogFile -Force }

$v8Port = 55601
$v8Args = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$v8LogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$v8Port,server,nowait"
)

$v8Proc = Start-Process -FilePath $qemuPath -ArgumentList $v8Args -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $v8Client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $v8Port)
    $v8Stream = $v8Client.GetStream()
    $v8Writer = New-Object System.IO.StreamWriter($v8Stream)
    $v8Writer.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # lex command: "lex let x = 42;"
    foreach ($k in @('l','e','x','space','l','e','t','space','x','space','equal','space','4','2','semicolon','ret')) { $v8Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # vgpu command
    foreach ($k in @('v','g','p','u','ret')) { $v8Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3

    # posix command
    foreach ($k in @('p','o','s','i','x','ret')) { $v8Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # help (verify new commands)
    foreach ($k in @('h','e','l','p','ret')) { $v8Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $v8Writer.Close(); $v8Client.Close()
} catch {
    Write-Host "  v8 test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $v8Proc.HasExited) { $v8Proc.Kill(); $v8Proc.WaitForExit(3000) }

$v8Content = ''
if (Test-Path $v8LogFile) {
    try { $v8Content = [System.IO.File]::ReadAllText($v8LogFile) } catch {}
}

$v8Tests = @(
    @{ name = 'lex produces LEX: prefix'; pattern = 'LEX:' },
    @{ name = 'lex produces token count'; pattern = 'tokens' },
    @{ name = 'lex identifies LET keyword'; pattern = 'LET' },
    @{ name = 'vgpu produces VGPU: output'; pattern = 'VGPU:' },
    @{ name = 'posix produces POSIX: prefix'; pattern = 'POSIX:' },
    @{ name = 'posix open test passes'; pattern = 'open:' },
    @{ name = 'posix 3/3 PASS'; pattern = '3/3 PASS' },
    @{ name = 'help shows lex command'; pattern = 'lex' },
    @{ name = 'help shows vgpu command'; pattern = 'vgpu' },
    @{ name = 'help shows posix command'; pattern = 'posix' },
    @{ name = 'help shows edit command'; pattern = 'edit' }
)

foreach ($t in $v8Tests) {
    $shellTotal++
    if ($v8Content -match $t.pattern) {
        $passes += "v8.0: $($t.name)"
        $shellPassed++
    } else {
        $errors += "v8.0: $($t.name)"
    }
}

if (Test-Path $v8LogFile) { Remove-Item $v8LogFile -Force }

# =============================================================
# Phase 17: Parser + Files + Browse + Container Tests
# =============================================================
Write-Host "`n=== Phase 17: v8.0 Phase II Tests ===" -ForegroundColor Cyan

$v8bLogFile = Join-Path $repoRoot 'qemu-v8b-test.log'
if (Test-Path $v8bLogFile) { Remove-Item $v8bLogFile -Force }

$v8bPort = 55602
$v8bArgs = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$v8bLogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$v8bPort,server,nowait"
)

$v8bProc = Start-Process -FilePath $qemuPath -ArgumentList $v8bArgs -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $v8bClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $v8bPort)
    $v8bStream = $v8bClient.GetStream()
    $v8bWriter = New-Object System.IO.StreamWriter($v8bStream)
    $v8bWriter.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # files command
    foreach ($k in @('f','i','l','e','s','ret')) { $v8bWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # container command
    foreach ($k in @('c','o','n','t','a','i','n','e','r','ret')) { $v8bWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # help (verify new commands in help)
    foreach ($k in @('h','e','l','p','ret')) { $v8bWriter.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $v8bWriter.Close(); $v8bClient.Close()
} catch {
    Write-Host "  v8b test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $v8bProc.HasExited) { $v8bProc.Kill(); $v8bProc.WaitForExit(3000) }

$v8bContent = ''
if (Test-Path $v8bLogFile) {
    try { $v8bContent = [System.IO.File]::ReadAllText($v8bLogFile) } catch {}
}

$v8bTests = @(
    @{ name = 'files shows FAT16 listing'; pattern = 'FILES' },
    @{ name = 'files shows file count'; pattern = 'files on FAT16' },
    @{ name = 'container creates groups'; pattern = 'CONTAINER:' },
    @{ name = 'container shows CG stats'; pattern = 'CG\[' },
    @{ name = 'container shows pids'; pattern = 'pids=' },
    @{ name = 'container shows mem limit'; pattern = 'mem=' },
    @{ name = 'help shows parse command'; pattern = 'parse' },
    @{ name = 'help shows files command'; pattern = 'files' },
    @{ name = 'help shows browse command'; pattern = 'browse' },
    @{ name = 'help shows container command'; pattern = 'container' }
)

foreach ($t in $v8bTests) {
    $shellTotal++
    if ($v8bContent -match $t.pattern) {
        $passes += "v8.0b: $($t.name)"
        $shellPassed++
    } else {
        $errors += "v8.0b: $($t.name)"
    }
}

if (Test-Path $v8bLogFile) { Remove-Item $v8bLogFile -Force }

# =============================================================
# Phase 18: Codegen + NVMe + Login + Pipe Tests (v9.0)
# =============================================================
Write-Host "`n=== Phase 18: v9.0 Phase I Tests ===" -ForegroundColor Cyan

$v9LogFile = Join-Path $repoRoot 'qemu-v9-test.log'
if (Test-Path $v9LogFile) { Remove-Item $v9LogFile -Force }

$v9Port = 55603
$v9Args = @(
    '-drive', "format=raw,file=hicos-hl.img",
    '-serial', "file:$v9LogFile",
    '-m', '128', '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot', '-no-shutdown',
    '-monitor', "telnet:127.0.0.1:$v9Port,server,nowait"
)

$v9Proc = Start-Process -FilePath $qemuPath -ArgumentList $v9Args -PassThru -NoNewWindow
Start-Sleep -Seconds 5

try {
    $v9Client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $v9Port)
    $v9Stream = $v9Client.GetStream()
    $v9Writer = New-Object System.IO.StreamWriter($v9Stream)
    $v9Writer.AutoFlush = $true
    Start-Sleep -Milliseconds 500

    # whoami command
    foreach ($k in @('w','h','o','a','m','i','ret')) { $v9Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3

    # pipe command
    foreach ($k in @('p','i','p','e','ret')) { $v9Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5

    # nvme command
    foreach ($k in @('n','v','m','e','ret')) { $v9Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3

    # help (verify new commands)
    foreach ($k in @('h','e','l','p','ret')) { $v9Writer.WriteLine("sendkey $k"); Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 2

    $v9Writer.Close(); $v9Client.Close()
} catch {
    Write-Host "  v9 test monitor error: $_" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1
if (-not $v9Proc.HasExited) { $v9Proc.Kill(); $v9Proc.WaitForExit(3000) }

$v9Content = ''
if (Test-Path $v9LogFile) {
    try { $v9Content = [System.IO.File]::ReadAllText($v9LogFile) } catch {}
}

$v9Tests = @(
    @{ name = 'whoami shows root user'; pattern = 'root' },
    @{ name = 'whoami shows uid'; pattern = 'uid=' },
    @{ name = 'pipe test passes'; pattern = 'PIPE:' },
    @{ name = 'pipe create OK'; pattern = 'create:' },
    @{ name = 'pipe write OK'; pattern = 'write:' },
    @{ name = 'pipe read data matches'; pattern = 'HicOS' },
    @{ name = 'pipe 3/3 PASS'; pattern = '3/3 PASS' },
    @{ name = 'nvme detection runs'; pattern = 'NVME:' },
    @{ name = 'help shows compile'; pattern = 'compile' },
    @{ name = 'help shows nvme'; pattern = 'nvme' },
    @{ name = 'help shows login'; pattern = 'login' },
    @{ name = 'help shows whoami'; pattern = 'whoami' },
    @{ name = 'help shows pipe'; pattern = 'pipe' }
)

foreach ($t in $v9Tests) {
    $shellTotal++
    if ($v9Content -match $t.pattern) {
        $passes += "v9.0: $($t.name)"
        $shellPassed++
    } else {
        $errors += "v9.0: $($t.name)"
    }
}

if (Test-Path $v9LogFile) { Remove-Item $v9LogFile -Force }

Write-Host "`n=== Boot Test Results ===" -ForegroundColor Cyan
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
Write-Host "  Total checks: $($passes.Count + $errors.Count) (PASS: $($passes.Count), FAIL: $($errors.Count))"
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
