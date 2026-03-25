# HicOS Architecture

## Overview

HicOS is a three-layer experimental x86_64 OS written entirely in Hilbert-Lang.

| Layer | Medium | Current Role |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS image generation chain |
| B | `hl-bootstrap.hl` (4,567 lines) | Bootstrap compiler/interpreter/toolchain |
| C | `bare-kernel/hl/*.hl` (117 modules, 37,044 lines) | Kernel source → `kernel.bin` (27,970 bytes) |

## Boot Chain

### BIOS Path

```text
stage1 / MBR
→ stage2 (protected → long mode)
→ kernel.bin _start
→ kernel_entry.hl (10,575 lines, 305 functions)
→ kernel_init.hl (subsystem initialization)
→ shell.hl (64 commands + pipe) + kernel_entry.hl (70 commands)
```

### UEFI Path

```text
OVMF → GPT + ESP → BOOTX64.EFI → UEFI boot output
```

## Codebase Metrics (iteration 119, verified)

| Metric | Value |
|---|---:|
| Total `.hl` files | 180 |
| Root `.hl` files | 63 |
| Kernel modules | 117 |
| Total H-L lines | 47,950 |
| Root H-L lines | 10,906 |
| Kernel lines | 37,044 |
| Kernel functions (source) | 1,499 |
| `kernel_entry.hl` lines / functions | 10,575 / 305 |
| `hl-bootstrap.hl` lines | 4,567 |
| `stdlib.hl` lines | 1,545 |
| `scripts/*.ps1` | 22 |
| PS1 lines | 9,866 |
| Shell + kernel commands (unique) | 112 |
| HicOS_*.hl subsystem modules | 27 |
| test_*.hl / test-*.hl | 13 |
| Total repo files | 312 |

## Key Source Locations

- `bare-kernel/hl/kernel_entry.hl` — Kernel entry, interrupt init, command dispatch (10,575 lines, 305 fn, 70 commands)
- `bare-kernel/hl/kernel_init.hl` — Subsystem initialization sequence
- `bare-kernel/hl/shell.hl` — Serial shell (64 commands + pipe)
- `bare-kernel/hl/kinterp.hl` — Kernel interpreter (1,341 lines, 46 fn, tree-walk + IR VM)
- `hl-bootstrap.hl` — Self-hosting compiler/toolchain (4,567 lines, 208 fn)
- `stdlib.hl` — Standard library (1,545 lines, 143 fn)
- `scripts/hl-bootstrap-build-test.ps1` — Primary build/test entry
- `scripts/rebuild-image.ps1` — BIOS image rebuilder
- `scripts/build-uefi-image.ps1` — UEFI image builder

## Algorithm Upgrades (iterations 81-119)

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
- **Iteration 118**: `dns.hl` loopback self-test — query→mock response→parse→cache hit→expire→miss→static
- **Iteration 119**: `advanced_verify.hl` advanced feature baseline — eBPF/TLS1.3/QUIC selftest + shell/kernel command integration

## Verification

All gates pass as of iteration 119:
- `hl-bootstrap-build-test.ps1` ✅
- `boot-readiness.ps1` ✅
- `runtime-path-readiness.ps1` ✅
- `image-layout-readiness.ps1` ✅
- `release-validate.ps1` ✅ 18/18
