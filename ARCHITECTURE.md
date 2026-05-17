# HicOS Architecture

## Overview

HicOS is a three-layer experimental x86_64 OS written entirely in Hilbert-Lang.

| Layer | Medium | Current Role |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS image generation chain |
| B | `hl-bootstrap.hl` (4,572 lines, 208 fn) | Bootstrap compiler/interpreter/toolchain |
| C | `bare-kernel/hl/*.hl` (274 modules, 3,757 fn) | Kernel source → `kernel.bin` (30,704 bytes) |

## Boot Chain

### BIOS Path

```text
stage1 / MBR
→ stage2 (protected → long mode)
→ kernel.bin _start
→ kernel_entry.hl (10,427 lines, 307 fn)
→ kernel_init.hl (subsystem initialization, 274 modules)
→ shell.hl (790 commands + pipe)
```

### UEFI Path

```text
OVMF → GPT + ESP → BOOTX64.EFI → UEFI boot output
```

## Codebase Metrics (post-iteration-288 sync)

| Metric | Value |
|---|---:|
| Total `.hl` files | 343 |
| Root `.hl` files | 69 |
| Kernel modules | 274 |
| Total H-L lines | ~100,400 |
| Kernel module functions | 3,757 |
| `kernel_entry.hl` lines | 10,427 (307 fn) |
| `shell.hl` lines | 4,510 |
| `kernel_init.hl` lines | 368 |
| `hl-bootstrap.hl` lines | 4,572 (208 fn) |
| `stdlib.hl` lines | 1,545 (143 fn) |
| `scripts/*.ps1` | 29 (11,193 lines) |
| Shell commands | 790 |
| HicOS_*.hl subsystem modules | 27 |
| IP-Protection files | 60 |
| `.md` documents | 10 |

## Key Source Locations

- `bare-kernel/hl/kernel_entry.hl` — Kernel entry, interrupt init, command dispatch (10,427 lines, 307 fn)
- `bare-kernel/hl/kernel_init.hl` — Subsystem initialization sequence (368 lines, 274 modules)
- `bare-kernel/hl/shell.hl` — Serial shell (4,510 lines, 790 commands)
- `bare-kernel/hl/kinterp.hl` — Kernel interpreter (tree-walk + IR VM)
- `bare-kernel/hl/kmod.hl` — Kernel module hot-patching (64 slots, 256 trampolines)
- `hl-bootstrap.hl` — Self-hosting compiler/toolchain (4,572 lines, 208 fn)
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

## Iteration 120: Kernel Module Hot-Patching

- `kmod.hl`: runtime module loading, unloading, and hot-replacement
- 64 module slots × 128 bytes, FNV-1a hash-based name lookup
- 256 trampoline slots: MOV RAX, imm64 + JMP RAX atomic redirect
- Reference counting with deferred unload (UNLOADING state)
- Dependency bitmask prevents premature unload of depended modules
- Module arena: 256 KB contiguous code region
- `kmod_replace()`: atomic version upgrade with trampoline redirect
- `kmod_selftest()`: 11-step self-test (load → find → activate → trampoline → hotpatch → refcount → replace → unload)
- Commands: `lsmod` (status) + `kmodtest` (self-test) in shell + kernel_entry

## Iteration 121: Bare-Metal Installation Foundation

- `vga_console.hl`: VGA text-mode console driver (80×25, 0xB8000)
  - Hardware cursor sync via CRTC 0x3D4/0x3D5
  - Scroll, backspace, tab, newline handling
  - Color attributes: banner/ok/err/warn
  - `dual_print()`: simultaneous serial + VGA output
- `ata_pio.hl`: ATA PIO disk driver for real IDE/SATA hardware
  - Primary/Secondary × Master/Slave (4-device scan)
  - 28-bit LBA read/write, IDENTIFY DEVICE, CACHE FLUSH
- `installer.hl` v6.0: tri-backend disk abstraction
  - Auto-detect priority: ATA PIO → AHCI → VirtIO-blk
  - Unified `installer_disk_read/write` dispatcher
- `rebuild-image.ps1`: native kernel VGA text dual-output
  - Boot messages + shell prompt mirrored to VGA text buffer

## Iteration 122: Native VGA Shell Interaction + Self-Install Image

- `rebuild-image.ps1`: native `vga_putchar` subroutine (x86_64 machine code)
  - Character echo → VGA text buffer (typed input visible on monitor)
  - Backspace → VGA cursor rewind + character erase
  - Enter → VGA newline, command output to VGA
  - 11 key boot messages converted to serial+VGA dual output
- `self_image.hl`: kernel self-image awareness
  - Kernel tracks its own image layout (address/size/sectors)
  - `self_install_to_disk()`: sector-by-sector image write to target

## Iteration 123: VGA Full Interaction Loop + USB Keyboard

- `rebuild-image.ps1`: real VGA scroll (`rep movsb` 3840 bytes + clear row 24)
  - Both LF and col-wrap paths now trigger full scroll
- `kernel_entry.hl`: `_ke_putc()` dual output — ALL H-L command output to VGA
- `usb_kbd.hl`: USB HID keyboard driver (Boot Protocol)
  - HID Usage ID → ASCII mapping (letters/numbers/symbols/Shift)
  - Auto-detect HID class=3/subclass=1/protocol=1
  - Poll-based input with modifier key tracking

## Iterations 124-130: UI Phase 1-6 — Complete Graphical Desktop

10 UI modules forming a full desktop environment:

| Module | Role |
|---|---|
| `ui_theme.hl` | Slate color palette, spacing constants, 10 theme accessors |
| `ui_controls.hl` | Buttons, labels, progress bars, separators, badges, hit-test |
| `ui_dialog.hl` | Modal dialogs: INFO/CONFIRM/WARNING/ERROR + keyboard/mouse nav |
| `ui_terminal.hl` | Graphical terminal: 24×80 char grid, cursor, scroll, input |
| `ui_installer.hl` | 5-step graphical installer wizard with disk detection + progress |
| `ui_sysmon.hl` | System monitor: uptime, memory bar, task counts, window stats |
| `ui_notify.hl` | Toast notifications: 4 types × 4 concurrent, auto-dismiss |
| `ui_desktop.hl` | Desktop orchestration: topbar clock, dock launchers, window titles |
| `wm.hl` | Window manager: title text, drag, minimize, taskbar, click routing |
| `HicOS_UIServer.hl` | UI server: IPC protocol, focus events, desktop tick integration |

## Iterations 247-288: Advanced Data Structures & Graph Algorithms (42 modules)

Key additions organized by category:

| Category | Modules |
|---|---|
| Probabilistic | Bloom Filter, HyperLogLog, Count-Min Sketch, Cuckoo Filter, t-Digest, Reservoir |
| Trees | Treap, Leftist Heap, KD-Tree, Segment Tree, Fenwick Tree, Sparse Table |
| String | Aho-Corasick, KMP/Z/Rabin-Karp, Suffix Array |
| Graph | Dijkstra SSSP, Kahn Topo Sort, Bellman-Ford, Consistent Hash |
| Geometry | Convex Hull, Interval Tree |
| ML Basics | Neural Network, Attention, Matrix |
| Misc | CRDT, Skip List, LRU, DSU, Merkle Tree, Wavelet |

### Graph Algorithm Modules (iter 286-288)

- **`dijkstra.hl`**: O(V²) SSSP, adjacency matrix, 32 vertices, linear min-search
- **`topological_sort.hl`**: Kahn BFS O(V+E), in-degree from adjacency matrix, cycle detection
- **`bellman_ford.hl`**: O(VE) edge-list relaxation, negative weights, negative cycle detection

## Verification

All gates pass on the current iteration-288 baseline:
- `hl-bootstrap-build-test.ps1` ✅ (274 modules, 3,757 fn)
- `validate-workspace.ps1` ✅ (343 HL, 274 kernel, 0 stub)
- `runtime-path-readiness.ps1` ✅ (IDT/PIT/KBD + SYSCALL + 网络 + eBPF/TLS/QUIC)
- `release-validate.ps1` ✅ 18/18
