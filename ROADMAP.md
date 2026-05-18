# HicOS Roadmap

## 当前同步基线（迭代 432 实测）

| 指标 | 当前值 |
|---|---:|
| 全部 `.hl` 文件 | **487** |
| `bare-kernel/hl/` 内核模块 | **418** |
| Shell 命令 | **1,744** |
| H-L 总行数 | **~159,650** |
| 最近完成迭代 | **432**（debugger + gdb_stub + breakpoint）|
| 当前阶段 | 第七阶段·生态与自举完善（Phase 7）|

---

## 已完成阶段

### 阶段 1–5（迭代 81–107）：内核核心算法升级 ✅

| 阶段 | 迭代 | 升级 |
|---|---|---|
| 1 内存 | 81–84 | 伙伴系统 / 分级空闲链表 / 哈希LRU / 归并排序 |
| 2 网络 | 86–88 | TCP Reno拥塞 / DNS TTL缓存 / VFS Trie前缀树 |
| 3 多核 | 91–94 | ARP哈希 / inode缓存 / 增强时钟 / Per-CPU队列 |
| 4 调度 | 97–100 | MLFQ / 按需分页+COW / SPSC环形 / TLS 1.3状态机 |
| 5 隔离 | 103–106 | futex哈希队列 / 边缘触发epoll / cgroup强制 / eBPF VM |

### 阶段 6（迭代 109–130）：链接器 + IR + UI ✅

- **109–120**：两趟链接器、IR VM 双执行引擎、execve+ring3、QUIC v1、PTY、内核热补丁框架
- **121–123**：裸机安装（VGA控制台/ATA PIO/USB HID/自安装镜像）
- **124–130**：完整图形桌面（主题/控件/对话框/终端/安装器/系统监控/通知/窗口管理）

### 阶段 7–8（迭代 131–246）：模块大扩展（130→232 模块）✅

116 次迭代，Shell 命令 68→580，新增网络协议/压缩/加密/序列化/文件格式/应用工具。

### 阶段 9（迭代 247–339）：高级数据结构 + 竞赛算法（232→325 模块）✅

| 迭代区间 | 内容 |
|---|---|
| 247–252 | Raft/Gossip/CRDT/gRPC/X.509/PNG/JPEG |
| 253–262 | Bloom/HLL/CMS/Cuckoo/t-Digest/Reservoir/Neural/Attention/Matrix |
| 262–285 | Skip List/一致性哈希/LRU/Merkle/Fenwick/SegTree/Wavelet/DSU/Treap/SAM/KMP/IT/ST/BH/KD/Leftist |
| 286–312 | Dijkstra/BF/Floyd/A*/MaxFlow/BiMatch/Tarjan/Euler/2-SAT/Hungarian/Hopcroft/MinCostFlow/重心/HLD/LCA/虚树/支配树/SAM/Manacher/Eertree/BWT/Lyndon/Z-function |
| 313–339 | ir/regalloc/codegen/io_uring/持久化线段树/回滚DSU/Splay/Mo/平方分解/CHT/矩阵快速幂/数论/字符串哈希/区间DP/博弈/Trie/Li Chao/分治DP/单调队列/SegBeats/LCT/quickselect/NTT/seg_merge/palindrome_dp/knuth_dp/bitset |

### 阶段 10（迭代 340–360）：算法库完善 ✦ **M1 达成** ✅

Miller-Rabin / Pollard-Rho / 线性基 / geometry_2d / 旋转卡壳 / 半平面交 / Dinic / 块割树 / 桥树 / 多项式求逆 / poly_ln_exp / poly_sqrt / 状压DP / 数位DP / 轮廓线DP / Wavelet Tree / Implicit Treap / 珂朵莉树 / 后缀树 / BSGS / 最小圆覆盖

### 阶段 11（迭代 361–375）：编译器深化 ✦ **M2 达成** ✅

pass_gvn / pass_licm / pass_dce2 / regalloc_linear_scan / regalloc_coalesce / calling_conv / type_infer / type_checker / generics / linker_elf / linker_ar / dynamic_linker / dwarf / perf_counter / jit_stub

### 阶段 12（迭代 376–385）：存储引擎 ✦ **M3 达成** ✅

btree / btree_plus / lsm_memtable / wal / mvcc / transaction / index_hash / index_btree / query_plan / db_engine（完整关系型数据库）

### 阶段 13（迭代 386–395）：网络深化 ✅

wireguard / tls13 / http3_quic / dns_over_https / dht / torrent_proto / opentelemetry / prometheus / grpc_stream / websocket_compression

### 阶段 14（迭代 396–405）：机器学习深化 ✦ **M4 达成** ✅

conv2d / pooling / rnn / lstm / autograd / optimizer / tokenizer / embedding / model_serialize / gpu_inference

### 阶段 15（迭代 406–420）：系统稳定性与生产化 ✦ **M5 达成** ✅

| 迭代 | 模块 |
|---|---|
| 406–407 | scheduler_cfs（CFS完全公平）+ numa_alloc（NUMA感知分配）|
| 408–409 | ftrace（函数追踪）+ kprobe（动态内核探针）|
| 410–411 | memory_profiler（内存分析）+ heap_checker（堆越界检测）|
| 412–413 | crash_reporter（崩溃报告）+ core_dump（内核崩溃转储）|
| 414–415 | hotpatch（内核热补丁）+ livepatch（运行时函数替换）|
| 416–418 | power_mgmt（电源管理）+ thermal（热量管理）+ cpufreq（CPU频率）|
| 419–420 | hypervisor（Hypervisor框架）+ vmx（VMX/VT-x支持）|

### 阶段 16（迭代 421–432）：生态与自举完善（进行中）

| 迭代 | 模块 | 状态 |
|---|---|---|
| 421–423 | package_manager + pkg_registry + pkg_build | ✅ |
| 424–426 | hldoc + hltest + hlbench | ✅ |
| 427–429 | lsp_server + syntax_highlight + code_complete | ✅ |
| 430–432 | debugger + gdb_stub + breakpoint | ✅ |

---

## 剩余规划（迭代 433–440）→ M6 目标

### 迭代 433–435：H-L 开发工具

| 迭代 | 模块 | 内容 |
|---|---|---|
| 433 | `hl_repl.hl` | H-L REPL 交互环境（读取-求值-打印循环）|
| 434 | `hl_fmt.hl` | H-L 代码格式化器（缩进/对齐/风格规范化）|
| 435 | `hl_lint2.hl` | 增强 Lint（未使用变量/类型不匹配/复杂度检查）|

### 迭代 436–438：POSIX 兼容层

| 迭代 | 模块 | 内容 |
|---|---|---|
| 436 | `posix_compat.hl` | POSIX 扩展兼容（信号/进程/IO接口）|
| 437 | `musl_shim.hl` | musl libc 接口垫片（标准 C 库接口映射）|
| 438 | `linux_syscall.hl` | Linux 系统调用兼容层（execve/mmap/read/write 等）|

### 迭代 439–440：WebAssembly 运行时 → ✦ M6 目标

| 迭代 | 模块 | 内容 |
|---|---|---|
| 439 | `wasm_runtime.hl` | WebAssembly 字节码解释器（MVP 规范）|
| 440 | `wasm_jit.hl` | WASM JIT 编译（热路径检测 + 即时生成 x86_64）|

**M6 达成条件**（iter 440）：
- 包管理 + LSP + 调试器全部就绪
- POSIX 兼容层完整
- WebAssembly 运行时可运行基础 WASM 程序
- Shell 命令突破 **2,000**

---

## 长期目标（迭代 441+）

| 方向 | 内容 |
|---|---|
| 自举完整性 | H-L 编译器完全用 H-L 编写，消除所有 PowerShell 构建依赖 |
| WASM 后端 | 将 H-L 编译到 WebAssembly，在浏览器中运行 HicOS |
| ARM64 / RISC-V | 后端移植，支持真实开发板启动 |
| 分布式 HicOS | 多节点 Raft 集群，支持分布式文件系统 |
| 网络协议认证 | TCP/IP 通过 RFC 一致性测试 |
| LLVM IR 后端 | 跨平台目标（x86_64 / ARM64 / WASM）|

---

## 里程碑时间线

| 里程碑 | 迭代 | 描述 | 状态 |
|---|---:|---|---|
| M1 | 360 | 竞赛级算法库（Shell >1,200）| ✦ 已达成 |
| M2 | 375 | 自宿主编译器成熟（类型系统+链接器）| ✦ 已达成 |
| M3 | 385 | 完整存储引擎（B+Tree+WAL+MVCC）| ✦ 已达成 |
| M4 | 405 | 完整 ML 框架（训练+推理+GPU）| ✦ 已达成 |
| M5 | 420 | 生产级稳定性（CFS+NUMA+VMX）| ✦ 已达成 |
| M6 | 440 | 完整生态（包管理+LSP+WASM，Shell >2,000）| 🔜 进行中 |
