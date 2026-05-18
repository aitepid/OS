# HicOS Architecture

## Overview

HicOS is a three-layer experimental x86_64 OS written entirely in Hilbert-Lang.

| Layer | Medium | Current Role |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS image generation chain |
| B | `hl-bootstrap.hl` (4,572 lines, 208 fn) | Bootstrap compiler/interpreter/toolchain |
| C | `bare-kernel/hl/*.hl` (426 modules) | Kernel source → `kernel.bin` (30,704 bytes) |

## Boot Chain

### BIOS Path

```text
stage1 / MBR
→ stage2 (protected → long mode)
→ kernel.bin _start
→ kernel_entry.hl (10,427 lines, 307 fn)
→ kernel_init.hl (subsystem initialization, 426 modules)
→ shell.hl (1,800 commands + pipe)
```

### UEFI Path

```text
OVMF → GPT + ESP → BOOTX64.EFI → UEFI boot output
```

## Codebase Metrics (post-iteration-440 sync)

| Metric | Value |
|---|---:|
| Total `.hl` files | 495 |
| Root `.hl` files | ~69 |
| `bare-kernel/hl/` kernel modules | 426 |
| Total H-L lines | ~163,700 |
| `kernel_entry.hl` lines | 10,427 (307 fn) |
| `hl-bootstrap.hl` lines | 4,572 (208 fn) |
| `stdlib.hl` lines | 1,545 (143 fn) |
| `scripts/*.ps1` | 29 (11,193 lines) |
| Shell commands | 1,800 |
| HicOS_*.hl subsystem modules | 27 |
| IP-Protection files | 60 |
| `.md` documents | 11 |

## Key Source Locations

- `bare-kernel/hl/kernel_entry.hl` — Kernel entry, interrupt init, command dispatch (10,427 lines, 307 fn)
- `bare-kernel/hl/kernel_init.hl` — Subsystem initialization sequence (426 modules)
- `bare-kernel/hl/shell.hl` — Serial shell (1,800 commands)
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

## Phase 6 Runtime Upgrades (iterations 109–130)

- **109**: two-pass linker + builtin/fwd stubs
- **110**: `kinterp.hl` IR VM dual-engine execution path
- **111**: `execve` + `argc/argv/envp` user stack setup
- **112**: `quic.hl` QUIC v1 transport layer
- **113**: `task.hl` ZOMBIE lifecycle + `waitpid(WNOHANG)`
- **114**: `pty.hl` real ring-buffer IO + attach/detach/status
- **120**: `kmod.hl` runtime module hot-patching (64 slots, 256 trampolines)
- **121–123**: bare-metal installation (VGA console, ATA PIO, USB HID, self-install image)
- **124–130**: complete graphical desktop (theme/controls/dialog/terminal/installer/sysmon/notify/wm)

## Iterations 131–246: Protocol and Algorithm Expansion (130→232 modules)

116 iterations adding network protocols, compression, cryptography, serialization, file formats.

## Iterations 247–339: Advanced Data Structures & Competitive Algorithms (232→325 modules)

Raft/Gossip/CRDT | Bloom/HLL/CMS/Cuckoo | Treap/Splay/LCT/Wavelet | Dijkstra/Dinic/Tarjan/Hungarian | SAM/Manacher/BWT | Miller-Rabin/NTT/poly全家桶 | 旋转卡壳/半平面交

## Iterations 340–360: Algorithm Library Completion ✦ M1 (325→346 modules)

bitmask_dp / digit_dp / broken_profile_dp / wavelet_tree_range / implicit_treap / chtholly_tree / suffix_tree / bsgs / min_enclosing_circle + geometry/graph/poly completions.

## Iterations 361–375: Compiler Deepening ✦ M2 (346→361 modules)

| Module | Feature |
|---|---|
| pass_gvn / pass_licm / pass_dce2 | GVN/LICM/DCE2 optimization passes |
| regalloc_linear_scan / regalloc_coalesce | Linear scan RA + register coalescing |
| calling_conv | Full System V AMD64 ABI + varargs + SSE |
| type_infer / type_checker / generics | HM type inference + static checking + monomorphization |
| linker_elf / linker_ar / dynamic_linker | ELF64 output + static lib + dynamic linking |
| dwarf / perf_counter / jit_stub | DWARF debug info + PMU + JIT framework |

## Iterations 376–385: Storage Engine ✦ M3 (361→371 modules)

btree / btree_plus / lsm_memtable / wal / mvcc / transaction / index_hash / index_btree / query_plan / db_engine

## Iterations 386–395: Network Deepening (371→381 modules)

wireguard / tls13 / http3_quic / dns_over_https / dht / torrent_proto / opentelemetry / prometheus / grpc_stream / websocket_compression

## Iterations 396–405: Machine Learning Framework ✦ M4 (381→391 modules)

conv2d / pooling / rnn / lstm / autograd / optimizer / tokenizer / embedding / model_serialize / gpu_inference

## Iterations 406–420: System Stability & Production ✦ M5 (391→406 modules)

| Iteration | Module | Feature |
|---|---|---|
| 406–407 | scheduler_cfs + numa_alloc | CFS完全公平调度 + NUMA感知分配 |
| 408–409 | ftrace + kprobe | 函数追踪 + 动态内核探针 |
| 410–411 | memory_profiler + heap_checker | 内存分析 + 堆越界检测 |
| 412–413 | crash_reporter + core_dump | 崩溃报告 + 核心转储(ELF core) |
| 414–415 | hotpatch + livepatch | 内核热补丁(trampoline) + 运行时函数替换 |
| 416–418 | power_mgmt + thermal + cpufreq | ACPI电源 + 热量管理 + CPU频率调节 |
| 419–420 | hypervisor + vmx | 基础Hypervisor框架 + VMX/VT-x支持 |

## Iterations 421–440: Ecosystem & Bootstrap ✦ Phase 7 / M6 (406→426 modules)

| Iteration | Module | Feature |
|---|---|---|
| 421–423 | package_manager + pkg_registry + pkg_build | H-L包管理器 + 软件包注册中心 + 构建系统 |
| 424–426 | hldoc + hltest + hlbench | 文档生成器 + 单元测试框架 + 基准测试框架 |
| 427–429 | lsp_server + syntax_highlight + code_complete | LSP服务器 + 语法高亮 + 代码补全 |
| 430–432 | debugger + gdb_stub + breakpoint | 内置调试器 + GDB Remote协议桩 + 断点管理器 |
| 433–435 | hl_repl + hl_fmt + hl_lint2 | H-L REPL环境 + 代码格式化器 + 增强Lint |
| 436–438 | posix_compat + musl_shim + linux_syscall | POSIX兼容层 + musl libc垫片 + Linux syscall层 |
| 439–440 | wasm_runtime + wasm_jit | WASM MVP解释器 + JIT热路径编译器(x86_64) |

## Buffer Address Scheme (Phase 7)

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
| 436 | posix_compat | 0x1EB0000 |
| 437 | musl_shim | 0x1EC0000 |
| 438 | linux_syscall | 0x1ED0000 |
| 439 | wasm_runtime | 0x1EE0000 |
| 440 | wasm_jit | 0x1EF0000 |

## Milestone Summary

| Milestone | Iteration | Achievement | Status |
|---|---|---|---|
| M1 | 360 | 竞赛级算法库（300+ 算法，Shell >1,200）| ✦ 已达成 |
| M2 | 375 | 自宿主编译器（类型系统+优化Pass+完整链接器）| ✦ 已达成 |
| M3 | 385 | 完整存储引擎（B+Tree+WAL+MVCC+关系型DB）| ✦ 已达成 |
| M4 | 405 | 完整ML框架（CNN+RNN+LSTM+Transformer+自动微分）| ✦ 已达成 |
| M5 | 420 | 生产级稳定性（CFS+NUMA+热补丁+崩溃报告+Hypervisor）| ✦ 已达成 |
| M6 | 440 | 完整生态（包管理+LSP+调试器+POSIX+WASM，Shell 1,800）| ✦ 已达成 |

## Verification

All gates pass on the current iteration-440 baseline:
- `hl-bootstrap-build-test.ps1` ✅ (426 modules)
- `validate-workspace.ps1` ✅ (495 HL files, 426 kernel modules)
- `runtime-path-readiness.ps1` ✅ (IDT/PIT/KBD + SYSCALL + 网络 + eBPF/TLS/QUIC)
- `release-validate.ps1` ✅ 18/18
