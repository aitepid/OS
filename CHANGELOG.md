# HicOS Changelog

## Current Snapshot

- 活跃 `.hl` 文件：`290`
- H-L 总行数：`68,430`
- 内核模块：`114`
- Shell 命令数：`61` + pipe 操作符
- 构建/测试主入口：`scripts/hl-bootstrap-build-test.ps1`
- 最近完成迭代：`93`

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





