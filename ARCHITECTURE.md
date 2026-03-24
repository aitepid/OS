# HicOS Architecture

## Overview

HicOS is a three-layer experimental x86_64 OS written entirely in Hilbert-Lang.

| Layer | Medium | Current Role |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS image generation chain |
| B | `hl-bootstrap.hl` (4,301 lines) | Bootstrap compiler/interpreter/toolchain |
| C | `bare-kernel/hl/*.hl` (114 modules, 30,630 lines) | Kernel source → `kernel.bin` (23,183 bytes) |

## Boot Chain

### BIOS Path

```text
stage1 / MBR
→ stage2 (protected → long mode)
→ kernel.bin _start
→ kernel_entry.hl (9,410 lines, 301 functions)
→ kernel_init.hl (subsystem initialization)
→ shell.hl (63 commands + pipe)
```

### UEFI Path

```text
OVMF → GPT + ESP → BOOTX64.EFI → UEFI boot output
```

## Codebase Metrics (iteration 101, verified)

| Metric | Value |
|---|---:|
| Total `.hl` files | 176 |
| Root `.hl` files | 62 |
| Kernel modules | 114 |
| Total H-L lines | 40,073 |
| Kernel lines | 30,630 |
| Kernel functions | 1,407 |
| `scripts/*.ps1` | 22 |
| PS1 lines | 8,646 |
| Shell commands | 63 + pipe |
| Total repo files | 308 |

## Key Source Locations

- `bare-kernel/hl/kernel_entry.hl` — Kernel entry, interrupt init, command dispatch
- `bare-kernel/hl/kernel_init.hl` — Subsystem initialization sequence
- `bare-kernel/hl/shell.hl` — Serial shell (63 commands + pipe)
- `hl-bootstrap.hl` — Self-hosting compiler/toolchain (4,301 lines)
- `stdlib.hl` — Standard library (1,371 lines)
- `scripts/hl-bootstrap-build-test.ps1` — Primary build/test entry
- `scripts/rebuild-image.ps1` — BIOS image rebuilder
- `scripts/build-uefi-image.ps1` — UEFI image builder

## Algorithm Upgrades (iterations 81-101)

15 kernel modules upgraded across 4 phases:

- **Phase 1** (memory): buddy alloc, size-class freelist, hash+LRU cache, merge sort
- **Phase 2** (network): TCP Reno, DNS TTL cache, VFS trie
- **Phase 3** (multicore): ARP hash, inode cache, enhanced clock, per-CPU runqueue
- **Phase 4** (scheduling): MLFQ, demand paging+COW, SPSC pipe, TLS 1.3 state machine

## Verification

All gates pass as of iteration 101:
- `hl-bootstrap-build-test.ps1` ✅
- `boot-readiness.ps1` ✅
- `runtime-path-readiness.ps1` ✅
- `image-layout-readiness.ps1` ✅
- `qemu-smoke.ps1` ✅
