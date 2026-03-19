# HicOS Changelog

## v5.0 (Current)

164 active .hl files, 114 kernel modules, 55 shell commands (Layer C), 18 QEMU-verified commands, 0 external deps.
Dual-boot: BIOS 42/42 PASS + UEFI 3/3 PASS. Full gate 7/7 PASS.
Image: 41,472 bytes (81 sectors). Code: ~38,500 lines (32,154 H-L + 6,352 PS1).

### Iterations 18-21: Network + Graphics + User Mode (QEMU verified)
- **Iteration 18: DHCP + Ping + DNS + ifconfig**
  - `dhcp`: VirtIO-net TX Discover → RX Offer → yiaddr → IP stored at 0x3002A8
  - `ping`: ARP refresh → ICMP Echo Request (IP checksum) → poll Reply → "reply received"
  - `nslookup`: UDP DNS A-record query for example.com → parse answer → decimal IP
  - `ifconfig`: MAC display + DHCP IP 3-digit-per-octet decimal output
  - VirtIO-net RX: used ring polling + desc_id → buffer → EtherType/Protocol dispatch
- **Iteration 20: VESA 1024×768×32 framebuffer**
  - VBE mode set: Stage2 real mode INT 10h AX=4F01/4F02, mode 0x118 + LFB
  - Page table mapping: PDPT[3]→PD[488-489], 2×2MB large pages at 0xFD000000
  - `vesa` command: blue fill + white banner (624×40 pixels)
- **Iteration 21: Ring3 user mode switch**
  - SYSCALL MSRs: STAR (GDT segments) + LSTAR (entry) + FMASK (clear IF)
  - TSS: 104-byte TSS + GDT descriptor + LTR
  - `ring3`: IRETQ→0x8000 Ring3 → SYSCALL(1,'U') → SYSCALL(1,'3') → SYSCALL(0)→kernel
- **Shell commands expanded**: 12 → 18 (`ifconfig` `dhcp` `ping` `nslookup` `vesa` `ring3`)
- **rebuild-image.ps1**: 1,431 → 3,676 lines
- **hl-bootstrap.hl**: 4,487 → 4,630 lines (206 functions, 7 quadrants)
- **Gate test fix**: net test timeouts adjusted (DHCP 8s, DNS 8s) → 42/42 PASS

### Compilation Pipeline Initiative
- **Phase 1 PASSED**: 114 modules, 101,392 tokens, 995 functions — all tokenized ✓
- **hl-compile-pipeline.ps1**: 宿主侧完整 H-L 词法分析器 (关键字/字符串/注释/运算符)
  - 括号平衡校验 + 函数计数 + per-module 统计
  - `hl-bootstrap compile` 独立入口命令
  - 集成到 build 流程 (build → compile → rebuild)
- **PIPELINE_PLAN.hl**: 六阶段编译管线打通策划案 (Phase 1-6)
- **cmd_build()**: 模块列表从 55 扩展到完整 111 + 3 boot chain = 114 个 (依赖顺序)
- **build_kernel()**: 添加 pipeline 注释和模块计数感知
- **ir.hl**: 新增 AST→IR 降低层 (ir_lower_expr/ir_lower_stmt/ir_lower_module)
  - 支持: Num, Bool, Nil, Str, Var, BinOp (16 ops), Unary, Call
  - 支持: Let, Assign, FnDef, Return, If, While, Print, Quadrant
- **linker.hl**: 新建跨模块链接器 (符号表 + 重定位 + 两遍链接)
  - Pass 1: 收集符号 + 计算模块偏移
  - Pass 2: 解析 rel32/abs64 重定位
  - 字符串常量池 (.rodata 段)
- **Version bump**: banner/CLI/kernel_init 统一为 v5.0 (114 modules)

### QEMU End-to-End Verification (Iterations 11-15)
- **BIOS Boot 21/21**: MBR→Stage2→Long Mode→Kernel→9 subsystems→Shell prompt
- **VirtIO-blk**: PCI detect → BAR0 → virtqueue → sector read/write verify
- **VirtIO-net**: PCI detect → BAR0 → MAC read (52:54:00:12:34:56) → ARP broadcast
- **Multitask**: PIT 100Hz timer → dual-task A/B alternation verified
- **UEFI Boot 3/3**: OVMF → GPT+CRC32 → ESP FAT16 → PE32+ BOOTX64.EFI → serial+ConOut

### UEFI Support
- **build-uefi-image.ps1**: Generates complete UEFI bootable disk image from scratch
  - PE32+ EFI application (DOS header + COFF + Optional Header + .text + .reloc)
  - GPT with CRC32 checksums, 128 partition entries, backup GPT header/entries
  - FAT16 ESP filesystem (BPB + dual FAT + \EFI\BOOT\BOOTX64.EFI + startup.nsh)
- **BOOTX64.EFI**: 1,536 bytes, serial 0x3F8 output + EFI ConOut->OutputString
- **qemu-uefi-test.ps1**: Automated OVMF + QEMU UEFI boot test

### Image Rebuild
- **rebuild-image.ps1**: Correct Stage2 far JMP (0x66 prefix) + INT13h LBA extended read
- **hicos-hl.img**: 29,184 bytes (57 sectors) — fully functional BIOS boot
- **hicos-uefi.img**: 33 MB GPT disk with ESP FAT16

### New Kernel Modules
- **kinterp.hl**: In-kernel H-L interpreter (Lexer→Parser→Tree-walk evaluator, 689 lines)
- **nvme.hl**: NVMe 1.4 driver (Admin + I/O queue framework)
- **errno.hl**: POSIX error codes (35 errno values)
- **font.hl**: 8x16 bitmap font renderer

### Infrastructure
- **full-gate.ps1**: 7-check gate (workspace+boot+runtime+layout+binary+QEMU+bootstrap)
- **boot-binary-analysis.ps1**: 13-check MBR+Stage1+Stage2+Kernel binary validation
- 18 PowerShell build/test scripts total

## v4.5

100 kernel modules, 50 shell commands, 184 .hl files, 0 external deps.

### epoll: Red-Black Tree I/O Multiplexing (Phase 1.1)
- **poll.hl**: Complete rewrite — old O(n) stub replaced with production epoll
- **Red-Black Tree**: Array-backed RB tree for O(log n) fd insert/search/modify
  - Full left/right rotation + 3-case insert fixup (recolor, rotate-parent, rotate-grandparent)
  - Mirror-symmetric handling for left/right parent positions
  - Root-black invariant enforced after every insert
- **Ready List**: O(1) append + O(1) drain via `_ep_mark_ready` / `_ep_drain_ready`
- **Spatial locality**: `hilbert_encode(fd, epfd, 0)` hint for cache-friendly node allocation
- **API**: `sys_epoll_create`, `sys_epoll_ctl` (ADD/DEL/MOD), `sys_epoll_wait`, `sys_epoll_close`
- **Legacy**: `sys_poll` retained with activated `pipe_available` readiness check
- **Self-test**: 32 non-sequential fd inserts + search verify + mod + del + RB root-black check
- **Complexity**: insert O(log n), search O(log n), wait O(k) where k = ready count

## v4.4

100 kernel modules, 50 shell commands, 184 .hl files, 0 external deps.

### CFS Scheduler: O(n) → O(log n) min-heap
- **task.hl**: Replaced linear-scan `task_pick_next` with min-heap run queue
- New functions: `rq_insert`, `rq_pop_min`, `rq_peek_vruntime`, `rq_remove`, `rq_count`
- Internal: `_rq_sift_up`, `_rq_sift_down`, `_rq_swap` (classic binary heap)
- `task_create` → auto-inserts into heap; `task_kill` → removes from heap
- `context_switch` → re-inserts old task into heap with updated vruntime
- `task_pick_next` → O(1) peek + O(log n) pop (vs old O(n) full scan)
- Integrated self-test: insert 5 out-of-order tasks, verify pop order + remove + empty
- **Comparison**: matches Linux CFS O(log n) rbtree; HicOS uses min-heap (simpler, same complexity)

## v4.3

### v4.3 Highlights
- **usermode.hl**: TSS init with mem_zero, STAR MSR encoding resolved (GDT: null/kcode/kdata/udata/ucode64), IRETQ frame built in memory, syscall_entry protocol documented
- **posix.hl**: `sys_fork` fully activated (register copy, FD table copy, page table share), `sys_exec` loads ELF + resets FDs, `sys_wait` polls child state with timeout
- **syscall.hl**: 20+ syscalls dispatched (FORK/EXEC/WAIT/KILL/PIPE/SEND/RECV/OPEN/CLOSE/STAT/READDIR/MKDIR/UNLINK/BRK/IOCTL/VERSION), pointer validation via `syscall_validate_ptr`, ABI version SYS_VERSION=255
- **vfs.hl**: `vfs_init` auto-mounts ramfs+devfs, `vfs_open` searches free slot and dispatches to backend, `vfs_read`/`vfs_write` dispatch to ramfs, `vfs_seek`/`vfs_stat`/`vfs_readdir`/`vfs_mkdir`/`vfs_unlink` activated
- **Security**: SMEP/SMAP CR4 bits, syscall pointer bounds checking (-EFAULT)
- **THREE_SYSTEM_COMPARISON.md**: Full 4-dimension comparison vs Linux/Windows/macOS with atomic improvement plan

## v4.2

100 kernel modules, 50 shell commands, 184 .hl files, 0 external deps.

### Critical compiler bugs fixed in v4.2
- **`char_at` / `is_digit` / `is_alnum`**: These core tokenizer builtins were never registered — **self-hosting bootstrap could not compile itself**
- **`parse_number`**: Used by tokenizer to convert numeric strings but was never defined — all number literals would fail to parse during self-bootstrap
- **`ord`**: Returned raw string char instead of ASCII code when host uses string-indexed chars — broke `char_code_at` and all char→int conversions
- **`range`**: Only supported `range(n)`, now supports `range(start, end)` and `range(start, end, step)`
- **`**` power operator**: Failed on negative exponents (infinite loop) — now correctly computes `x^(-n) = 1/x^n`

### Kernel integration activated in v4.2
- **mem.hl**: Added `mem_read_i16` / `mem_write_i16` (signed 16-bit for audio PCM), `mem_write_string` / `mem_read_string`, `clamp`, `char_code_at`
- **syscall.hl**: Activated all core syscalls (SYS_EXIT/GETPID/WRITE/READ/MMAP/MUNMAP/SLEEP/UPTIME) — previously all returned 0
- **signal.hl**: Activated `signal_deliver` with actual pending/blocked bitmask scanning and SIGKILL/SIGTERM default action

## v4.1

### Bug fixes in v4.1
- **Compiler**: `self.name = value` field assignment was silently ignored (parsed as ExprStmt instead of FieldAssign) — **critical OOP bug**
- **Compiler**: `obj.method(args)` was resolved as global function lookup instead of class method dispatch — added MethodCall AST node with class hierarchy search
- **Compiler**: Fixed variadic `*args` parameter binding (was comparing char as int instead of string)
- **Compiler**: Variadic parameter names now correctly strip `*` prefix when binding to env
- **stdlib.hl**: `obj_call_method` returned the method object instead of calling it
- **stdlib.hl**: Added `array_last`/`array_first` utility functions
- **pipe.hl**: Fixed undefined variable BUG in `pipe_write`/`pipe_read` (wp, rp, count were used before declaration)
- **HicOS_FileSystem.hl**: Replaced JS `.split()/.pop()/.join()/.filter()` with native H-L `str_split`/`array_join`/`pop`
- **HicOS_SecurityManager.hl**: Replaced JS `crypto.subtle.digest` + `.map()/.join()` with native `sha256_hash` + hex encoding
- **icmp.hl**: Removed duplicate ARP functions (arp_lookup/arp_insert/arp_process_reply) that conflicted with arp.hl
- **rtc.hl**: Removed duplicate functions (rtc_read_reg/rtc_read_time/get_ticks) that conflicted with timer.hl
- **build.hl**: Added 5 missing modules (lint, boot, test, test-runner, posix_test)
- **pipe.hl**: Activated `pipe_create`, `pipe_available` (were returning stubs)
- **rtc.hl**: Activated `rtc_wait_ready` with actual timeout loop, `uptime_secs` now calls `get_ticks()`
- **README.md**: Fixed file counts (182→184, 99→100 kernel modules)

### New in v4.1
**H-L language features** (Python-level):
- `class` / single inheritance / magic methods (`__init__`, `__str__`, `__eq__`, `__call__`, etc.)
- `@decorator` syntax + built-in decorators (`@cache`, `@deprecated`, `@staticmethod`)
- `[expr for x in iter if cond]` list comprehensions
- `let [a, [b, c]] = expr` deep destructuring + `_` wildcard
- `yield` statement + generator coroutines
- `raise` statement + typed `catch e : TypeError { }` + multi-catch clauses
- `fn f(a: int, b: int) -> int` optional type hints
- Default parameters `fn f(a, b = 10)` + `*args` variadic
- `super(self)` parent class access

**stdlib.hl** (new): OOP utilities, generator tools, exception classes, decorator helpers, reduce

**Kernel modules activated**:
- 21 modules: all commented-out mem_write/mem_read calls activated
- tls.hl: full SHA-256 (64 rounds) + HMAC-SHA-256 + HKDF
- ext2.hl: inode read / directory listing / indirect blocks
- virt_mem.hl: pte_read/pte_write/alloc_page_table
- mouse.hl: overflow protection + dynamic screen bounds
- kernel_init.hl: activated page_alloc/hilbert_alloc/pci_scan/smp/shell

## v4.0

99 kernel modules, 49 shell commands, 182 .hl files, 0 external deps.

### New in v4.0
**Native compiler pipeline**: ir.hl (H-IR + const-fold/DCE/strength-reduce),
regalloc.hl (linear-scan, 14 GP regs), abi.hl (System V AMD64),
codegen.hl (AST→IR→x86_64 with If/While/Call).
x86 encoder expanded to 126 instructions (LEA, CMOV, BSF/BSR, POPCNT, RDTSC, fences).

sysfs, http, shm, eventfd, trace, hrtimer,
pty, socket, netfilter, random, cgroup, inotify,
mmap, poll, tmpfs, ntp, block_cache, watchdog,
ipv6, udp, mixer, syslog, login,
gpu, ntfs, ext2, ext4, tls, users, usb_storage, usb_hid, usb_hub,
posix, pipe, wm, wifi, bluetooth, rtc, procfs, env, firmware,
terminal, multimon, arp, posix_test

### Shell commands (49)
help ver uptime date free heap ps cpus mount lspci ifconfig
ls cat echo fib hilbert clear reboot shutdown ping dns arp dev panic
whoami id uname lsusb beep env proc meminfo mounts dmesg mixer ip6
cache ntp wdog tmpfs fw rand cg pty sock shm trace hrt sysfs

## v3.1
51 kernel modules. Boot, memory, tasks, FS, net, devices, shell (24 cmds).

## v2.0
x86_64 encoder (119 instructions). 6KB bootable image.

## v1.0
H-L self-hosting compiler. Hilbert-curve spatial addressing.

## Roadmap

### v4.1
- Graphical login screen, copy-on-write fork, USB isochronous, HTTP/2

### v5.0
- Native H-L GUI framework, package manager, hardware GPU shaders, Btrfs/ZFS
