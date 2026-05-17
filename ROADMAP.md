# HicOS Roadmap

## 当前同步基线（迭代 297 实测）

- `352` 个 `.hl` 文件（~103,800 行）：69 根目录 + 283 内核模块
- `29` 个 PowerShell 脚本（11,193 行）
- `hl-bootstrap.hl`：`4,572` 行 / `208` 函数 | `stdlib.hl`：`1,545` 行 / `143` 函数
- `kernel_entry.hl`：`10,427` 行 / `307` 函数 | `shell.hl`：`4,744` 行
- 编译产出函数：`3,757`（bare-kernel/hl）| Shell 命令：`835`
- 最近完成功能迭代：`297`（tarjan + articulation + euler_path）

## 已完成阶段

### 阶段 0（迭代 73-80）：Shell / 命令迭代
- 环境变量 / 信号 / 历史 / 方向键
- hostname / uname / date / netstat / arp
- Shell pipe + grep（63 个命令）
- 阶段发布整理

### 阶段 1（迭代 81-84）：内存 + 排序算法
| 迭代 | 模块 | 升级 |
|---|---|---|
| 81 | `page_alloc.hl` | 位图 → **伙伴系统** |
| 82 | `kmalloc.hl` | 首次适配 → **分级空闲链表** |
| 83 | `block_cache.hl` | 线性扫描 → **哈希+LRU 双链** |
| 84 | `hilbert_alloc.hl` | 插入排序 → **归并排序** |

### 阶段 2（迭代 86-89）：网络 + 文件系统
| 迭代 | 模块 | 升级 |
|---|---|---|
| 86 | `tcp.hl` | 无流控 → **Reno 拥塞控制+RTT** |
| 87 | `dns.hl` | 无缓存 → **TTL 哈希缓存** |
| 88 | `vfs.hl` | 线性匹配 → **Trie 前缀树** |
| 89 | 文档 | 阶段 2 收敛 |

### 阶段 3（迭代 91-95）：外设 + 多核 + 页面置换
| 迭代 | 模块 | 升级 |
|---|---|---|
| 91 | `arp.hl`+`net.hl` | 线性扫描 → **哈希表** |
| 92 | `ext2.hl` | 每次磁盘读 → **inode 哈希缓存** |
| 93 | `swap.hl` | 基础时钟 → **双链增强时钟** |
| 94 | `smp.hl` | 全局锁 → **Per-CPU 运行队列** |
| 95 | 文档 | 阶段 3 收敛 |

### 阶段 4（迭代 97-101）：调度 + 内存 + 安全
| 迭代 | 模块 | 升级 |
|---|---|---|
| 97 | `sched.hl` | CFS 参数 → **MLFQ 4 级调度器** |
| 98 | `mmap.hl` | 立即分配 → **按需分页 + COW** |
| 99 | `pipe.hl` | 逐字节 → **批量 SPSC 环形缓冲** |
| 100 | `tls.hl` | 空壳 → **8 状态 TLS 1.3 握手** |
| 101 | 文档 | 阶段 4 收敛 |

### 阶段 5（迭代 103-107）：同步 + I/O + 隔离
| 迭代 | 模块 | 升级 |
|---|---|---|
| 103 | `sync.hl` | 空壳 futex → **16 桶哈希等待队列** |
| 104 | `poll.hl` | 水平触发 → **边缘触发 + oneshot + futex 阻塞** |
| 105 | `cgroup.hl` | 被动记账 → **CPU/内存/IO 强制执行 + OOM** |
| 106 | `bpf.hl` | 新建 — **eBPF 寄存器 VM + 5 钩子点** |
| 107 | 文档 | 阶段 5 收敛 |

### 阶段 6（迭代 109-120）：链接器 + 内核解释器 + POSIX
| 迭代 | 模块 | 目标 | 状态 |
|---|---|---|---|
| 109 | `linker.hl` + pipeline | 链接器二次扫描 + stdlib 零警告 | ✅ |
| 110 | `kinterp.hl` | IR 虚拟机执行引擎 | ✅ |
| 111 | `posix.hl` + `usermode.hl` | `execve` + 用户栈 + ring3 跳转 | ✅ |
| 112 | `quic.hl` | QUIC v1 传输协议 | ✅ |
| 113 | `task.hl` + `posix.hl` | `ZOMBIE` 生命周期 + `waitpid(WNOHANG)` | ✅ |
| 114 | `pty.hl` | PTY 真实读写修复 + attach/detach/status | ✅ |
| 115 | 文档 | 阶段 6 文档收敛 | ✅ |
| 116 | `kernel_entry.hl` | 内核自举原型 — `heval` lex→parse→eval | ✅ |
| 117 | `tcp.hl` + `kernel_entry.hl` | TCP 回环自测 — 完整 3-way + data + close | ✅ |
| 118 | `dns.hl` + `kernel_entry.hl` | DNS 回环自测 — 查询→解析→缓存→命中→过期→static | ✅ |
| 119 | `advanced_verify.hl` + commands + gate | eBPF / TLS / QUIC 从源码存在→已验证接入 | ✅ |
| 120 | `kmod.hl` + commands | 内核热补丁 — 64 模块槽 + 256 trampoline + 原子热替换 | ✅ |

### 阶段 7（迭代 125-130）：UI 桌面环境
| 迭代 | 模块 | 目标 | 状态 |
|---|---|---|---|
| 125 | `ui_theme.hl` | 统一视觉基线（Slate 配色系统） | ✅ |
| 126 | `wm.hl` | 窗口交互（焦点/提升/拖拽/关闭/最小化） | ✅ |
| 127 | `ui_controls.hl` + `ui_terminal.hl` | 控件系统 + 图形终端 | ✅ |
| 128 | `ui_dialog.hl` + `ui_desktop.hl` | 模态对话框 + 桌面编排层 | ✅ |
| 129 | `wm.hl` + `ui_installer.hl` | 窗口标题文字 + 5 步图形安装器 | ✅ |
| 130 | `ui_sysmon.hl` + `ui_notify.hl` | 系统监控 + Toast 通知 + IPC 完善 | ✅ |

### 阶段 8（迭代 131-246）：模块大扩展（130→232 模块）

通过 116 次持续迭代，系统模块从 130 个扩展到 232 个，每次迭代添加 3 个新模块：

**网络协议**：HTTP/HTTPS、WebSocket、Telnet、SMTP、POP3、IMAP、IRC、FTP、NTP、MQTT、RADIUS、LDAP、SIP、RTSP、STUN、RTP、SOCKS、DHCP Server

**压缩算法**：LZ4、Huffman、RLE、ZLIB、LZMA、Bzip2、Snappy、Zstd、Brotli

**加密全覆盖**：AES、ChaCha20、SM4、RSA、Ed25519、MD5、SHA1、SHA256、BLAKE2、SM3、xxHash、SipHash、HMAC、Poly1305、Bcrypt、Scrypt、Argon2、PBKDF2

**序列化**：Protocol Buffers、Apache Avro、CBOR、ASN.1、MessagePack

**编码格式**：Base64、Base32、Hex、URL、Quoted-Printable、UUencode、PEM、JWT

**文件格式**：BMP、GIF、WAV、CPIO、TAR

**应用功能**：SQLite、Diff、INI、CSV、Profiler、Ping、Traceroute、Semaphore、Cron、RSS

**阶段成果**：模块 130→232 | Shell 命令 68→580 | 代码行 46,499→~80,300

### 阶段 9（迭代 247-297）：高级数据结构 + 图算法（232→283 模块）✅

通过 50 次持续迭代，系统模块从 232 个扩展到 283 个：

**分布式基础**（iter 247-252）：
- `raft.hl`、`gossip.hl`、`crdt.hl`、`grpc.hl`、`x509.hl`、`png.hl` / `jpeg.hl`

**概率数据结构**（iter 253-262）：
- `bloom_filter.hl`、`hyperloglog.hl`、`count_min_sketch.hl`
- `cuckoo_filter.hl`、`tdigest.hl`、`reservoir_sampling.hl`

**神经网络/矩阵**（iter 256-261）：
- `neural.hl`、`attention.hl`、`matrix.hl`

**高级数据结构**（iter 262-279）：
- `skiplist.hl`、`consistent_hash.hl`、`lru_cache.hl`、`merkle_tree.hl`
- `fenwick_tree.hl`、`segment_tree.hl`、`wavelet.hl`
- `disjoint_set.hl`、`treap.hl`、`suffix_array.hl`
- `aho_corasick.hl`、`kmp.hl`、`interval_tree.hl`

**空间/查询结构**（iter 280-285）：
- `sparse_table.hl`（O(1) RMQ）、`binary_heap.hl`（Floyd+Heapsort）、`kd_tree.hl`（2D 最近邻）
- `leftist_heap.hl`（可合并堆）、`lcs.hl`（DP 三合一）、`convex_hull.hl`（Andrew 单调链）

**图算法系列**（iter 286-297）：
| 迭代 | 模块 | 算法 | 复杂度 |
|---|---|---|---|
| 286 | `dijkstra.hl` | Dijkstra 单源最短路 | O(V²) |
| 287 | `topological_sort.hl` | Kahn BFS 拓扑排序 + 环检测 | O(V+E) |
| 288 | `bellman_ford.hl` | Bellman-Ford 负权 + 负权环检测 | O(VE) |
| 289 | `prim.hl` | Prim MST 线性扫描 | O(V²) |
| 290 | `kruskal.hl` | Kruskal MST + DSU 路径压缩 | O(E log E) |
| 291 | `floyd_warshall.hl` | Floyd-Warshall 全对最短路 | O(V³) |
| 292 | `a_star.hl` | A* 启发式搜索 Manhattan 距离 | O(V²) |
| 293 | `max_flow.hl` | Edmonds-Karp 最大流 | O(VE²) |
| 294 | `bipartite_match.hl` | 增广路 DFS 二部图最大匹配 | O(VE) |
| 295 | `tarjan.hl` | Tarjan SCC disc/low-link | O(V+E) |
| 296 | `articulation.hl` | 关节点 + 桥 low-link 无向图 | O(V+E) |
| 297 | `euler_path.hl` | Hierholzer 欧拉路径/回路 | O(E) |

**阶段成果**：
- 模块数：232 → 283（增长 22%）
- Shell 命令：580 → 835（增长 44%）
- 代码行数：~80,300 → ~103,800（增长 29%）
- 内核函数：2,200 → 3,757（增长 71%）

---

## 阶段 10：图论进阶 + 字符串高级算法（迭代 298-312）🔜

### 图论进阶（iter 298-306）
| 迭代 | 模块 | 算法 | 说明 |
|---|---|---|---|
| 298 | `two_sat.hl` | 2-SAT 问题（基于 SCC） | O(V+E)，Kosaraju/Tarjan |
| 299 | `hungarian.hl` | 匈牙利算法（最优分配） | O(n³)，带权二部图最小代价匹配 |
| 300 | `hopcroft_karp.hl` | Hopcroft-Karp 二部图匹配 | O(E√V)，BFS 分层 + DFS 增广 |
| 301 | `min_cost_flow.hl` | 最小费用最大流（SPFA） | O(VEf)，cost+flow 双目标 |
| 302 | `centroid.hl` | 树重心分解 | O(n log n)，树路径查询 |
| 303 | `heavy_light.hl` | 重链剖分（HLD） | O(log²n)，树上路径/区间更新 |
| 304 | `lca.hl` | 最近公共祖先（倍增 + Euler+RMQ） | O(n log n) 预处理，O(1)/O(log n) 查询 |
| 305 | `virtual_tree.hl` | 虚树（关键点树） | 稀疏关键点树形 DP |
| 306 | `dominator.hl` | 支配树（Lengauer-Tarjan） | O(E log V)，编译器后端用 |

### 字符串高级算法（iter 307-312）
| 迭代 | 模块 | 算法 | 说明 |
|---|---|---|---|
| 307 | `suffix_automaton.hl` | 后缀自动机（SAM） | O(n)，子串计数/最长公共子串 |
| 308 | `manacher.hl` | Manacher 算法最长回文子串 | O(n)，回文中心扩展 |
| 309 | `eertree.hl` | 回文树（Eertree/Palindromic Tree） | O(n)，回文子串统计 |
| 310 | `burrows_wheeler.hl` | Burrows-Wheeler 变换（BWT） | O(n log n)，压缩预处理 |
| 311 | `lyndon.hl` | Lyndon 分解（Duval 算法） | O(n)，字典序旋转最小表示 |
| 312 | `z_function.hl` | Z 函数 / Z-Array | O(n)，模式匹配加速 |

**预期成果**（iter 312 完成后）：
- 模块数：283 → 298
- Shell 命令：835 → ~910
- 代码行数：~103,800 → ~108,000

---

## 阶段 11：系统级强化（迭代 313-327）📋 规划中

### 编译器 / 运行时强化
| 迭代 | 模块 | 目标 |
|---|---|---|
| 313 | `ir.hl` | SSA 形式中间表示 + phi 节点 |
| 314 | `regalloc.hl` | 图着色寄存器分配（Chaitin-Briggs） |
| 315 | `codegen.hl` | 指令调度 + 窥孔优化 |

### 内核安全强化
| 迭代 | 模块 | 目标 |
|---|---|---|
| 316 | `seccomp.hl` | 系统调用过滤（BPF 规则表） |
| 317 | `namespace.hl` | 进程命名空间（PID/Mount/Net/UTS） |
| 318 | `secure_boot.hl` | UEFI Secure Boot + 签名验证链 |

### 存储 + 虚拟化
| 迭代 | 模块 | 目标 |
|---|---|---|
| 319 | `nvme.hl` | NVMe 命令队列 + 中断完成 |
| 320 | `virtio_blk.hl` | virtio-blk 块设备驱动优化 |
| 321 | `overlay_fs.hl` | OverlayFS 联合文件系统 |

### 网络高级功能
| 迭代 | 模块 | 目标 |
|---|---|---|
| 322 | `netfilter.hl` | 包过滤 + NAT 规则表 |
| 323 | `ipv6.hl` | IPv6 路由 + NDP + 无状态配置 |
| 324 | `wifi.hl` | Wi-Fi 802.11 帧 + WPA2 握手 |

### 多媒体 + GPU
| 迭代 | 模块 | 目标 |
|---|---|---|
| 325 | `gpu.hl` | GPU 2D 加速 + framebuffer blit |
| 326 | `audio.hl` + `mixer.hl` | AC97 PCM 播放 + 音频混合 |
| 327 | 文档 | 阶段 11 收敛 |

**预期成果**（iter 327 完成后）：
- 模块数：298 → 313
- Shell 命令：~910 → ~980
- 代码行数：~108,000 → ~114,000

---

## 长期目标（迭代 328+）

| 方向 | 内容 |
|---|---|
| 自举完整性 | H-L 编译器完全用 H-L 编写，消除所有外部依赖 |
| WASM 后端 | 将 H-L 编译到 WebAssembly，在浏览器中运行 HicOS |
| 网络协议栈认证 | TCP/IP 协议栈通过 RFC 一致性测试套件 |
| 分布式 HicOS | 多节点 Raft 集群，支持分布式文件系统 |
| 正式验证 | 核心内存分配器用 Coq/Lean 辅助证明正确性 |
| 硬件移植 | ARM64 / RISC-V 后端，支持真实开发板启动 |

---

## 当前推荐执行顺序

```powershell
.\hl-bootstrap.cmd test
powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1
```

## 相关文件

- `PROJECT_STATUS.md`
- `CHANGELOG.md`
- `PROJECT_ADVANCEMENT_PLAN.hl`
- `COMPILER_PIPELINE_STRATEGY.hl`
