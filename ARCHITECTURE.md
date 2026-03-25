# HicOS Architecture

## Overview

HicOS is a three-layer experimental x86_64 OS written entirely in Hilbert-Lang.

| Layer | Medium | Current Role |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS image generation chain |
| B | `hl-bootstrap.hl` (4,301 lines) | Bootstrap compiler/interpreter/toolchain |
| C | `bare-kernel/hl/*.hl` (116 modules, 36,782 lines) | Kernel source → `kernel.bin` (27,865 bytes) |

## Boot Chain

### BIOS Path

```text
stage1 / MBR
→ stage2 (protected → long mode)
→ kernel.bin _start
→ kernel_entry.hl (10,515 lines, 305 functions)
→ kernel_init.hl (subsystem initialization)
→ shell.hl (63 commands + pipe)
```

### UEFI Path

```text
OVMF → GPT + ESP → BOOTX64.EFI → UEFI boot output
```

## Codebase Metrics (iteration 117, verified)

| Metric | Value |
|---|---:|
| Total `.hl` files | 179 |
| Root `.hl` files | 63 |
| Kernel modules | 116 |
| Total H-L lines | 47,655 |
| Kernel lines | 36,782 |
| Kernel functions (source) | 1,503 |
| `scripts/*.ps1` | 22 |
| PS1 lines | 8,646 |
| Shell commands | 63 + pipe |
| Total repo files | 311 |

## Key Source Locations

- `bare-kernel/hl/kernel_entry.hl` — Kernel entry, interrupt init, command dispatch
- `bare-kernel/hl/kernel_init.hl` — Subsystem initialization sequence
- `bare-kernel/hl/shell.hl` — Serial shell (63 commands + pipe)
- `hl-bootstrap.hl` — Self-hosting compiler/toolchain (4,301 lines)
- `stdlib.hl` — Standard library (1,371 lines)
- `scripts/hl-bootstrap-build-test.ps1` — Primary build/test entry
- `scripts/rebuild-image.ps1` — BIOS image rebuilder
- `scripts/build-uefi-image.ps1` — UEFI image builder

## Algorithm Upgrades (iterations 81-117)

19 kernel modules upgraded across 5 phases:

- **Phase 1** (memory): buddy alloc, size-class freelist, hash+LRU cache, merge sort
- **Phase 2** (network): TCP Reno, DNS TTL cache, VFS trie
- **Phase 3** (multicore): ARP hash, inode cache, enhanced clock, per-CPU runqueue
- **Phase 4** (scheduling): MLFQ, demand paging+COW, SPSC pipe, TLS 1.3 state machine
- **Phase 5** (isolation): futex hash queue, edge-trigger epoll, cgroup enforcement, eBPF VM

Phase 6 incremental runtime upgrades:

- **Iteration 109**: two-pass linker + builtin/fwd stubs, unresolved relocs `120 → 1`
- **Iteration 110**: `kinterp.hl` IR VM dual-engine execution path
- **Iteration 111**: `execve` + `argc/argv/envp` user stack setup
- **Iteration 112**: `quic.hl` QUIC v1 transport layer
- **Iteration 113**: `task.hl` ZOMBIE lifecycle + `waitpid(WNOHANG)`
- **Iteration 114**: `pty.hl` real ring-buffer IO + attach/detach/status
- **Iteration 116**: `kernel_entry.hl` `heval` command — kernel self-bootstrap prototype (lex→parse→eval)
- **Iteration 117**: `tcp.hl` loopback self-test — full 3-way handshake + data + close on 127.0.0.1

## Verification

All gates pass as of iteration 117:
- `hl-bootstrap-build-test.ps1` ✅
- `boot-readiness.ps1` ✅
- `runtime-path-readiness.ps1` ✅
- `image-layout-readiness.ps1` ✅
- `release-validate.ps1` ✅ 18/18
