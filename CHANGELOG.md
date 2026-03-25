# HicOS Changelog

## Current Snapshot

- `.hl` 文件：`179`（63 根目录 + 116 内核模块）
- H-L 总行数：`47,655`
- 内核模块：`116`（函数 1,503 个，源码计数）
- Shell 命令数：`63` + pipe 操作符
- `scripts/*.ps1`：`22`（8,646 行）
- 编译：`118/118` 模块 | 0 parse warning | 1 unresolved reloc | 1,797 符号
- 构建/测试主入口：`scripts/hl-bootstrap-build-test.ps1`
- 最近完成迭代：`117`

## Iteration 117 — TCP 回环自测

- **`tcp.hl`**: 新增 TCP loopback 自测框架
  - `tcp_loopback_test()`: 在 127.0.0.1 上执行完整 3-way 握手 + 数据交换 + FIN 关闭
  - `_tcp_lo_build_seg()`: 构建回环用最小 TCP 段（20B 头 + payload）
  - `tcp_loopback_status()`: 状态摘要输出
  - 验证路径: LISTEN→SYN→SYN_RCVD→ACK→ESTABLISHED→DATA("HELLO" 5B)→FIN→CLOSE_WAIT
- **`kernel_entry.hl`**: 新增 `_ke_cmd_tcploop` + 命令分发 + 帮助文本
- **`shell.hl`**: 新增 `tcploop` 命令
- **编译结果**: 118/118 模块 | 1,797 符号 | 1,492 functions found | 0 warning

## Iteration 116 — 内核自举原型：heval 命令

- **`kernel_entry.hl`**: 新增 `heval` 命令 — 内核级 lex→parse→eval 自举原型
  - `_ke_cmd_heval(buf_addr, buf_len)`: 从命令缓冲区提取 H-L 表达式，调用 `kinterp_exec()` 在裸机内核中执行
  - 帮助文本第 13 行新增 `heval`
  - 命令分发表接入 `heval` 匹配（`buf_len >= 5`）
  - 证明内核可以作为自身语言的実时解释器宿主
- **`shell.hl`**: 新增 `heval <expr>` 命令，调用 `kinterp_exec()` 执行
- **编译结果**: 118/118 模块 | 1,793 符号 | 1,488 functions found | 0 warning

## Iteration 115 — 阶段 6 文档收敛

- 全量 md 文件与策划案强制对齐到项目实际状态
- 门禁全通过：`hl-bootstrap-build-test` ✅ / `release-validate` 18/18 ✅

## Iteration 114 — PTY 基础闭环修复

- **`pty.hl`**: 真实 PTY ring buffer 读写路径接通
  - 修复 `pty_master_write` / `pty_slave_read` / `pty_slave_write` / `pty_master_read` 中 `addr` 未定义的真实 bug
  - `pty_buf_addr()` 现在实际参与双向缓冲读写
  - 新增 `pty_attach()` / `pty_detach()`
  - 新增 `pty_info()` / `pty_status()`
  - 新增 `pty_master_task` / `pty_slave_task` 绑定信息
- **`shell.hl`**: `pty` 命令改为走 `pty_status()`
- **`posix.hl`**: 新增 `FD_PTY_MASTER` / `FD_PTY_SLAVE`
- **编译结果**: 118/118 模块 | 1,792 符号 | 1,487 functions found | 0 warning

## Iteration 113 — 进程生命周期完善

- **`task.hl`**: 进程退出/回收模型升级
  - 新增 `STATE_ZOMBIE` 与 `parent_idx` 生命周期字段
  - `task_exit()`：退出后进入 ZOMBIE，而不是直接销毁
  - `task_reap()`：父进程 `wait()` 后真正回收任务槽位
  - `task_find_by_pid()`：PID → task slot 查询辅助
  - 修复任务槽位回收：`FREE/DEAD/ZOMBIE` 可重新进入分配路径
- **`posix.hl`**: `wait` / `fork` 语义增强
  - 新增 `sys_waitpid(child_pid, options)`
  - 支持 `WNOHANG` 非阻塞等待
  - `sys_wait(-1)` 支持等待任意子进程
  - `sys_fork()` 集成 `mmap_cow_fork()`，按父任务 mmap 区域逐个建立 COW
  - 修复此前把 `current_task` 错传为 `mmap_cow_fork(parent_region, child_task)` 的 region 参数问题
- **编译结果**: 118/118 模块 | 1,788 符号 | 1,483 函数 | 0 warning

## Iteration 112 — QUIC 传输协议

- **`quic.hl`**: 新建 — **QUIC v1 传输协议**（RFC 9000）
  - 16 连接槽位 × 16 双向流/连接
  - 1-RTT 握手：Initial → Handshake → Established （6 状态机）
  - 流多路复用：`quic_stream_open/send/recv` 带流级流控
  - 包保护：AEAD 加密密钥派生（CID 混合）
  - 拥塞控制：NewReno 慢启动 + 拥塞避免
  - RTT 估算：Jacobson/Karels 自适应 RTO
  - ACK 帧处理 + CONNECTION_CLOSE
  - STREAM 帧解析（offset/length/FIN 标志）
  - 连接级 + 流级双层流控
  - `quic_status()` / `quic_conn_info()` 诊断
  - 22 个函数，440+ 行
- **编译结果**: 118/118 模块 | 1,785 符号 | 1,480 函数 | 0 warning

## Iteration 111 — execve + 用户态地址空间初始化

- **`posix.hl`**: 新增 `sys_execve(path, argv, envp)`
  - 完整 POSIX execve 语义：加载 ELF + argc/argv/envp 栈构建 + 用户态跳转
  - 用户栈布局：字符串区 → envp 指针数组 → argv 指针数组 → argc
  - 栈地址 0x7FF000（与内核地址空间隔离）
  - FD 3+ 自动关闭，stdin/stdout/stderr 保留
  - 调用 `enter_usermode()` 实现 ring0 → ring3 IRETQ 跳转
- **`syscall.hl`**: 新增 `SYS_EXECVE = 9` 并接入分发表
- **`usermode.hl`**: execve 集成文档更新
- **编译结果**: 117/117 | 1,763 符号 | 1,458 函数 | 0 warning

## Iteration 110 — kinterp IR 虚拟机执行引擎

- **`kinterp.hl`**: 从 745 行/31 函数升级为 **1,342 行/51 函数**
  - 新增 **IR 虚拟机执行引擎** (`kirvm_*`)：512 寄存器文件 + 32 层调用栈
  - `kirvm_exec_from`: 支持全部 IR 算术/比较/控制流/调用/返回指令
  - `kirvm_scan_labels`: 预扫描 IR 标签建立 PC 映射表
  - `kinterp_exec_ir`: 完整 IR 管道 — lex → parse → AST → IR lower → optimize → VM 执行
  - `_kirvm_parse_*`: 为 IR 路径实现的完整递归下降解析器，生成 `ir_lower_*` 兼容 AST
  - 双执行引擎：树遍历（`kinterp_exec`）+ IR VM（`kinterp_exec_ir`）
  - 100,000 步安全上限，防止无限循环
- **编译结果**: 117/117 模块 | 1,762 符号 | 1,457 函数 | 0 warning

## Iteration 109 — 链接器二次扫描 + stdlib 修复

- **`hl-compile-pipeline.ps1`**: 链接器深化
  - `Link-PreScan`: 编译前预扫描所有 .hl 源文件的 `fn` 声明，构建前向声明表
  - `Link-GenerateStubs`: 为语言内建函数和前向声明生成 stub trampoline
  - 未解析重定位从 **120 → 1**（降低 99.2%）
  - 已解析重定位从 **114 → 264**（增加 131%）
- **`linker.hl`**: 内核侧链接器升级
  - `linker_register_builtins`: 内建函数 stub 注册
  - `linker_register_fwd_stubs`: 前向声明 stub 注册
  - `linker_pass2_enhanced`: 增强型二次解析
- **`stdlib.hl`**: Parse warning 修复
  - 消除 2 条嵌套 `fn` 闭包导致的 parse warning
  - `cache()` / `deprecated()` 改为平铺函数结构
  - stdlib 首次完整编译，贡献 **2,117 B** 到 kernel.bin
- **编译结果**: 117/117 全量零警告编译
- **`EVOLUTION_PLAN.hl`**: 新建 — 全量审计型系统进化策划案（9 章）

## Iteration 107 — 阶段 5 收敛

- 全部文档重新采集并同步到仓库实际状态
- `manifest.hl` 修正：`SHELL_COMMANDS` 87→63，`BOOT_IMAGE_BYTES` 152064→156160
- `PROJECT_STATUS.md`：全量更新（177 HL / 40,742 行 / 115 模块 / 1,435 函数）
- `ROADMAP.md`：阶段 5 全部标记已完成
- `PROJECT_ADVANCEMENT_PLAN.hl`：阶段 5 完成记录 + 阶段 6 路线
- 五阶段共 19 个内核模块算法升级全部入账
- 门禁全通过（hl-bootstrap + validate + boot + image + runtime + smoke）

## Iteration 106 — BPF 内核可编程过滤

- **`bpf.hl`**: 新建 — **eBPF 风格寄存器虚拟机**
  - 10 寄存器 + PC，16 种指令（算术/逻辑/跳转/内存/EXIT）
  - 程序加载（验证 EXIT 结尾）、卸载、附加到 5 个钩子点
  - `bpf_run`: 安全沙箱执行（10000 步上限）
  - `bpf_run_hook`: 在 SYSCALL/NET_RX/NET_TX/SCHED 钩子运行
  - Per-program key-value map（16 对）
  - manifest 更新：115 内核模块 / 177 HL 文件

## Iteration 105 — Cgroup v2 资源强制执行

- **`cgroup.hl`**: 被动记账升级为 **主动强制执行**
  - CPU: 每周期配额（ticks），`cgroup_tick()` 计费，超限节流
  - Memory: 硬限制 + OOM killer 钩子（杀最年轻进程）
  - I/O: 带宽限制（字节/周期），`cgroup_check_io()` 节流
  - PIDs: 最大任务数限制
  - `cgroup_period_reset()` 周期性重置计费（由 timer 调用）
  - `cgroup_detach()` / `cgroup_list()` / 增强 `cgroup_status()`

## Iteration 104 — Epoll 边缘触发 + Futex 阻塞

- **`poll.hl`**: 升级为 **边缘触发 + oneshot + futex 阻塞等待**
  - `EPOLLET`: 仅在状态变化时报告事件（vs 水平触发每次都报告）
  - `EPOLLONESHOT`: 事件后自动禁用 fd
  - `sys_epoll_wait` 无事件时用 `futex_wait_timeout` 阻塞
  - 唤醒后重新扫描就绪 fd
  - 每实例 edge-trigger 历史记录数组

## Iteration 103 — Futex 哈希桶等待队列

- **`sync.hl`**: 空壳 futex 升级为 **16 桶哈希等待队列**
  - `futex_wait`: 原子检查值 + 入队当前任务 + 阻塞（spin 模拟）
  - `futex_wake`: 从桶中出队最多 N 个等待者，标记 READY
  - `futex_wait_timeout`: 带超时的等待，超时后自动移除
  - `futex_requeue`: 将等待者从 addr1 迁移到 addr2（condvar 优化）
  - 16 个哈希桶 × 256 最大等待者，链表管理
  - mutex/semaphore/rwlock 全部改用真正的 futex_wait 阻塞
  - `sync_status()` 统计等待/唤醒次数
  - 26 个函数编译通过，构建 + 冒烟通过

## Iteration 101 — 阶段 4 收敛（数据修正版）

- 全部文档重新采集并同步到仓库实际状态
- **数据修正**：此前 .hl 文件计数 290 → 实际 176，行数 70K → 实际 40K（glob 重叠导致重复计数）
- `PROJECT_STATUS.md`：全量更新（176 HL / 40,073 行 / 155,648 img / 23,183 kernel.bin）
- `ROADMAP.md`：重写为阶段 0/1/2/3/4 已完成 + 阶段 5 规划
- `PROJECT_ADVANCEMENT_PLAN.hl`：补充迭代 97-101 完成记录 + 阶段 5 路线
- 四阶段共 15 个内核模块算法升级全部入账
- 门禁全通过（hl-bootstrap + validate + boot + image + runtime + qemu-smoke）

## Iteration 100 — TLS 1.3 握手状态机

- **`tls.hl`**: 空壳 connect 升级为 **8 状态 TLS 1.3 握手状态机**
  - IDLE → CH_SENT → SH_RECV → EE_RECV → CERT → FIN_RECV → CF_SENT → ESTABLISHED
  - X25519 密钥生成 + 共享密钥派生
  - HKDF 握手密钥 → 应用密钥派生（读/写分离）
  - 应用数据加密/解密 + HMAC-GCM 标签
  - `tls_close()` 发送 close_notify alert
  - `https_get()` 完整链路：DNS → TCP → TLS → HTTP GET
  - 8 会话槽位，`tls_status()` 显示活跃/已建立

## Iteration 99 — Pipe SPSC 环形缓冲区

- **`pipe.hl`**: 逐字节元数据更新升级为 **批量 memcpy + lock-free SPSC**
  - `pipe_write_batch`/`pipe_read_batch`: 分段复制（开端+绕回）
  - writer 拥有 write_pos，reader 拥有 read_pos（无锁）
  - 读/写端分离引用计数（`pipe_close_read`/`pipe_close_write`）
  - 生命周期字节统计 + `pipe_status()`

## Iteration 98 — mmap 按需映射 + COW

- **`mmap.hl`**: 立即分配全部物理页升级为 **按需分页 + Copy-on-Write**
  - `sys_mmap()`: 仅记录区域，不分配物理页（懒惰）
  - `mmap_fault()`: 首次访问时按需分配单页，匿名置零 / 文件回填
  - `mmap_cow_fork()`: fork 后父子共享物理页（只读），写时复制
  - COW 引用计数数组（512 页）：引用>1 时复制，=1 时直接变可写
  - `sys_munmap()` 感知 COW：引用计数到 0 才释放物理页
  - `mmap_status()` 显示活跃/COW/跟踪页统计
  - 13 个函数编译通过，构建 + 冒烟通过

## Iteration 97 — 多级反馈队列调度器 (MLFQ)

- **`sched.hl`**: CFS 参数模块升级为 **4 级 MLFQ 调度器**
  - 4 个优先级队列（L0-L3），时间片 2/4/8/16ms 递增
  - 新任务进入 L0；耗尽时间片降级；I/O 让出可升级
  - 周期性 boost：每 10000 tick 全部重置到 L0（防饥饿）
  - `mlfq_init/insert/pick/demote/yield/tick/boost/status` 全套 API
  - CFS 兼容保留：`nice_to_weight`/`calc_slice`/`update_vruntime`
  - 15 个函数编译通过，构建 + 冒烟通过

## Iteration 95 — 阶段 3 收敛

- 全部文档重新采集并同步到仓库实际状态
- `PROJECT_STATUS.md`：数据全量更新（290 HL / 69K 行 / 22 PS1 / 155KB img / 22KB kernel.bin）
- `ROADMAP.md`：重写为阶段 0/1/2/3 已完成 + 阶段 4 规划
- `PROJECT_ADVANCEMENT_PLAN.hl`：补充迭代 91-95 完成记录 + 阶段 4 路线
- 三阶段共 11 个内核模块算法升级全部入账
- 门禁全通过（hl-bootstrap + validate + boot + image + runtime + qemu-smoke）

## Iteration 94 — SMP Per-CPU 运行队列

- **`smp.hl`**: 全局调度锁升级为 **Per-CPU 环形运行队列 + 负载均衡**
  - 每 CPU 32 槽位环形队列，O(1) 入队/出队
  - `sched_enqueue()`: 自动选择最轻载 CPU 入队
  - `sched_dequeue()`: 本地 CPU 无竞争出队
  - `sched_balance()`: 负载差 >1 时从最重迁移到最轻
  - Per-CPU 自旋锁（每 CPU 独立锁地址）
  - `sched_runq_status()` 显示各 CPU 队列长度
  - 21 个函数编译通过，构建 + 冒烟通过

## Iteration 93 — 增强型时钟页面置换

- **`swap.hl`**: 基础时钟扫描升级为 **双链 Active/Inactive 增强型时钟算法**
  - Active 链表（最近访问，保护不驱逐，上限 256 帧）
  - Inactive 链表（驱逐候选，时钟指针扫描）
  - 提升：inactive 帧 ref=1 → 移到 active 头部
  - 降级：active 溢出 → 尾部移到 inactive
  - 驱逐：inactive 帧 ref=0 → swap out（第二次机会）
  - 新增 `swap_status()` 显示 active/inactive 计数
  - `demand_page()` 自动注册新帧到 active 链
  - 15 个函数编译通过，构建 + 冒烟通过

## Iteration 92 — ext2 Inode 哈希缓存

- **`ext2.hl`**: 每次磁盘读取 inode 升级为 **O(1) 哈希缓存 + 按需磁盘回填**
  - 64 条目缓存 + 16 桶分离链哈希（inode_num % 16）
  - `ext2_read_inode()`: 先查缓存 O(1)，命中直返；未命中读盘并插入缓存
  - 新增 `ext2_icache_status()` 显示命中/未命中统计
  - `ext2_init()` 时自动初始化缓存
  - 22 个函数编译通过，构建 + 冒烟通过

## Iteration 91 — ARP 哈希表缓存

- **`arp.hl`**: O(n) 线性扫描升级为 **O(1) 16 桶分离链哈希表**
  - 32 条目缓存池 + 16 桶哈希（IP % 16）
  - `arp_lookup()` / `arp_update()`: O(1) 平均
  - 满缓存时驱逐 slot 0
  - 加载时自动初始化（`_arp_cache_init()`）
- **`net.hl`**: 内联 ARP 同步升级为 16 桶哈希
  - `arp_init()` / `arp_lookup()` / `arp_update()` 全部重写
  - 保持 `arp_input()` 调用方不变
- 阶段 3 开始，构建 + 冒烟通过

## Iteration 89 — 阶段 2 收敛

- 全部文档重新采集并同步到仓库实际状态
- `PROJECT_STATUS.md`：数据全量更新（290 HL / 68K 行 / 22 PS1 / 154KB img / 22KB kernel.bin）
- `ROADMAP.md`：重写为阶段 0/1/2 已完成 + 阶段 3 规划
- `PROJECT_ADVANCEMENT_PLAN.hl`：补充迭代 81-89 完成记录 + 阶段 3 路线
- 门禁全通过（hl-bootstrap + validate + boot + runtime + qemu-smoke）

## Iteration 88 — VFS Trie 前缀树挂载解析

- **`vfs.hl`**: 挂载点解析从 O(n) 线性扫描升级为 **O(depth) Trie 前缀树**
  - 32 节点 Trie，按路径组件分层（"dev"、"mnt"、"disk0"）
  - `vfs_mount()` 同时插入挂载表 + Trie
  - `vfs_resolve()`: 分割路径 → 逐组件走 Trie → 跟踪最深挂载点
  - 新增 `_vfs_split_path()` / `_trie_init()` / `_trie_insert_path()` / `_trie_find_child()`
  - 18 个函数编译通过，所有调用方无需修改

## Iteration 87 — DNS TTL 哈希缓存

- **`dns.hl`**: 无缓存直查升级为 **O(1) 哈希表 + TTL 过期缓存**
  - 32 桶分离链哈希 + 64 条目缓存池
  - `dns_resolve()`: 先查缓存 O(1)，命中直接返回；未命中走查询路径
  - TTL 自动过期：基于 tick 计数器（100Hz），过期条目懒清除
  - DJB2 哈希函数，按域名 label 逐字符计算
  - 新增 `dns_cache_result()` / `dns_cache_flush()` / `dns_cache_status()`
  - 13 个函数编译通过

## Iteration 86 — TCP Reno 拥塞控制

- **`tcp.hl`**: 无流控 TCP 升级为 **TCP Reno 拥塞控制 + Jacobson/Karels RTT 估算**
  - 慢启动：cwnd < ssthresh 时 cwnd += MSS per ACK（指数增长）
  - 拥塞避免：cwnd >= ssthresh 时 cwnd += MSS²/cwnd per ACK（线性增长）
  - 快速重传：3 个重复 ACK → ssthresh = cwnd/2, cwnd = ssthresh + 3*MSS
  - 快速恢复：后续重复 ACK cwnd += MSS
  - 超时处理：cwnd = 1*MSS, RTO 指数退避
  - Jacobson/Karels RTT：SRTT/RTTVAR 定点数估算，RTO = SRTT/8 + 4*RTTVAR
  - 滑动窗口：tcp_send 按 min(cwnd, rwnd) 限制发送
  - TCB 布局 +128~+191 填充拥塞控制状态（利用原 reserved 空间）
  - 新增 `tcp_cc_info()` 供 netstat 显示拥塞状态
  - 17 个函数编译通过，QEMU 冒烟通过

## Iteration 84 — Hilbert 空间分配器归并排序

- **`hilbert_alloc.hl`**: 初始化排序从 O(n²) 插入排序升级为 **O(n log n) 自底向上迭代归并排序**
  - `_hl_merge_sort()`: 非递归自底向上归并，避免深层递归栈溢出
  - `_hl_merge()`: 双指针合并子数组
  - `hilbert_page_free()`: 从无序 append 升级为 **二分查找插入点** + 顺序插入，维持排序不变量
  - 内置自测：5 元素归并排序正确性验证
  - 7 个函数编译通过，构建 + 冒烟通过

## Iteration 83 — 哈希+LRU 块缓存

- **`block_cache.hl`**: 从 O(n) 线性扫描升级为 **O(1) 哈希表 + O(1) LRU 双向链表**
  - 64 桶分离链哈希表：`bcache_lookup()` 平均 O(1)（原 O(64) 全表扫描）
  - 数组模拟双向链表：`bcache_evict_lru()` O(1) 移除尾节点（原 O(64) 找最小 age）
  - 访问提升：`_lru_promote()` O(1) 移到链表头部
  - 17 个函数编译通过，无需修改调用方（ext2/fat16/kernel_entry/shell）
- 构建 + 冒烟 + 全门禁通过

## Iteration 82 — 分级空闲链表堆分配器

- **`kmalloc.hl`**: 从 O(n) 首次适配扫描升级为 **O(1) 分级空闲链表（Segregated Free-List）**
  - 8 个 slab 尺寸类别：32, 64, 128, 256, 512, 1024, 2048, 4096 字节
  - `kmalloc(size)`: O(1) 从对应类别空闲链表弹出（首次触发时自动从 buddy 分配页并切块）
  - `kfree(ptr)`: O(1) 压回对应类别空闲链表
  - 大分配（>2048 字节）直接委托 `page_alloc_contiguous`
  - `krealloc()` 优化：原地缩小不触发重分配
  - `kmalloc_stats()` 返回格式不变，扫描 8 个类别 O(k) 替代 O(n) 堆遍历
  - 构建于迭代 81 伙伴系统之上：空闲链表耗尽时调用 `page_alloc()` 申请新页
- 11 个函数编译通过，114 模块构建成功
- `shell.hl` 的 `heap` 命令继续正常工作（`kmalloc_stats` 返回格式兼容）

## Iteration 81 — 伙伴系统页帧分配器

- **`page_alloc.hl`**: 从 O(n) 位图线性扫描升级为 **O(log n) 伙伴系统（Buddy Allocator）**
  - 10 级 free list（order 0=4KB .. order 9=2MB）
  - `page_alloc()`: O(1) 单页分配（从 order-0 free list 弹出）
  - `page_alloc_contiguous(count)`: O(log n) 连续分配（分配 2^⌈log₂(count)⌉ 块，返还多余页）
  - `page_free()`: O(log n) 释放 + 自动伙伴合并（XOR 定位 buddy，递归向上合并）
  - `page_count_free()`: O(1)（维护计数器，不再扫描位图）
  - 保留位图层用于 E820 内存映射初始化兼容
  - 两条初始化路径：快速路径（无 E820，直接构建最大对齐块）、慢速路径（从位图构建）
  - 连续分配的每页标记为 order-0，支持调用方逐页释放（向后兼容 firmware.hl、hlc_loader.hl 等）
- 所有 24 个函数编译通过，114 个内核模块构建成功
- 公共 API 签名完全不变，所有调用方无需修改

## Iteration 80 — 阶段发布整理

- `README.md`、`PROJECT_STATUS.md`、`ROADMAP.md`、`CHANGELOG.md`、`PROJECT_ADVANCEMENT_PLAN.hl` 统一同步到迭代 `80`
- 重新核对当前仓库规模与阶段指标：
  - `176` 个活跃 `.hl` 文件
  - `114` 个内核模块
  - `61` 个 Shell 命令 + pipe 操作符
  - `kernel_entry.hl` 达到 `10404` 行、`301` 个函数、`66` 个原生命令
- Host-side 门禁复核：
  - `validate-workspace.ps1` ✅
  - `boot-readiness.ps1` ✅
  - `runtime-path-readiness.ps1` ✅
  - `image-layout-readiness.ps1` ✅
  - `boot-binary-analysis.ps1` ✅
  - `perf-baseline.ps1` ✅
  - `release-validate.ps1` ✅
  - `hl-bootstrap-build-test.ps1` ✅
- `qemu-boot-test.ps1` / `qemu-uefi-test.ps1` 因当前环境未安装 QEMU 标记为跳过，不再误写为“失败”或“已完整通过”

## Iteration 79 — grep

- `kernel_entry.hl` 新增原生 `grep` 命令：
  - `_ke_grep_match(line_addr, line_len, pat_addr, pat_len)` — 子串匹配
  - `_ke_cmd_grep(buf_addr, buf_len)` — 过滤管道捕获缓冲区中的行
- `_ke_putc()` 内部集成管道捕获标志检查（捕获模式时输出到缓冲区，不输出到串口）
- `_ke_pipe_exec()` 简化：左侧命令输出被捕获，右侧命令可读取并过滤
- 典型用法：`help | grep tick`、`ps | grep SYN`
- `shell.hl` 命令数 60 → 61

## Iteration 78 — Shell Pipe

- `kernel_entry.hl` 新增 shell pipe 基础设施：
  - `_ke_find_pipe(buf_addr, buf_len)` — 扫描命令缓冲区中的 `|` 字符
  - `_ke_pipe_exec(buf_addr, buf_len)` — 分割并依次执行 `cmd1 | cmd2`
  - `_ke_pipe_cap_start()` / `_ke_pipe_cap_stop()` — 输出捕获控制
  - `_ke_putc_pipe(ch)` — 可切换输出目标（串口 / 捕获缓冲区）
- 管道捕获缓冲区 4KB @ 0x370000
- `_ke_shell()` enter 处理增加 pipe 检测：遇到 `|` 自动拆分执行
- `_ke_sc2ascii()` 新增 `|` `[` `]` `` ` `` 按键映射
- 语法示例：`ps | tick`、`help | date`

## Iteration 77 — netstat / arp

- `kernel_entry.hl` 新增原生命令函数：
  - `_ke_cmd_netstat()` — 扫描 TCP 连接表（64 TCB @ 0x800000），显示 local:port → remote:port + 状态
  - `_ke_cmd_arp()` — 显示原生 ARP 缓存（16 entries @ 0x360000）+ 网络配置
  - `_ke_print_ip(ip)` — 输出点分十进制 IPv4 地址
  - `_ke_print_mac(addr)` — 输出冒号分隔十六进制 MAC 地址
  - `_ke_print_tcp_state(state)` — TCP 状态名称映射（RFC 793）
  - `_ke_arp_init()` — 初始化原生 ARP 缓存
- `_ke_dispatch()` 新增 `netstat`(7) / `arp`(3) 命令分发
- `_ke_cmd_help()` 新增第 12 行：`netstat arp`
- `shell.hl` 新增 `netstat` 命令，命令数 58 → 60
- `_start()` 新增 Phase 7k: `_ke_arp_init()` 调用

## Iteration 76 — hostname / uname / date

- `kernel_entry.hl` 新增原生命令函数：
  - `_ke_cmd_hostname()` — 输出系统主机名 "hicos"
  - `_ke_cmd_uname()` — 输出 "HicOS 6.0 x86_64 Hilbert-Lang"
  - `_ke_cmd_date()` — 读取 CMOS RTC 输出 YYYY-MM-DD HH:MM:SS（委托 `_ke_cmd_time()`）
- `_ke_dispatch()` 新增 `hostname`(8)、`uname`(5)、`date`(4) 命令分发
- `_ke_cmd_help()` 新增第 11 行：`date uname hostname history`
- `shell.hl` 中 `uname` 输出统一为 "HicOS 6.0 x86_64 Hilbert-Lang"

## Iteration 75 — Command History + Arrow Keys

- `kernel_entry.hl` 新增命令历史环形缓冲区（32 条 × 64 字节 @ 0x350000）
- 新增函数：
  - `_ke_hist_init()` — 初始化历史系统
  - `_ke_hist_push(buf_addr, buf_len)` — 保存命令到历史
  - `_ke_hist_entry_len(slot)` — 获取历史条目长度
  - `_ke_hist_load(buf_addr, index)` — 从历史加载到命令缓冲区
  - `_ke_line_erase(buf_len)` — 擦除当前行显示
  - `_ke_line_reprint(buf_addr, buf_len)` — 重新输出命令行
  - `_ke_cmd_history()` — 显示历史列表
- `_ke_shell()` 重写：支持 PS/2 扩展扫描码（0xE0 前缀）
  - ↑/↓ 方向键：浏览命令历史
  - ←/→ 方向键：行内光标移动
- `shell.hl` 新增 `history` 和 `hostname` 命令
- `shell.hl` 版本更新为 6.0，命令数从 56 → 58
- `kernel_init.hl` 版本字符串更新为 6.0

## Iteration 74 — POSIX Signal Handling

- `kernel_entry.hl` 增加信号位掩码与发送逻辑
- 新增：
  - `_ke_sig_bit(signum)`
  - `_ke_signal_send(tid, signum)`
  - `_ke_signal_pending(tid)`
  - `_ke_signal_block(tid, signum)`
  - `_ke_signal_unblock(tid, signum)`
  - `_ke_signal_deliver(tid)`
  - `_ke_sig_name(signum)`
  - `_ke_cmd_kill(buf_addr, buf_len)`
- `kill <pid> [sig]` 接入 `kernel.bin` 命令分发
- `ps` 输出增加信号相关信息
- `shell.hl` 中 `kill` 默认改为发送 `SIGTERM`

## Iteration 73 — Environment Variables + echo

- 新增环境变量初始化与查找/设置逻辑
- 接入 `env` / `setenv` / `echo`
- `_start()` 中增加环境初始化阶段
- `kernel.bin` 命令分发补齐 `adduser` / `service` / `wifi` / `msg`

## Documentation Sync

本轮同时清理并重写：
- `README.md`
- `ARCHITECTURE.md`
- `ROADMAP.md`
- `PROJECT_STATUS.md`
- `THREE_SYSTEM_COMPARISON.md`
- `FIVE_OS_COMPARISON.md`
- `PROJECT_ADVANCEMENT_PLAN.hl`

原则：
- 删除乱码与失真统计
- 删除未经本轮复核的“最新通过”口径
- 统一为当前仓库可证明状态





