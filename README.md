# HicOS

A bare-metal experimental x86_64 operating system written entirely in **Hilbert-Lang (H-L)**, a self-designed language. Zero external dependencies — no C, no Rust, no JSON/YAML/npm. The compiler, linker, and interpreter are self-hosted in H-L; the kernel modules are H-L. The only non-H-L code is the boot image emitter (`scripts/rebuild-image.ps1`), which writes raw x86_64 machine code.

Boots in QEMU and presents an interactive **serial-console shell**.

## Quick Start

### Build the boot image

Requires PowerShell 7:

```powershell
pwsh -NoProfile -Command '. ./scripts/rebuild-image.ps1'
```

Produces `hicos-hl.img` (MBR + Stage 2 + kernel, 57,856 B).

### Run in QEMU

```bash
qemu-system-x86_64 -drive format=raw,file=hicos-hl.img -serial stdio -display none -m 256M
```

You get a shell prompt:

```
HicOS 6.0 -- Hilbert-Lang Kernel
=== Kernel Init ===
  [ok] Serial: COM1 38400 8N1
  [ok] PIC: 8259A remapped
  [ok] PIT: 100 Hz timer
  [ok] IDT: 256 vectors
  [ok] Scancode: PS/2 loaded
  [ok] Timer ticks: active
  [ok] PCI: 4 device(s)
  [ok] Memory: 8MB identity mapped
  [ok] VESA: 1024x768x32 LFB=FD000000
  [ok] VESA: framebuffer write/read verified
  [ok] SYSCALL: configured
  [ok] Modules: 113 kernel, 27 userspace
=== Boot Complete ===
HicOS>
```

## Shell Commands

The serial shell supports interactive editing (backspace/delete, Enter) and ~100 commands:

```
System:   help ver reboot shutdown halt clear
Info:     free ps lspci uptime
Disk:     format ls cat mkfile hexdump
Net:      dhcp ping ifconfig nslookup
Graphics: vesa
Kernel:   ring3
```

## Codebase

| Metric | Value |
|---|---:|
| H-L source files | 446 |
| Kernel modules (`bare-kernel/hl/`) | 397 |
| Top-level subsystems (`HicOS_*.hl`) | 28 |
| H-L total lines | ~116,000 |
| Shell commands | ~100 |
| Boot image | 57,856 B |
| PowerShell scripts | 35 |
| External dependencies | 0 |

### Layout

```
HicOS/
├── bare-kernel/hl/    397 H-L kernel modules (drivers, protocols, algorithms, filesystems)
├── scripts/           PowerShell build/test/validation scripts (image emitter, pipeline)
├── HicOS_*.hl         28 top-level subsystem stubs (desktop, window manager, network, …)
├── hl-bootstrap.hl    self-hosting H-L compiler / interpreter / linker / REPL
├── stdlib.hl          H-L standard library
├── manifest.hl        project metadata
├── hicos-hl.img       built boot image
└── BOOTX64.EFI        UEFI boot entry
```

## Architecture

Three layers:

1. **Layer A** — `scripts/rebuild-image.ps1`: emits raw x86_64 machine code into `hicos-hl.img` (MBR + Stage 2 + kernel). The only non-H-L code in the repo, needed because no H-L code can run before the kernel is up.
2. **Layer B** — `hl-bootstrap.hl`: the self-hosted toolchain (compiler, interpreter, linker, REPL).
3. **Layer C** — `bare-kernel/hl/*.hl`: the kernel — serial driver, IDT, PIC/PIT, PS/2 scancodes, PCI scan, VESA framebuffer, and the serial shell.

### Boot chain (BIOS path)

```
MBR (sector 0)                 ; Stage 1, emitted by Layer A
  └─ loads Stage 2 to 0x8000
Stage 2 (sector 1)             ; real → protected → long mode + VBE 1024×768×32
  └─ jumps to kernel at 0x100000
Kernel (sectors 2+)            ; native x86_64
  └─ serial init, IDT, PIC/PIT, PS/2, PCI scan
      └─ subsystem init
          └─ serial shell
```

## Memory Layout

| Address | Size | Purpose |
|---|---|---|
| 0x7C00 | 512 B | MBR / Stage 1 load address |
| 0x8000 | 512 B | Stage 2 load address |
| 0x100000 | ~30 KB | Kernel load address |
| 0x300000–0x3000FF | 256 B | Shared kernel control block (ticks, scancodes, command buffer) |
| 0xFD000000 | LFB | VESA linear framebuffer |

## Known Limits

- The shipped `hicos-hl.img` contains a **handwritten machine-code kernel** emitted by `rebuild-image.ps1`. The H-L compiler pipeline (`scripts/hl-compile-pipeline.ps1`) can build `kernel.bin` from `bare-kernel/hl/*.hl`, but its output is not yet linked into the boot image — closing this gap is the current focus.
- Boot is BIOS-based; `BOOTX64.EFI` exists but the UEFI path is not fully validated.
- Network commands are present in the shell but depend on device setup in QEMU.

## License

See [LICENSE.txt](LICENSE.txt).
