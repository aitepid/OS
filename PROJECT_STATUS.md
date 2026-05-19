# HicOS Project Status

## 版本定位

当前仓库处于 `v6.0` 发布线，最新功能里程碑为迭代 **440**（wasm_runtime + wasm_jit）。✦ **全部里程碑 M1–M6 已达成**

## QEMU 压力测试状态 ✅

25 个 QEMU 压力测试问题（BUG-001 至 BUG-025）**全部已修复**（Sprint 26–27）：

| 分类 | 修复数 | 涉及模块 |
|---|---:|---|
| P0 崩溃/安全 | 3 | shell.hl、gdb_stub.hl、random.hl |
| P1 加密/认证 | 5 | tls.hl、jwt.hl、quic.hl、x509.hl、linker.hl |
| P2 功能不完整 | 11 | dns.hl、socket.hl、jit_stub.hl、wasm_jit.hl、ext4.hl、pty.hl、cbor.hl、debugger.hl、lsp_server.hl、syntax_highlight.hl、code_complete.hl |
| P3 质量问题 | 6 | abi.hl、calling_conv.hl、ui_settings.hl、musl_shim.hl、advanced_verify.hl、（manifest 统计） |

## 当前基线（迭代 440）

### 仓库规模（精确计数）

| 指标 | 当前值 | 说明 |
|---|---:|---|
| 全部 `.hl` 文件 | **495** | ~69 根目录 + 426 bare-kernel/hl |
| H-L 总行数 | **~163,700** | 持续增长 |
| `bare-kernel/hl/` 内核模块 | **426** | 编译进 `kernel.bin` |
| Shell 命令数 | **1,800** | shell.hl 全量命令集 |
| `hl-bootstrap.hl` | 4,572 行 / 208 函数 | 自举编译器 |
| `stdlib.hl` | 1,545 行 / 143 函数 | 标准库 |
| `scripts/*.ps1` | 29 个（11,193 行）| 构建/验证脚本 |
| `IP-Protection/` 文件数 | 60 | 知识产权文件 |
| `.md` 文档 | 11 | |
| 外部依赖 | **0** | 100% 纯 H-L |

### 产物尺寸（实测）

| 产物 | 大小 |
|---|---:|
| `hicos-hl.img`（BIOS） | 162,816 字节（318 扇区） |
| `hicos-uefi.img`（UEFI） | 34,603,008 字节 |
| `kernel.bin` | 30,704 字节 |

---

## 已达成里程碑

| 里程碑 | 迭代 | 内容 | 状态 |
|---|---:|---|---|
| **M1** | 360 | 竞赛级算法库完整（300+算法，Shell 突破 1,200）| ✦ 已达成 |
| **M2** | 375 | 自宿主编译器成熟（类型系统+优化Pass+完整链接器）| ✦ 已达成 |
| **M3** | 385 | 完整存储引擎（B+Tree+WAL+MVCC+关系型数据库）| ✦ 已达成 |
| **M4** | 405 | 完整 ML 框架（CNN+RNN+LSTM+Transformer+自动微分）| ✦ 已达成 |
| **M5** | 420 | 生产级稳定性（CFS+NUMA+热补丁+崩溃报告+Hypervisor）| ✦ 已达成 |
| **M6** | 440 | 完整生态（包管理+LSP+调试器+POSIX+WASM，Shell 1,800）| ✦ 已达成 |

---

## 各阶段完成状态

### 系统/硬件层 ✅

| 子模块 | 状态 |
|---|---|
| 串口/VGA 控制台 | ✅ |
| 内存管理（伙伴系统/分级/按需分页/Swap/NUMA）| ✅ |
| 中断/异常（IDT/PIC/PIT/LAPIC）| ✅ |
| 任务/调度（MLFQ+CFS/signal/cgroup）| ✅ |
| PCI/AHCI/ATA/NVMe/VirtIO/USB | ✅ |
| 音频（AC97/mixer/AudioServer）| ✅ |
| 显示（VESA/VirtIO-GPU/framebuffer/多显示器）| ✅ |
| ACPI/电源/热量/CPU频率 | ✅ |
| SMP（多核）| ✅ |
| 安全启动/seccomp | ✅ |
| CFS 调度器 | ✅ |
| NUMA 分配器 | ✅ |
| 系统稳定性（ftrace/kprobe/崩溃报告/内存分析）| ✅ |
| 热补丁/在线补丁 | ✅ |
| Hypervisor + VMX/VT-x | ✅ |

### 文件系统层 ✅

FAT16 / Ext2/Ext4 / NTFS / VFS / devfs / procfs / sysfs / ramfs / tmpfs / OverlayFS / iNotify / B-Tree 索引 / WAL / MVCC 事务

### 网络协议栈 ✅

HTTP/1.1/2/3、WebSocket、TLS 1.3、QUIC、DNS/DoH、DHCP、NTP、WireGuard、SMTP/POP3/IMAP、FTP、IRC、MQTT、SIP/RTSP/RTP、STUN、SOCKS5、LDAP、RADIUS、gRPC、OpenTelemetry、Prometheus、DHT、BitTorrent 协议框架

### 加密/安全层 ✅

AES-GCM / ChaCha20-Poly1305 / SM4 / RSA / Ed25519 / Curve25519 / SHA-256 / SM3 / BLAKE2 / HMAC / PBKDF2 / scrypt / Argon2 / bcrypt / X.509 / PEM / JWT / CRC / UUID

### 算法库 ✅（竞赛级完整）

**数据结构**（44 个）：二叉堆/左偏堆/Treap/Splay/LCT/DSU/Bloom/HLL/CMS/Cuckoo/t-Digest/LRU/一致性哈希/CRDT/Merkle/Wavelet/Reservoir/KD-Tree/区间树/Trie/Aho-Corasick/后缀数组/后缀自动机/B-Tree/B+Tree 等

**图算法**：Dijkstra/Bellman-Ford/Floyd-Warshall/A*/Dinic/最小费用最大流/Hopcroft-Karp/Hungarian/Tarjan SCC/欧拉路径/2-SAT/重心分解/HLD/LCA/虚树/支配树/块割树/桥树

**字符串**：KMP/Z-function/Rabin-Karp/Aho-Corasick/后缀数组/SAM/Manacher/Eertree/BWT/Lyndon/后缀树/BSGS

**数论/多项式**：Miller-Rabin/Pollard-Rho/exGCD/CRT/NTT/多项式求逆/ln/exp/开根/BSGS/线性基

**几何**：凸包（Andrew）/旋转卡壳/半平面交/最小圆覆盖

**DP优化**：区间DP/分治DP/Knuth/斜率优化/状压DP/数位DP/轮廓线DP/回文划分DP

### 编译器工具链 ✅（完全自宿主）

x86_64 原生后端（126指令）/ IR+SSA（37 操作码）/ 线性扫描寄存器分配 / GVN/LICM/DCE2 优化 Pass / HM 类型推断 + 泛型 / ELF64 链接器 / 静态库 + 动态链接 / DWARF 调试信息 / 性能计数器 / JIT 桩

### 存储引擎 ✅

B-Tree（读优化）/ B+ Tree（范围查询）/ LSM Memtable / Write-Ahead Log / MVCC / 事务 API / 哈希索引 / B-Tree 索引 / 查询计划 / 完整关系型数据库引擎

### 机器学习框架 ✅（M4）

2D 卷积层 + 池化 / RNN + LSTM / Transformer 多头自注意力 / 自动微分（反向图）/ SGD+Adam / BPE 分词器 / 词向量嵌入 / 模型序列化 / VirtIO-GPU 加速推理

### 生态工具 ✅（Phase 7 全部完成）

| 模块 | 状态 | 迭代 |
|---|---|---|
| 包管理器（install/remove/version）| ✅ | iter 421 |
| 软件包注册中心 | ✅ | iter 422 |
| 构建系统（依赖追踪）| ✅ | iter 423 |
| 文档生成器（HLDoc）| ✅ | iter 424 |
| 单元测试框架（HLTest）| ✅ | iter 425 |
| 基准测试框架（HLBench）| ✅ | iter 426 |
| LSP 服务器存根 | ✅ | iter 427 |
| 语法高亮引擎 | ✅ | iter 428 |
| 代码补全引擎 | ✅ | iter 429 |
| 内置调试器 | ✅ | iter 430 |
| GDB Remote 协议桩 | ✅ | iter 431 |
| 断点管理器 | ✅ | iter 432 |
| H-L REPL 环境 | ✅ | iter 433 |
| 代码格式化器 | ✅ | iter 434 |
| 增强 Lint | ✅ | iter 435 |
| POSIX 扩展兼容 | ✅ | iter 436 |
| musl libc 垫片 | ✅ | iter 437 |
| Linux 系统调用兼容层 | ✅ | iter 438 |
| WASM MVP 解释器 | ✅ | iter 439 |
| WASM JIT 编译器 | ✅ | iter 440 |

---

## 三层架构现状

| 层级 | 载体 | 说明 |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS 镜像生成链 |
| B | `hl-bootstrap.hl`（4,572 行，208 函数）| 自举编译器/解释器/工具链 |
| C | `bare-kernel/hl/*.hl`（426 模块）| 内核模块 → `kernel.bin` |

---

## 规模总览

| 里程碑 | 迭代 | 模块数 | HL 文件 | Shell 命令 | 状态 |
|---|---:|---:|---:|---:|---|
| M1 | 360 | ~346 | ~460 | ~1,250 | ✦ 已达成 |
| M2 | 375 | ~361 | ~484 | ~1,350 | ✦ 已达成 |
| M3 | 385 | ~371 | ~510 | ~1,420 | ✦ 已达成 |
| M4 | 405 | ~391 | ~540 | ~1,550 | ✦ 已达成 |
| M5 | 420 | ~406 | ~565 | ~1,650 | ✦ 已达成 |
| **当前** | **440** | **426** | **495** | **1,800** | ✦ M6 已达成 |
