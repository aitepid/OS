# HicOS 6.0

纯 `Hilbert-Lang (H-L)` 编写的实验性 x86_64 裸金属操作系统与自举工具链。零外部依赖，100% 自研语言实现。

## 当前状态（迭代 440 — M6 全部里程碑达成 + Sprint 1-17 质量修复完成）

| 指标 | 数值 |
|---|---:|
| 总 `.hl` 文件 | **495** |
| 内核模块（`bare-kernel/hl/`）| **426** |
| Shell 命令 | **1,800** |
| H-L 总行数 | **~163,700** |
| 内核函数 | **~2,200** |
| 外部依赖 | **0** |
| 启动镜像（BIOS） | 162,816 字节 |
| 启动镜像（UEFI） | 34,603,008 字节 |
| Bug 修复 Sprint | **1–17 轮全部完成** |
| H-L 语法违规 | **0**（第四轮静态验证）|

**当前阶段：第七阶段·生态与自举完善 ✦ 全部完成**

全部里程碑已达成：
- ✦ **M1**（iter 360）：竞赛级算法库完整（300+ 算法）
- ✦ **M2**（iter 375）：自宿主编译器成熟（类型系统+链接器）
- ✦ **M3**（iter 385）：完整存储引擎（B+Tree+WAL+MVCC）
- ✦ **M4**（iter 405）：完整 ML 推理框架（CNN+RNN+Transformer）
- ✦ **M5**（iter 420）：生产级稳定性（CFS+NUMA+Hypervisor）
- ✦ **M6**（iter 440）：完整生态（包管理+LSP+调试器+POSIX+WASM）

---

## 产物

| 产物 | 大小 |
|---|---:|
| `hicos-hl.img`（BIOS） | 162,816 字节（318 扇区） |
| `hicos-uefi.img`（UEFI） | 34,603,008 字节 |
| `kernel.bin` | 30,704 字节 |

---

## 仓库结构

```text
HicOS/
├─ bare-kernel/
│  └─ hl/               # 423+ 个内核模块（~140,000 行）
├─ scripts/             # 29 个 PowerShell 构建/验证脚本
├─ IP-Protection/       # 60 个知识产权文件
├─ hl-bootstrap.hl      # 自举编译器（4,572 行，208 函数）
├─ stdlib.hl            # 标准库（1,545 行，143 函数）
├─ manifest.hl          # 项目元数据（单一事实来源）
├─ HicOS_*.hl           # 27 个子系统模块
├─ hicos-hl.img         # BIOS 镜像（162,816 字节）
├─ hicos-uefi.img       # UEFI 镜像（34,603,008 字节）
└─ *.md                 # 11 个文档
```

---

## 已完成的迭代历程

### 阶段 1–5（迭代 81–107）：内核核心算法升级

| 阶段 | 模块 | 升级 |
|---|---|---|
| 1 内存 | `page_alloc` `kmalloc` `block_cache` `hilbert_alloc` | 伙伴系统 / 空闲链表 / 哈希LRU / 归并排序 |
| 2 网络 | `tcp` `dns` `vfs` | Reno拥塞 / TTL缓存 / Trie前缀树 |
| 3 多核 | `arp+net` `ext2` `swap` `smp` | 哈希表 / inode缓存 / 增强时钟 / Per-CPU队列 |
| 4 调度 | `sched` `mmap` `pipe` `tls` | MLFQ / 按需COW / SPSC环形 / TLS1.3状态机 |
| 5 隔离 | `sync` `poll` `cgroup` `bpf` | futex哈希 / 边缘触发epoll / cgroup强制 / eBPF VM |

### 阶段 6（迭代 109–130）：高级特性与 UI 系统

- **109–120**：链接器优化、IR VM 双引擎、QUIC v1、内核热补丁框架
- **121–123**：裸机安装（VGA控制台、ATA PIO、USB键盘、自安装镜像）
- **124–130**：完整图形桌面（主题/控件/对话框/终端/安装器/系统监控/通知/窗口管理）

### 阶段 7–8（迭代 131–246）：协议与算法大扩展（130→232 模块）

116 次迭代，新增：**网络协议**（HTTP/WS/SMTP/POP3/IMAP/IRC/FTP/MQTT 等）、**压缩算法**（LZ4/ZLIB/LZMA/Bzip2/Snappy/Zstd/Brotli）、**加密全覆盖**（AES/ChaCha20/RSA/Ed25519/SM3/SM4 等）、**序列化格式**（Protobuf/Avro/CBOR/ASN.1）、**文件格式**（BMP/GIF/WAV/PNG/JPEG）。

### 阶段 9（迭代 247–339）：高级数据结构 + 竞赛算法（232→325 模块）✦ M1

**分布式/一致性**：Raft、Gossip、CRDT | **概率结构**：Bloom/HyperLogLog/CMS/Cuckoo/t-Digest/Reservoir | **树型结构**：Treap/Splay/LCT/Skip List/Leftist Heap/KD-Tree/Wavelet | **图算法**：Dijkstra/Bellman-Ford/Floyd/A*/Dinic/Tarjan/Hopcroft-Karp 等 | **字符串**：SAM/Manacher/Eertree/BWT/Lyndon/Z-function/KMP | **数论/多项式**：Miller-Rabin/Pollard-Rho/NTT/poly全家桶 | **几何**：Convex Hull/旋转卡壳/半平面交 | **DP优化**：状压/数位/Knuth/分治/轮廓线

### 阶段 10（迭代 340–360）：算法库完善 ✦ M1 达成

bitmask_dp / digit_dp / broken_profile_dp / wavelet_tree_range / implicit_treap / chtholly_tree / suffix_tree / bsgs / min_enclosing_circle 等 21 个模块。

### 阶段 11（迭代 361–375）：编译器深化 ✦ M2 达成

pass_gvn / pass_licm / pass_dce2 / regalloc_linear_scan / regalloc_coalesce / calling_conv / type_infer / type_checker / generics / linker_elf / linker_ar / dynamic_linker / dwarf / perf_counter / jit_stub 共 15 个模块。

### 阶段 12（迭代 376–385）：存储引擎 ✦ M3 达成

btree / btree_plus / lsm_memtable / wal / mvcc / transaction / index_hash / index_btree / query_plan / db_engine 共 10 个模块。

### 阶段 13（迭代 386–395）：网络深化

wireguard / tls13 / http3_quic / dns_over_https / dht / torrent_proto / opentelemetry / prometheus / grpc_stream / websocket_compression 共 10 个模块。

### 阶段 14（迭代 396–405）：机器学习深化 ✦ M4 达成

conv2d / pooling / rnn / lstm / autograd / optimizer / tokenizer / embedding / model_serialize / gpu_inference 共 10 个模块。

### 阶段 15（迭代 406–420）：系统稳定性与生产化 ✦ M5 达成

scheduler_cfs / numa_alloc / ftrace / kprobe / memory_profiler / heap_checker / crash_reporter / core_dump / hotpatch / livepatch / power_mgmt / thermal / cpufreq / hypervisor / vmx 共 15 个模块。

### 阶段 16（迭代 421–440）：生态与自举完善 ✦ M6 达成

| 迭代 | 模块 | 功能 |
|---|---|---|
| 421–423 | package_manager + pkg_registry + pkg_build | H-L 包管理器 + 软件包注册中心 + 构建系统 |
| 424–426 | hldoc + hltest + hlbench | 文档生成器 + 单元测试框架 + 基准测试框架 |
| 427–429 | lsp_server + syntax_highlight + code_complete | LSP 服务器 + 语法高亮 + 代码补全 |
| 430–432 | debugger + gdb_stub + breakpoint | 内置调试器 + GDB Remote 协议桩 + 断点管理器 |
| 433–435 | hl_repl + hl_fmt + hl_lint2 | H-L REPL 环境 + 代码格式化器 + 增强 Lint |
| 436–438 | posix_compat + musl_shim + linux_syscall | POSIX 兼容层 + musl libc 垫片 + Linux syscall 层 |
| 439–440 | wasm_runtime + wasm_jit | WASM MVP 解释器 + JIT 热路径编译器 |

---

## 内核功能全景

### 系统/硬件层

- **控制台**：VGA 文本模式（80×25）+ 串口双输出
- **硬件**：PIC/PIT/IDT/LAPIC/SMP（INIT-SIPI-SIPI）
- **存储**：PCI 扫描、VirtIO-blk/net、AHCI、NVMe、USB、ATA PIO
- **内存**：伙伴系统 / 分级空闲链表 / 按需分页+COW / Swap / Block Cache / NUMA 分配器
- **调度**：MLFQ 4级 / CFS 完全公平 / SMP Per-CPU 运行队列
- **隔离**：futex / epoll / cgroup / seccomp / 命名空间 / 容器运行时
- **稳定性**：ftrace / kprobe / memory_profiler / heap_checker / crash_reporter / core_dump
- **热补丁**：hotpatch（trampoline）/ livepatch（运行时函数替换）
- **虚拟化**：hypervisor 框架 / vmx（VMX/VT-x 支持）

### 文件系统层

FAT16 / Ext2/Ext4 / NTFS / VFS / devfs / procfs / sysfs / ramfs / tmpfs / OverlayFS / iNotify / Block Cache / B-Tree 索引 / WAL / MVCC

### 网络协议栈

| 层次 | 协议 |
|---|---|
| 数据链路 | ARP、以太网、VLAN |
| 网络层 | IPv4、IPv6、ICMP |
| 传输层 | TCP（Reno）、UDP |
| 应用层 | HTTP/1.1/2/3、WebSocket、TLS 1.3、QUIC、DNS/DoH、DHCP、NTP、SMTP、POP3、IMAP、FTP、IRC、MQTT、SIP、RTSP、RTP、STUN、SOCKS5、LDAP、RADIUS、gRPC、WireGuard |

### 加密/安全

AES-GCM、ChaCha20-Poly1305、SM4 | RSA、Ed25519、Curve25519 | SHA-256、SM3、BLAKE2、xxHash、SipHash | HMAC、PBKDF2、scrypt、Argon2、bcrypt | X.509、PEM、JWT、ASN.1 DER | RDRAND+timer jitter

### 算法库（~180 个模块）

**数据结构**：Treap/Splay/LCT/Skip List/Bloom/HLL/CMS/Cuckoo/t-Digest 等 40+个  
**图算法**：Dijkstra/Bellman-Ford/Floyd/A*/Dinic/Tarjan/Hungarian/Hopcroft-Karp 等  
**字符串**：KMP/SAM/Manacher/Eertree/BWT/Lyndon/Z-function/Aho-Corasick 等  
**数学**：Miller-Rabin/Pollard-Rho/NTT/多项式全家桶/BSGS/线性基  
**几何**：凸包/旋转卡壳/半平面交/最小圆覆盖  
**DP**：状压/数位/Knuth/分治/轮廓线

### 机器学习框架

CNN（conv2d+pooling）/ RNN+LSTM / Transformer（多头自注意力）/ 自动微分（autograd）/ SGD+Adam 优化器 / BPE 分词器 / 词向量嵌入 / 模型序列化 / GPU 加速推理

### 编译器工具链

x86_64 原生后端（126 指令）/ IR+SSA（37 操作码）/ 线性扫描寄存器分配 / GVN/LICM/DCE 优化 Pass / 完整类型系统（HM类型推断+泛型）/ ELF 链接器 / DWARF 调试信息 / JIT 桩

### 存储引擎

B-Tree / B+ Tree / LSM Memtable / WAL / MVCC / 事务 API / 哈希索引 / 查询计划 / 完整关系型数据库引擎

### 生态工具（Phase 7 — 全部完成）

包管理器（install/remove/registry）/ 构建系统（依赖追踪）/ 文档生成器 / 单元测试框架 / 基准测试框架 / LSP 服务器 / 语法高亮 / 代码补全 / 内置调试器 / GDB Remote 协议桩 / 断点管理器 / H-L REPL 环境 / 代码格式化器 / 增强 Lint / POSIX 兼容层 / musl libc 垫片 / Linux 系统调用层 / WASM MVP 解释器 / WASM JIT 编译器

---

## Shell 命令（1,800 个）

覆盖：系统管理 / 网络诊断 / 文件操作 / 进程管理 / 压缩加密 / 数据结构 / 图算法 / ML推理 / 虚拟化 / 调试 / 包管理 / 生态工具 / POSIX / WASM 运行时

---

## Bug 修复与代码质量（Sprint 1–17）

全库 426 个内核模块在迭代 440 之后经历了 17 轮系统性代码质量修复，所有已知 H-L 语法违规及逻辑缺陷已清零。

| Sprint | 内容 | 范围 |
|--------|------|------|
| Sprint 1–5 | P0~P3 问题：8 处 `init()` 命名冲突、`irc say` 崩溃、5 个空桩模块、hl_fmt/hl_repl 假实现、Shell 重复命令块 | 26 文件 |
| Sprint 6–7 | N-01~N-13：argon2/avro 重写为合法 H-L 语法、ahci MMIO 重命名、15+ 文件跨模块函数名去冲突 | 17 文件 |
| Sprint 8 | N-14~N-15：netfilter.hl（8 处）+ usb_kbd.hl（1 处）`continue` 语法消除 | 2 文件 |
| Sprint 9 | N-16~N-26：26 个测试函数名添加模块前缀，消除 11 组跨文件冲突 | 13 文件 |
| Sprint 10–11 | 第二轮深度审查（R-01~R-04）+ 第四轮 bare-block 修复 | 4 文件 |
| Sprint 12 | 全库 `continue` 残留清零（200+ 模块扫描） | 200+ 文件 |
| Sprint 13 | scalar-as-array `set_at(scalar, 0, val)` 修复 + `_test` 名冲突 | 9 文件 |
| Sprint 14 | scalar-as-array 修复（avro/argon2/linux_syscall/gdb_stub 等 9 模块） | 9 文件 |
| Sprint 15 | 全库 loop/control 变量 `let mut` 补全 | 373 文件 |
| Sprint 16 | 全局模块状态变量 `let mut` 补全 | 200+ 文件 |
| Sprint 17 | 函数体内全部局部变量 `let mut` 补全（10,379 处） | 400+ 文件 |

**第四轮静态验证结果（2026-05-19）：** `break` / `return -N` / `global` / `#注释` / `while(条件)` / 跨文件函数名冲突 / `continue` 语句 — **全部 0 处** ✅

详细修复记录见 [`BUG_FIX_OUTLINE.md`](BUG_FIX_OUTLINE.md)。

---

## 构建与验证

```powershell
# 构建
.\hl-bootstrap.cmd test

# 完整门禁测试
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1

# 发布验证
powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1

# QEMU 冒烟测试
powershell -ExecutionPolicy Bypass -File .\scripts\qemu-smoke.ps1
```

---

## 技术特点

- **零外部依赖**：无 C/C++/Rust，无 JSON/YAML，无 npm/cargo
- **自宿主**：编译器、链接器、解释器全部用 H-L 编写
- **裸金属**：直接在 x86_64 硬件上运行，BIOS 和 UEFI 双启动
- **模块化**：426 个独立内核模块，每个专注单一功能
- **三层架构**：镜像构建（Layer A）/ 自举工具链（Layer B）/ 内核模块（Layer C）

## 相关文档

- `ARCHITECTURE.md`：三层架构详解
- `ROADMAP.md`：已完成阶段与里程碑
- `CHANGELOG.md`：详细迭代记录（440 个迭代）
- `PROJECT_STATUS.md`：项目状态与统计
- `BUG_FIX_OUTLINE.md`：Sprint 1-17 全量修复记录（54 缺陷，10,379 语法修复，第四轮验证零违规）
- `PROJECT_ADVANCEMENT_OUTLINE.md`：推进大纲与 SOP
- `HILBERT_LANG_BNF.md`：H-L 语言语法规范
- `UI_DESIGN_PLAN.md`：UI 设计策划
- `FIVE_OS_COMPARISON.md`：与五个知名 OS 对比
- `THREE_SYSTEM_COMPARISON.md`：三系统架构对比

## License

本项目为教育与研究目的开发，所有源代码采用自研 Hilbert-Lang 编写。
