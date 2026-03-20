# HicOS 5.0 鈥?100% Pure Hilbert-Lang Operating System

## Overview

HicOS is a bare-metal x86_64 operating system written entirely in **Hilbert-Lang (H-L)**.
**Zero JavaScript. Zero Rust. Zero C. Zero external dependencies.**

All 164 active source files are `.hl` (legacy JS-origin files purged).
Dual-boot support: BIOS/MBR (`hicos-hl.img`, 41 KB) and UEFI/GPT (`hicos-uefi.img`, 33 MB).
Both boot paths verified end-to-end in QEMU (42/42 BIOS checks + 3/3 UEFI checks).

## Quick Start

```bash
# BIOS boot in QEMU
qemu-system-x86_64 -drive format=raw,file=hicos-hl.img -serial stdio -display none

# UEFI boot in QEMU (requires OVMF)
qemu-system-x86_64 -drive if=pflash,format=raw,unit=0,readonly=on,file=ovmf-code.fd \
  -drive file=hicos-uefi.img,format=raw,if=ide -display none -serial stdio
```

Optional (run via wrapper script):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-qemu.ps1 -NoDisplay
```

Optional (preflight + run in one command):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\boot-and-run.ps1 -NoDisplay
```

If QEMU is installed but not in PATH:

```powershell
$env:QEMU_HOME="C:\Program Files\qemu"
powershell -ExecutionPolicy Bypass -File .\scripts\boot-and-run.ps1 -NoDisplay
```

## Workspace Validation

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-workspace.ps1
```

Optional (when `hl-bootstrap` is available):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-workspace.ps1 -RunHlBuild -RunHlTests
```

Optional (strict gate for language purity and no-stub policy):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-workspace.ps1 -StrictLanguagePurity -StrictNoStubs
```

Optional (boot chain readiness check):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\boot-readiness.ps1
```

Optional (runtime path readiness check):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\runtime-path-readiness.ps1
```

Optional (image layout readiness check):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\image-layout-readiness.ps1
```

Optional (full gate, one command):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1
```

Optional (boot preflight):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\boot-preflight.ps1
```

Optional (hl-bootstrap build + test):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\hl-bootstrap-build-test.ps1
```

Optional (full gate and require hl-bootstrap step):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1 -RequireHlBootstrap
```

Optional (install QEMU via winget):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-qemu.ps1
```

## Architecture

```
HicOS/
鈹溾攢鈹€ bare-kernel/
鈹?  鈹斺攢鈹€ hl/                  # 114 kernel modules (pure H-L)
鈹?      鈹溾攢鈹€ stage1.hl        # MBR boot sector (512 bytes)
鈹?      鈹溾攢鈹€ stage2.hl        # Real 鈫?Protected 鈫?Long mode
鈹?      鈹溾攢鈹€ kernel_entry.hl  # H-L kernel entry (IDT+PIC+PIT+KBD)
鈹?      鈹溾攢鈹€ kernel_init.hl   # Subsystem init sequence
鈹?      鈹溾攢鈹€ shell.hl         # Interactive shell (60 commands)
鈹?      鈹溾攢鈹€ errno.hl         # POSIX error codes
鈹?      鈹溾攢鈹€ hilbert.hl       # Hilbert curve encode/decode/dist
鈹?      鈹溾攢鈹€ hlc_loader.hl    # .hlc executable format loader
鈹?      鈹溾攢鈹€ xref.hl          # Symbol cross-reference scanner
鈹?      鈹溾攢鈹€ build.hl         # Build system
鈹?      鈹斺攢鈹€ ... (108 modules total)
鈹溾攢鈹€ HicOS_*.hl               # Native userspace modules (27 files)
鈹溾攢鈹€ hl-bootstrap.hl          # Self-hosting bootstrap compiler (H-L, 4,630 lines)
鈹溾攢鈹€ stdlib.hl                # Standard library (1,528 lines)
鈹溾攢鈹€ hicos-hl.img             # BIOS bootable x86_64 image (41 KB, 81 sectors)
鈹溾攢鈹€ hicos-uefi.img           # UEFI bootable GPT+ESP image (33 MB)
鈹溾攢鈹€ BOOTX64.EFI              # PE32+ UEFI application (1.5 KB)
鈹溾攢鈹€ scripts/                 # 17 build/test/gate scripts
鈹溾攢鈹€ DEEP_DEVELOPMENT_PLAN.hl # Development plan vs Windows/macOS
鈹溾攢鈹€ README.md
鈹斺攢鈹€ ROADMAP.md
```

## Hilbert-Lang

H-L is a spatial programming language where data and code are addressed
via 3D Hilbert-curve coordinates instead of linear arrays.

```hl
// Hilbert spatial encoding 鈥?O(1) bit-interleave
let key = hilbert_encode(42, 17, 9);
let dist = hilbert_dist(key, hilbert_encode(43, 17, 9));

// Class with inheritance and magic methods (Python-level OOP)
class Animal {
    fn __init__(self, name) { self.name = name; }
    fn __str__(self) { return self.name; }
}
class Dog : Animal {
    fn speak(self) { return self.name + " barks"; }
}

// List comprehension + decorators
@cache
fn fib(n) {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}
let squares = [x ** 2 for x in range(20) if x % 2 == 0];

// Deep destructuring
let [a, [b, c]] = [1, [2, 3]];

// Generators (lazy evaluation)
let gen = gen_range(0, 1);
let first10 = gen_take(gen, 10);

// Exception handling with typed catch
try {
    raise TypeError("bad type");
} catch e : TypeError {
    print(e.message);
} finally {
    cleanup();
}

// Quadrant 鈥?spatial module scope
quadrant scheduler {
    fn nice_to_weight(nice) {
        let mut w = 1024;
        let mut n = nice;
        if n > 0 {
            while n > 0 { w = w * 4 / 5; n = n - 1; }
        }
        return w;
    }
}

// Type annotations (optional)
fn add(a: int, b: int) -> int { return a + b; }

// Spatial IPC
emit scheduler_queue task;
spawn worker_thread;
```

## System Statistics

| Metric | Value |
|---|---|
| Active `.hl` files | 164 (114 kernel + 27 userspace + 23 infra) |
| Total lines of code | ~38,500 (32,154 H-L + 6,352 PS1) |
| Archived files | 0 (legacy JS-origin files purged) |
| `.js` files | **0** |
| `.rs` files | **0** |
| `.json` files | **0** (replaced by `manifest.hl`) |
| External dependencies | **0** |
| Self-hosting | Yes (`hl-bootstrap.hl` compiles itself) |
| BIOS boot image | `hicos-hl.img` = 41,472 bytes (81 sectors, MBR 0x55AA) |
| UEFI boot image | `hicos-uefi.img` = 33 MB (GPT + ESP FAT16 + BOOTX64.EFI) |
| QEMU BIOS test | **42/42 PASS** (serial鈫扨CI鈫扸irtIO鈫扸ESA鈫扗HCP鈫扗NS鈫扲ing3鈫抯hell) |
| QEMU UEFI test | **3/3 PASS** (OVMF鈫扜PT鈫扙SP鈫扨E32+鈫抯erial+ConOut) |
| Full gate | **7/7 PASS** (workspace+boot+runtime+layout+binary+QEMU+bootstrap) |
| Build scripts | 17 PowerShell scripts in `scripts/` |
| Kernel modules | 114 in `bare-kernel/hl/` |
| Kernel functions | 995 |
| Shell commands (Layer C) | 55 (in shell.hl) |
| Shell commands (QEMU verified) | 18 (in hicos-hl.img) |
| H-L Language | Classes, inheritance, decorators, list comprehensions, generators, typed exceptions, type hints, deep destructuring |
| Kernel features | IDT, PIC, PIT, PS/2 keyboard+mouse, serial shell, VGA console |
| Interrupts | Timer (IRQ0鈫抳ec32), Keyboard (IRQ1鈫抳ec33), Mouse (IRQ12鈫抳ec44), LAPIC |
| Memory mgmt | kmalloc (1MB heap) + bitmap page alloc + 4-level VMM + Hilbert spatial alloc + mmap |
| Networking | VirtIO-net, ARP, IPv4/IPv6, UDP, TCP, ICMP, DHCP, DNS, NTP, TLS 1.3, HTTP/1.1, netfilter, BSD sockets |
| Storage | VirtIO-blk + USB mass storage + block cache (64 LRU) + ramfs + tmpfs + FAT16 + ext2 + ext4 + NTFS + VFS + sysfs + devfs + procfs + inotify + swap |
| IPC | Pipes (32) + message queues (16) + futex + poll/epoll + PTY (16) + shm (32) + eventfd (32) |
| Sync | Spinlock + mutex + futex + semaphore + rwlock |
| SMP | INIT-SIPI-SIPI, up to 16 cores, per-CPU LAPIC |
| Process model | 64 tasks, CFS scheduler, POSIX fork/exec/wait/pipe, signals, ELF64, ring 0鈫? |
| Syscalls | 30+ via SYSCALL/SYSRET + POSIX fork/exec/wait/pipe/dup2/mmap |
| Video | VESA 1024脳768脳32 + window manager + VT100 terminal + VirtIO-GPU 2D/3D |
| Audio | AC97 codec + mixer (8 streams, volume, pan, 44100Hz stereo) |
| USB | XHCI host + mass storage + HID + hub (5 levels, 8 hubs) |
| Security | TLS 1.3 (AES-128-GCM-SHA256, X25519), HTTPS client |
| Wireless | Wi-Fi 802.11 (scan/connect/WPA2) + Bluetooth 4.0 BLE (HCI/USB) |
| Users | Multi-user (32 max), uid/gid, rwx file permissions |
| GPU | VirtIO-GPU: 2D scanout, 3D virgl, multi-monitor (4 displays) |
| POSIX | fork/exec/wait/pipe/dup2/mmap/poll/socket/pty/shm, env vars, /proc, 15 compliance tests |

## Comparison

See [FIVE_OS_COMPARISON.md](FIVE_OS_COMPARISON.md) for an honest technical
comparison of HicOS vs Windows 11, Linux 6.x, macOS 14, and HarmonyOS 4 鈥?
including gap analysis, genuine advantages, and remaining gaps.

### Verified in QEMU (end-to-end)
- BIOS MBR boot 鈫?Stage2 long mode 鈫?Kernel init 鈫?20-subsystem serial output 鈫?Shell prompt
- VirtIO-blk: PCI detect 鈫?BAR0 鈫?virtqueue init 鈫?sector read/write verify
- VirtIO-net: PCI detect 鈫?BAR0 鈫?MAC read (52:54:00:12:34:56) 鈫?ARP broadcast
- Multitask: PIT 100Hz timer 鈫?dual-task A/B alternation
- UEFI: OVMF 鈫?GPT+CRC32 鈫?ESP FAT16 鈫?PE32+ BOOTX64.EFI 鈫?serial+ConOut
- FAT16: format 鈫?mkfile 鈫?ls 鈫?cat (end-to-end file creation and reading)
- Network: DHCP Discover鈫扥ffer鈫扞P acquired | Ping ICMP echo鈫抮eply | DNS A-record query鈫扞P
- VESA: 1024脳768脳32 mode set + LFB page table mapping + framebuffer read/write verify
- Ring3: IRETQ to user mode 鈫?SYSCALL print 'U3' 鈫?SYSCALL(0) return to kernel

### Remaining Gaps vs Mainstream
- No hardware GPU shader compilation (virgl passthrough only)
- No Btrfs / ZFS filesystem
- No USB 3.0 isochronous transfers
- No real hardware Wi-Fi firmware loading
- No physical hardware testing yet (QEMU only)

## Compiler Pipeline (Native x86_64 Execution)

The build chain is fully self-contained with native code generation:

1. `hl-bootstrap.hl` 鈥?Self-hosting H-L compiler (lexer 鈫?parser 鈫?AST)
2. **H-IR** 鈥?Intermediate representation with optimization passes
   - Constant folding, dead code elimination, strength reduction
3. **Register allocator** 鈥?Linear scan over 14 GP registers (RAX鈥揜15)
4. **x86_64 encoder** 鈥?126 instructions, all three modes (16/32/64-bit)
5. **System V AMD64 ABI** 鈥?RDI/RSI/RDX/RCX/R8/R9, 16-byte stack alignment
6. Boot image builder assembles MBR + stage2 + kernel
7. `hicos-hl.img` (6 KB) is the stage-0 bootstrap binary

No Cargo. No npm. No webpack. No Make. No Node.js.
The OS IS the compiler. The compiler IS the OS.

## License

See [LICENSE.txt](LICENSE.txt).

Local `hl-bootstrap` testing and build wrapper is available in repo root via `hl-bootstrap-build-test.ps1`. Phase 1 compilation pipeline (lexer) is complete:

```powershell
.\hl-bootstrap.cmd bare-kernel\hl\build.hl
.\hl-bootstrap.cmd bare-kernel\hl\test-runner.hl
