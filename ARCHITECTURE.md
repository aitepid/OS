# HicOS Architecture

## Overview

HicOS is a three-layer experimental x86_64 OS written entirely in Hilbert-Lang.

| Layer | Medium | Current Role |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS image generation chain |
| B | `hl-bootstrap.hl` (4,572 lines, 208 fn) | Bootstrap compiler/interpreter/toolchain |
| C | `bare-kernel/hl/*.hl` (418 modules) | Kernel source → `kernel.bin` (30,704 bytes) |

## Boot Chain

### BIOS Path

```text
stage1 / MBR
→ stage2 (protected → long mode)
→ kernel.bin _start
→ kernel_entry.hl (10,427 lines, 307 fn)
→ kernel_init.hl (subsystem initialization, 418 modules)
→ shell.hl (1,744 commands + pipe)
```

### UEFI Path

```text
OVMF → GPT + ESP → BOOTX64.EFI → UEFI boot output
```

## Codebase Metrics (post-iteration-432 sync)

| Metric | Value |
|---|---:|
| Total `.hl` files | 487 |
| Root `.hl` files | ~72 |
| Kernel modules | 418 |
| Total H-L lines | ~159,650 |
| `kernel_entry.hl` lines | 10,427 (307 fn) |
| `hl-bootstrap.hl` lines | 4,572 (208 fn) |
| `stdlib.hl` lines | 1,545 (143 fn) |
| `scripts/*.ps1` | 29 (11,193 lines) |
| Shell commands | 1,744 |
| HicOS_*.hl subsystem modules | 27 |
| IP-Protection files | 60 |
| `.md` documents | 11 |

## Key Source Locations

- `bare-kernel/hl/kernel_entry.hl` — Kernel entry, interrupt init, command dispatch (10,427 lines, 307 fn)
- `bare-kernel/hl/kernel_init.hl` — Subsystem initialization sequence (418 modules)
- `bare-kernel/hl/shell.hl` — Serial shell (1,744 commands)
- `bare-kernel/hl/kinterp.hl` — Kernel interpreter (tree-walk + IR VM)
- `bare-kernel/hl/kmod.hl` — Kernel module hot-patching (64 slots, 256 trampolines)
- `hl-bootstrap.hl` — Self-hosting compiler/toolchain (4,572 lines, 208 fn)
- `stdlib.hl` — Standard library (1,545 lines, 143 fn)
- `scripts/hl-bootstrap-build-test.ps1` — Primary build/test entry
- `scripts/rebuild-image.ps1` — BIOS image rebuilder
- `scripts/build-uefi-image.ps1` — UEFI image builder

## Algorithm Upgrades (iterations 81–119)

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
- **Iteration 116**: `kernel_entry.hl` `heval` command — kernel self-bootstrap prototype
- **Iteration 117**: `tcp.hl` loopback self-test — full 3-way handshake + data + close
- **Iteration 118**: `dns.hl` loopback self-test — query→mock response→parse→cache
- **Iteration 119**: `advanced_verify.hl` — eBPF/TLS1.3/QUIC selftest

## Iteration 120: Kernel Module Hot-Patching

- `kmod.hl`: runtime module loading, unloading, and hot-replacement
- 64 module slots × 128 bytes, FNV-1a hash-based name lookup
- 256 trampoline slots: MOV RAX, imm64 + JMP RAX atomic redirect
- Reference counting with deferred unload (UNLOADING state)
- Dependency bitmask prevents premature unload of depended modules

## Iterations 121–123: Bare-Metal Installation Foundation

- `vga_console.hl`: VGA text-mode console driver (80×25, 0xB8000)
- `ata_pio.hl`: ATA PIO disk driver (Primary/Secondary × Master/Slave, 28-bit LBA)
- `installer.hl` v6.0: tri-backend disk abstraction (ATA PIO → AHCI → VirtIO-blk)

## Iterations 124–130: UI Phase 1–6 — Complete Graphical Desktop

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

## Iterations 131–246: Protocol and Algorithm Expansion (130→232 modules)

116 iterations adding:
- **Network protocols**: HTTP/WS/SMTP/POP3/IMAP/IRC/FTP/MQTT/SIP/RTSP/RTP/STUN/SOCKS5/LDAP/RADIUS
- **Compression**: LZ4/ZLIB/LZMA/Bzip2/Snappy/Zstd/Brotli
- **Cryptography**: AES/ChaCha20/RSA/Ed25519/SM3/SM4/BLAKE2/HMAC/PBKDF2/scrypt/Argon2/bcrypt
- **Serialization**: Protobuf/Avro/CBOR/ASN.1 DER
- **File formats**: BMP/GIF/WAV/PNG/JPEG

## Iterations 247–339: Advanced Data Structures & Competitive Algorithms (232→325 modules)

| Category | Modules |
|---|---|
| Distributed/Consensus | Raft, Gossip, CRDT, gRPC, X.509, PNG/JPEG |
| Probabilistic | Bloom Filter, HyperLogLog, Count-Min Sketch, Cuckoo, t-Digest, Reservoir |
| Trees | Treap, Splay, LCT, Skip List, Leftist Heap, KD-Tree, Wavelet, Fenwick, Segment Tree |
| Graph | Dijkstra/Bellman-Ford/Floyd/A*/MaxFlow/BiMatch/Tarjan/Euler/2-SAT/Hungarian |
| Graph Advanced | Hopcroft, MinCostFlow, 重心分解/HLD/LCA/虚树/支配树 |
| String | SAM, Manacher, Eertree, BWT, Lyndon, Z-function, KMP |
| Math | Miller-Rabin, Pollard-Rho, NTT, poly全家桶, BSGS, 线性基 |
| Geometry | Convex Hull, 旋转卡壳, 半平面交, 最小圆覆盖 |
| DP | 状压DP, 数位DP, Knuth, 分治DP, 轮廓线DP, 回文划分DP |

## Iterations 340–360: Algorithm Library Completion ✦ M1

21 final algorithm modules: bitmask_dp / digit_dp / broken_profile_dp / wavelet_tree_range / implicit_treap / chtholly_tree / suffix_tree / bsgs / min_enclosing_circle + geometry/graph/poly completions.

## Iterations 361–375: Compiler Deepening ✦ M2

15 compiler modules: pass_gvn / pass_licm / pass_dce2 / regalloc_linear_scan / regalloc_coalesce / calling_conv / type_infer / type_checker / generics / linker_elf / linker_ar / dynamic_linker / dwarf / perf_counter / jit_stub

## Iterations 376–385: Storage Engine ✦ M3

10 storage modules: btree / btree_plus / lsm_memtable / wal / mvcc / transaction / index_hash / index_btree / query_plan / db_engine

## Iterations 386–395: Network Deepening

10 network modules: wireguard / tls13 / http3_quic / dns_over_https / dht / torrent_proto / opentelemetry / prometheus / grpc_stream / websocket_compression

## Iterations 396–405: Machine Learning Framework ✦ M4

10 ML modules: conv2d / pooling / rnn / lstm / autograd / optimizer / tokenizer / embedding / model_serialize / gpu_inference

## Iterations 406–420: System Stability & Production ✦ M5

15 production modules:

| Iteration | Module | Feature |
|---|---|---|
| 406–407 | scheduler_cfs + numa_alloc | CFS完全公平调度 + NUMA感知分配 |
| 408–409 | ftrace + kprobe | 函数追踪 + 动态内核探针 |
| 410–411 | memory_profiler + heap_checker | 内存分析 + 堆越界检测 |
| 412–413 | crash_reporter + core_dump | 崩溃报告 + 核心转储(ELF core) |
| 414–415 | hotpatch + livepatch | 内核热补丁(trampoline) + 运行时函数替换 |
| 416–418 | power_mgmt + thermal + cpufreq | ACPI电源 + 热量管理 + CPU频率调节 |
| 419–420 | hypervisor + vmx | 基础Hypervisor框架 + VMX/VT-x支持 |

## Iterations 421–432: Ecosystem & Bootstrap ✦ Phase 7 (in progress)

12 ecosystem modules:

| Iteration | Module | Feature |
|---|---|---|
| 421–423 | package_manager + pkg_registry + pkg_build | H-L包管理器 + 软件包注册中心 + 构建系统 |
| 424–426 | hldoc + hltest + hlbench | 文档生成器 + 单元测试框架 + 基准测试框架 |
| 427–429 | lsp_server + syntax_highlight + code_complete | LSP服务器 + 语法高亮 + 代码补全 |
| 430–432 | debugger + gdb_stub + breakpoint | 内置调试器 + GDB Remote协议桩 + 断点管理器 |

## Buffer Address Scheme

Each module is allocated a 64 KB buffer region. Starting from iter 421:

| Iteration | Module | Buffer Address |
|---|---|---|
| 421 | package_manager | 0x1DC0000 |
| 422 | pkg_registry | 0x1DD0000 |
| 423 | pkg_build | 0x1DE0000 |
| 424 | hldoc | 0x1DF0000 |
| 425 | hltest | 0x1E00000 |
| 426 | hlbench | 0x1E10000 |
| 427 | lsp_server | 0x1E20000 |
| 428 | syntax_highlight | 0x1E30000 |
| 429 | code_complete | 0x1E40000 |
| 430 | debugger | 0x1E50000 |
| 431 | gdb_stub | 0x1E60000 |
| 432 | breakpoint | 0x1E70000 |
| 433 | hl_repl | 0x1E80000 |
| 434 | hl_fmt | 0x1E90000 |
| 435 | hl_lint2 | 0x1EA0000 |

## Verification

All gates pass on the current iteration-432 baseline:
- `hl-bootstrap-build-test.ps1` ✅ (418 modules)
- `validate-workspace.ps1` ✅ (487 HL, 418 kernel, 0 stub)
- `runtime-path-readiness.ps1` ✅ (IDT/PIT/KBD + SYSCALL + 网络 + eBPF/TLS/QUIC)
- `release-validate.ps1` ✅ 18/18
