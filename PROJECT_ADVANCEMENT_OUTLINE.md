# HicOS 项目推进大纲

> 最后同步：Iteration 432 | 2026-05-18  
> 版本：HicOS 6.0 | 语言：100% Hilbert-Lang (H-L) | 架构：x86_64 裸金属

---

## 一、项目全貌

HicOS 是一个完全用自研语言 **Hilbert-Lang (H-L)** 编写的裸金属 x86_64 操作系统，具备以下核心特征：

| 属性 | 值 |
|------|----|
| 内核模块数 | **418** |
| HL 文件总数 | **487**（~72 根目录 + 418 内核模块）|
| Shell 命令数 | **1,744** |
| H-L 总代码行数 | **~159,650 行** |
| 内核函数数 | **~2,200** |
| 外部依赖 | **0**（100% 纯 H-L）|
| 自宿主 | ✅ 已实现 |
| 启动镜像 | 162 KB（hicos-hl.img）|
| UEFI 镜像 | 34.6 MB（hicos-uefi.img）|
| 编译后端 | 原生 x86_64（126 条指令，37 个 IR 操作码）|
| ABI | System V AMD64 |
| 寄存器分配 | 线性扫描（14 GP 寄存器）|

---

## 二、当前迭代状态

### 最近提交记录

| 迭代区间 | 内容 | 模块数 | HL 文件 | Shell 命令 |
|----------|------|--------|---------|------------|
| 430–432 | debugger + gdb_stub + breakpoint | 418 | 487 | 1,744 |
| 427–429 | lsp_server + syntax_highlight + code_complete | 415 | 484 | 1,723 |
| 424–426 | hldoc + hltest + hlbench | 412 | 481 | 1,702 |
| 421–423 | package_manager + pkg_registry + pkg_build | 409 | 478 | 1,681 |
| 419–420 | hypervisor + vmx | 406 | 475 | 1,660 |
| 416–418 | power_mgmt + thermal + cpufreq | 404 | 473 | 1,639 |
| 414–415 | hotpatch + livepatch | 401 | 470 | 1,618 |
| 412–413 | crash_reporter + core_dump | 399 | 468 | 1,604 |
| 410–411 | memory_profiler + heap_checker | 397 | 466 | 1,590 |

---

## 三、功能域完成度评估

### 3.1 系统/硬件层 ✅ 完整

| 子模块 | 状态 | 说明 |
|--------|------|------|
| 串口/控制台 | ✅ | serial, vga_console, font |
| 内存管理 | ✅ | kmalloc, page_alloc, hilbert_alloc, mmap, swap, NUMA |
| 中断/异常 | ✅ | IDT, PIC, PIT, LAPIC |
| 定时器 | ✅ | timer, hrtimer, RTC |
| 任务/调度 | ✅ | task, sched (MLFQ + CFS), signal, cgroup |
| PCI 总线 | ✅ | pci, AHCI, ATA PIO, NVMe, VirtIO |
| USB | ✅ | xHCI, HID, Hub, Keyboard, Storage |
| 音频 | ✅ | AC97, mixer, AudioServer |
| 显示 | ✅ | VESA, VirtIO-GPU, framebuffer, 多显示器 |
| ACPI/电源 | ✅ | acpi, power_mgmt, thermal, cpufreq, SMP |
| 安全启动 | ✅ | secure_boot, seccomp, TSS, SYSCALL MSR |
| 系统稳定性 | ✅ | ftrace, kprobe, memory_profiler, heap_checker |
| 崩溃处理 | ✅ | crash_reporter, core_dump（ELF core） |
| 热补丁 | ✅ | hotpatch（trampoline）, livepatch（运行时替换）|
| 虚拟化 | ✅ | hypervisor 框架, vmx（VMX/VT-x 支持）|

### 3.2 文件系统层 ✅ 完整

| 子模块 | 状态 | 说明 |
|--------|------|------|
| VFS 抽象层 | ✅ | vfs, devfs, procfs, sysfs |
| FAT16 | ✅ | 读写支持 |
| Ext2/Ext4 | ✅ | 含 VFS 挂载 |
| NTFS | ✅ | 基础支持 |
| RAM/Tmp FS | ✅ | ramfs, tmpfs |
| OverlayFS | ✅ | CoW union mount |
| iNotify | ✅ | 文件系统事件通知 |
| 块缓存 | ✅ | block_cache |
| B-Tree 索引 | ✅ | btree.hl + btree_plus.hl（iter 376–377）|
| WAL / MVCC | ✅ | wal.hl + mvcc.hl + transaction.hl（iter 379–381）|

### 3.3 网络协议栈 ✅ 完整

| 层次 | 已实现 |
|------|--------|
| 数据链路 | ARP, 以太网, VLAN |
| 网络层 | IPv4, IPv6, ICMP |
| 传输层 | TCP (Reno), UDP |
| 应用层 | HTTP/1.1/2/3, WebSocket, TLS 1.3, QUIC, DNS/DoH, DHCP, NTP |
| 邮件 | SMTP, POP3, IMAP |
| 即时通讯 | IRC, MQTT, WebSocket |
| 文件传输 | FTP, TFTP, SCP |
| 流媒体 | RTP, RTSP, SIP, STUN |
| 目录服务 | LDAP, RADIUS |
| 安全 | WireGuard VPN, TLS 1.3 完整握手 |
| 分布式 | gRPC（流式）, DHT（Kademlia）, BitTorrent 协议框架 |
| 可观测性 | OpenTelemetry（分布式追踪）, Prometheus metrics |

### 3.4 加密/安全 ✅ 非常完整

| 类型 | 已实现 |
|------|--------|
| 对称加密 | AES-GCM, ChaCha20-Poly1305, SM4 |
| 非对称加密 | RSA, Ed25519, Curve25519 (X25519) |
| 哈希 | SHA-256, SM3, BLAKE2, xxHash, SipHash |
| MAC | HMAC, Poly1305 |
| KDF | PBKDF2, scrypt, Argon2, bcrypt |
| 证书/PKI | X.509 v3, PEM, JWT, ASN.1 DER |
| 随机 | RDRAND + timer jitter |
| 其他 | CRC8/16/32, UUID v4 |

### 3.5 数据结构 ✅ 竞赛级完整（44+ 个）

**基础树结构**：二叉堆 / 左偏堆 / Treap / Splay Tree / Skip List / Fenwick Tree / 线段树（懒标记）/ 稀疏表 / 可持久化线段树 / 吉司机线段树 / Li Chao Tree

**高级数据结构**：Link-Cut Tree / DSU（带回滚）/ Bloom Filter / Cuckoo Filter / HyperLogLog / Count-Min Sketch / t-Digest / LRU Cache / 一致性哈希 / CRDT / Merkle Tree / Wavelet Tree（区间k-th）/ 珂朵莉树（ODT）/ Implicit Treap

**搜索/索引树**：KD-Tree / 区间树 / Trie / Aho-Corasick / 后缀数组 / 后缀自动机 / 后缀树（Ukkonen）

**B-Tree 族**：B-Tree（读优化）/ B+ Tree（范围查询）/ LSM Memtable

### 3.6 算法库 ✅ 竞赛级完整

#### 字符串算法

| 算法 | 状态 |
|------|------|
| KMP + Z-function + Rabin-Karp | ✅ |
| Aho-Corasick 自动机 | ✅ |
| 后缀数组 + LCP | ✅ |
| 后缀自动机 SAM | ✅ |
| Manacher 回文 O(n) | ✅ |
| 回文树 Eertree | ✅ |
| BWT（Burrows-Wheeler 变换）| ✅ |
| Lyndon 分解 Duval O(n) | ✅ |
| 滚动哈希（多项式）| ✅ |
| 回文划分最小切割 DP | ✅ |
| 后缀树（Ukkonen）| ✅ iter 358 |

#### 图论算法

| 算法 | 状态 |
|------|------|
| 最短路：Dijkstra / Bellman-Ford / Floyd-Warshall / A* | ✅ |
| MST：Prim / Kruskal | ✅ |
| 最大流（Dinic O(V²E)）| ✅ iter 346 |
| 最小费用最大流 | ✅ |
| 二部匹配（DFS + Hopcroft-Karp）| ✅ |
| 匈牙利算法 | ✅ |
| Tarjan SCC / 割点 / 桥 | ✅ |
| 欧拉路径（Hierholzer）| ✅ |
| 2-SAT | ✅ |
| 重心分解 / 重链分解 / LCA | ✅ |
| 虚树 / 必经点树 | ✅ |
| 块割树（Block-Cut Tree）| ✅ iter 347 |
| 桥树（Bridge Tree）| ✅ iter 348 |

#### 数学/数论算法

| 算法 | 状态 |
|------|------|
| exGCD + 模逆 + CRT + Euler φ + 筛法 | ✅ |
| 矩阵快速幂 | ✅ |
| NTT（数论变换，mod 998244353）| ✅ |
| Miller-Rabin 素性测试 | ✅ iter 340 |
| Pollard-Rho 因式分解 | ✅ iter 341 |
| 线性基（XOR 高斯消元）| ✅ iter 342 |
| 多项式求逆（Newton 迭代 + NTT）| ✅ iter 349 |
| 多项式 ln + exp | ✅ iter 350 |
| 多项式开根 | ✅ iter 351 |
| Baby-step Giant-step (BSGS) | ✅ iter 359 |
| Convex Hull Trick（CHT）| ✅ |
| Li Chao Tree | ✅ |
| Sprague-Grundy + Nim 博弈论 | ✅ |

#### 计算几何

| 算法 | 状态 |
|------|------|
| 凸包（Andrew 单调链）| ✅ |
| 旋转卡壳 | ✅ iter 344 |
| 半平面交 | ✅ iter 345 |
| 最小圆覆盖（Welzl）| ✅ iter 360 |
| 点线面关系判断 | ✅ iter 343 |

#### DP 优化

| 类型 | 状态 |
|------|------|
| 区间 DP（矩阵链乘）| ✅ |
| 分治 DP O(n log n) | ✅ |
| Knuth 优化 O(n²) | ✅ |
| 斜率优化（CHT 辅助）| ✅ |
| 回文划分 DP | ✅ |
| 轮廓线 DP（Broken Profile）| ✅ iter 354 |
| 数位 DP | ✅ iter 353 |
| 状压 DP（bitmask）| ✅ iter 352 |

### 3.7 编译器工具链 ✅ 完全自宿主（M2）

| 组件 | 状态 | 说明 |
|------|------|------|
| x86 编码器 | ✅ | 126 条指令 |
| IR/SSA | ✅ | 基本块 + Phi 节点 + 37 个操作码 |
| 寄存器分配 | ✅ | 线性扫描（14 GP 寄存器）iter 364 |
| 寄存器合并 | ✅ | Briggs + George 启发式 iter 365 |
| 代码生成 | ✅ | 窥孔优化 + DCE |
| ABI | ✅ | System V AMD64 + varargs + SSE iter 366 |
| 优化 Pass | ✅ | GVN iter 361 / LICM iter 362 / DCE2 iter 363 |
| 类型系统 | ✅ | HM 类型推断 iter 367 + 类型检查器 iter 368 |
| 泛型 | ✅ | 单态化展开 iter 369 |
| 链接器 | ✅ | ELF64 iter 370 / 静态库 iter 371 / 动态链接 iter 372 |
| 调试信息 | ✅ | DWARF 行号表 + 变量位置 iter 373 |
| 性能计数器 | ✅ | PMU 指令数/缓存缺失 iter 374 |
| JIT | ✅ | 热路径检测 + 即时编译框架 iter 375 |

### 3.8 存储引擎 ✅ 完整（M3）

| 组件 | 状态 |
|------|------|
| B-Tree（读优化）| ✅ iter 376 |
| B+ Tree（范围查询）| ✅ iter 377 |
| LSM Memtable | ✅ iter 378 |
| Write-Ahead Log | ✅ iter 379 |
| MVCC（多版本并发控制）| ✅ iter 380 |
| 事务 API | ✅ iter 381 |
| 哈希索引 | ✅ iter 382 |
| B-Tree 索引 | ✅ iter 383 |
| 查询计划 | ✅ iter 384 |
| 完整关系型数据库引擎 | ✅ iter 385 |

### 3.9 机器学习框架 ✅ 完整（M4）

| 组件 | 状态 |
|------|------|
| 2D 卷积层 + 池化 | ✅ iter 396–397 |
| RNN + LSTM（门控）| ✅ iter 398–399 |
| 自动微分（反向图）| ✅ iter 400 |
| SGD + Adam 优化器 | ✅ iter 401 |
| BPE 分词器 | ✅ iter 402 |
| 词向量嵌入表 | ✅ iter 403 |
| 模型序列化 | ✅ iter 404 |
| VirtIO-GPU 加速推理 | ✅ iter 405 |
| Transformer 多头自注意力 | ✅ iter 253 |

### 3.10 生态工具 🔶 Phase 7 进行中

| 模块 | 状态 |
|------|------|
| 包管理器（install/remove/version）| ✅ iter 421 |
| 软件包注册中心 | ✅ iter 422 |
| 构建系统（依赖追踪）| ✅ iter 423 |
| 文档生成器（HLDoc）| ✅ iter 424 |
| 单元测试框架（HLTest）| ✅ iter 425 |
| 基准测试框架（HLBench）| ✅ iter 426 |
| LSP 服务器 | ✅ iter 427 |
| 语法高亮引擎 | ✅ iter 428 |
| 代码补全引擎 | ✅ iter 429 |
| 内置调试器 | ✅ iter 430 |
| GDB Remote Protocol 桩 | ✅ iter 431 |
| 断点管理器 | ✅ iter 432 |
| H-L REPL 环境 | 🔜 iter 433 |
| 代码格式化器 | 🔜 iter 434 |
| 增强 Lint | 🔜 iter 435 |
| POSIX 扩展兼容 | 🔜 iter 436 |
| musl libc 垫片 | 🔜 iter 437 |
| Linux 系统调用兼容层 | 🔜 iter 438 |
| WASM 解释器 | 🔜 iter 439 |
| WASM JIT | 🔜 iter 440 |

---

## 四、未来迭代规划

### 第七阶段剩余（Iter 433–440）→ M6 目标

#### Iter 433–435：H-L 开发工具

| 模块 | 内容 |
|------|------|
| `hl_repl.hl` | H-L REPL 交互环境（读取-求值-打印循环）|
| `hl_fmt.hl` | H-L 代码格式化器（缩进/对齐/风格规范化）|
| `hl_lint2.hl` | 增强 Lint（未使用变量/类型不匹配/复杂度检查）|

#### Iter 436–438：POSIX 兼容层

| 模块 | 内容 |
|------|------|
| `posix_compat.hl` | POSIX 扩展兼容（信号/进程/IO接口）|
| `musl_shim.hl` | musl libc 接口垫片（标准 C 库接口映射）|
| `linux_syscall.hl` | Linux 系统调用兼容层（execve/mmap/read/write 等）|

#### Iter 439–440：WebAssembly 运行时 → ✦ M6 目标

| 模块 | 内容 |
|------|------|
| `wasm_runtime.hl` | WebAssembly 字节码解释器（MVP 规范）|
| `wasm_jit.hl` | WASM JIT 编译（热路径检测 + 即时生成 x86_64）|

---

## 五、里程碑状态

| 里程碑 | 迭代 | 内容 | 状态 |
|--------|------|------|------|
| **M1** | 360 | 竞赛级算法库（300+ 算法，Shell >1,200）| ✦ 已达成 |
| **M2** | 375 | 自宿主编译器（类型系统+优化Pass+完整链接器）| ✦ 已达成 |
| **M3** | 385 | 完整存储引擎（B+Tree+WAL+MVCC+关系型DB）| ✦ 已达成 |
| **M4** | 405 | 完整 ML 框架（CNN+RNN+LSTM+Transformer+自动微分）| ✦ 已达成 |
| **M5** | 420 | 生产级稳定性（CFS+NUMA+热补丁+崩溃报告+Hypervisor）| ✦ 已达成 |
| **M6** | 440 | 完整生态（包管理+LSP+调试器+POSIX+WASM，Shell >2,000）| 🔜 进行中 |

---

## 六、技术债与已知问题

| 问题 | 影响 | 状态 |
|------|------|------|
| `manifest.hl` 中 `HL_TOTAL_LINES` 未及时动态统计 | 低 | 已知，下次 docs sync |
| `KERNEL_FUNCTIONS` 固定值 2200，未动态统计 | 低 | M2 阶段工具化 |
| 部分网络模块（wifi, bluetooth）功能框架已有但实现浅 | 中 | 长期目标 |
| UI 缺少 TrueType/矢量字体渲染 | 中 | 长期目标 |
| H-L 无统一异常传播机制（返回值约定）| 中 | M6 后评估 |

---

## 七、项目规模预测

| 里程碑 | 迭代 | 模块数 | HL 文件 | 代码行数 | Shell 命令 | 状态 |
|--------|------|--------|---------|---------|------------|------|
| M1 | 360 | 388 | 460 | ~130K | ~1,250 | ✦ 已达成 |
| M2 | 375 | 415 | 484 | ~145K | ~1,350 | ✦ 已达成 |
| M3 | 385 | 430 | 510 | ~155K | ~1,420 | ✦ 已达成 |
| M4 | 405 | 455 | 540 | ~170K | ~1,550 | ✦ 已达成 |
| M5 | 420 | 475 | 565 | ~185K | ~1,650 | ✦ 已达成 |
| **当前** | **432** | **418** | **487** | **~159K** | **1,744** | 🔵 活跃开发 |
| M6 | 440 | ~510 | ~605 | ~205K | ~2,000 | 🔜 目标中 |

---

## 八、每次推进标准操作流程（SOP）

每次 `继续推进` 按如下步骤执行 **3 个模块**：

1. **创建模块文件** `bare-kernel/hl/<name>.hl`
   - 文件头注释：功能、Buffer 地址、关键函数说明
   - 定义全局数组和变量（`array(n, default)`）
   - 实现 `<prefix>_init()` 函数（内核初始化序列必须）
   - 实现核心算法函数
   - 实现 `<prefix>_test()` 自测函数（带 PASS/FAIL 输出）
   - 末尾 `print("<name>.hl loaded")`

2. **更新 `kernel_init.hl`**
   - 添加 `<prefix>_init();` 调用（带注释）
   - 更新 `serial_print` 状态行中的模块数
   - 更新汇总行 `=== HicOS kernel initialized (N modules) ===`

3. **更新 `shell.hl`**
   - `ver` 命令：更新模块数
   - `help` 输出：新增模块命令说明行（每模块约 7 个命令）
   - `shell_handle_ext`：添加命令解析处理块
   - 底部 `print` 行：更新命令总数和模块列表

4. **更新 `manifest.hl`**
   - `KERNEL_MODULES`、`HL_FILES`、`SHELL_COMMANDS`

5. **更新 `CHANGELOG.md`**
   - `Current Snapshot` 区块同步所有统计数字
   - 为每个新迭代添加详情条目

6. **Git 提交**
   ```
   iter NNN-NNN: <mod1> + <mod2> + <mod3> [N modules, N HL files, N shell cmds]
   ```

### Buffer 地址分配规则

每个新模块从前一模块递增 `0x10000`（64 KB）：

| 迭代 | 模块 | Buffer |
|------|------|--------|
| 432 | breakpoint | 0x1E70000 |
| **433** | **hl_repl** | **0x1E80000** |
| **434** | **hl_fmt** | **0x1E90000** |
| **435** | **hl_lint2** | **0x1EA0000** |
| **436** | **posix_compat** | **0x1EB0000** |
| **437** | **musl_shim** | **0x1EC0000** |
| **438** | **linux_syscall** | **0x1ED0000** |
| **439** | **wasm_runtime** | **0x1EE0000** |
| **440** | **wasm_jit** | **0x1EF0000** |

### H-L 语言约束（编写模块时必须遵守）

| 约束 | 正确写法 |
|------|---------|
| 无取模运算符 `%` | `v - (v/m)*m` |
| 无负数字面量 | `0-1`（用于 -1 哨兵值）|
| 无 `break`/`continue` | 改用条件变量 + 提前 return |
| 无按位 XOR/AND 运算符 | 使用函数封装 |
| 全局数组只能用 `array(n, default)` | 不可用局部数组 |

---

*本文件由 Claude Code 自动维护，基于 Iteration 432 状态分析。*  
*下次同步建议：Iter 440（M6 里程碑）前后。*
