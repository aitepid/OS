# HicOS Architecture

HicOS is a bare-metal x86_64 operating system written entirely in H-L (Hilbert-Lang).
114 kernel modules, 27 userspace modules, 55 shell commands (Layer C), 18 QEMU-verified commands, zero external dependencies.
Dual-boot: BIOS/MBR (41 KB) + UEFI/GPT (33 MB, PE32+ BOOTX64.EFI).

## Boot Chain

### BIOS Path (verified: 42/42 QEMU checks)
```
stage1.hl (MBR 512B) → stage2.hl (real→protected→long mode)
  → kernel_entry.hl (IDT + PIC + PIT + keyboard + mouse)
  → kernel_init.hl (9-subsystem initialization)
  → shell.hl (interactive serial shell, 60 commands)
```

### UEFI Path (verified: 3/3 QEMU checks)
```
OVMF firmware → GPT (CRC32 + 128 entries + backup)
  → ESP FAT16 (\EFI\BOOT\BOOTX64.EFI)
  → PE32+ entry (serial 0x3F8 + EFI ConOut)
  → "HicOS UEFI OK" + "HicOS UEFI Boot OK"
```

## Memory Map

| Range | Size | Purpose |
|---|---|---|
| 0x000000–0x0FFFFF | 1 MB | Real mode, BIOS, boot stack |
| 0x100000–0x1FFFFF | 1 MB | Kernel code (.text) |
| 0x200000–0x2FFFFF | 1 MB | Page tables (PML4/PDPT/PD/PT) |
| 0x300000–0x3FFFFF | 1 MB | Kernel heap (kmalloc, first-fit) |
| 0x400000–0x7FFFFF | 4 MB | Page frame bitmap (128 MB physical) |
| 0x800000–0x83FFFF | 256 KB | Task table (64 tasks × 4 KB) |
| 0x840000–0x87FFFF | 256 KB | IPC message queues (16 × 16 KB) |
| 0x880000–0x8BFFFF | 256 KB | VFS inode/dentry cache |
| 0x8C0000–0x8FFFFF | 256 KB | FD tables (64 tasks × 16 FDs) |
| 0x900000–0x91FFFF | 128 KB | Pipe buffers (32 × 4 KB) |
| 0x920000–0x9FFFFF | 896 KB | Env vars, firmware staging |
| 0xFD000000 | 3 MB | VESA linear framebuffer (1024×768×32) |

## Subsystem Architecture (114 modules)

### Layer 0: Boot (3 modules)
stage1, stage2, kernel_entry

### Layer 1: Core Services (17 modules)
mem, serial, kmalloc, page_alloc, virt_mem, hilbert_alloc, alloc, swap,
timer, rtc, task, sched, sync, signal, exception, panic, env

### Layer 2: Hardware Drivers (15 modules)
scancode, mouse, framebuffer, vesa, pci, acpi, lapic, audio, mixer,
usb, usb_storage, usb_hid, usb_hub, virtio_net, virtio_blk

### Layer 3: Filesystems (14 modules)
ramfs, fat16, ext2, ext4, ntfs, tmpfs, block_cache, inotify, sysfs, vfs, devfs, procfs, elf, firmware

### Layer 4: Networking (14 modules)
net, arp, udp, tcp, icmp, dhcp, dns, ipv6, ntp, netfilter, http, tls, wifi, bluetooth

### Layer 5: Graphics & UI (4 modules)
gpu, multimon, wm, terminal

### Layer 6: Process & IPC (11 modules)
posix, mmap, poll, pty, socket, shm, eventfd, pipe, ipc, syscall, usermode

### Layer 7: Security & Users (5 modules)
tls, random, cgroup, users, smp

### Layer 8: Compiler & Codegen (4 modules)
ir, regalloc, abi, codegen

Pipeline: AST → H-IR → Optimize (const-fold, DCE, strength-reduce) → Linear-scan regalloc → x86_64
x86 encoder: 126 instructions (16-bit real, 32-bit protected, 64-bit long mode)

### Layer 9: System Services (6 modules)
power, syslog, watchdog, trace, hrtimer, kernel_init

### Layer 10: UEFI & Install (5 modules)
uefi_boot, gpt, secure_boot, installer, build

### Layer 11: Shell & Login (2 modules)
login, shell (60 commands, depends on everything)

### Meta (7 modules, not compiled into kernel)
build, boot, test, test-runner, lint, posix_test, kinterp

## Dependency Graph

See `bare-kernel/hl/kernel_init.hl` for the full 113-module dependency map.

## QEMU Verification Status

| Test Suite | Result | Checks |
|---|---|---|
| BIOS boot | ✅ PASSED | 42/42 (serial→PCI→VirtIO→VESA→shell→FAT16→DHCP→DNS→Ring3) |
| UEFI boot | ✅ PASSED | 3/3 (OVMF→GPT→ESP→PE32+) |
| Binary analysis | ✅ PASSED | 13/13 (MBR+Stage1+Stage2+Kernel) |
| Full gate | ✅ PASSED | 7/7 (all subsystems) |

## Subsystems
114 modules organized by dependency order in build.hl.
See kernel_init.hl for full module dependency map.