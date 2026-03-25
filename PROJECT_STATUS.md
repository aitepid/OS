# HicOS Project Status

## 版本定位

当前仓库处于 `v6.0` 发布线，迭代 114（阶段 6 推进）里程碑。

## 本轮已核实状态（迭代 114 全量复核）

### 仓库规模（精确计数）

| 指标 | 当前值 | 说明 |
|---|---:|---|
| 全部 `.hl` 文件 | 179 | 63 根目录 + 116 内核模块 |
| H-L 总行数 | 47,395 | 根 10,861 + 内核 36,534 |
| `bare-kernel/hl/` 内核模块 | 116 | 编译进 `kernel.bin` |
| `kernel_entry.hl` 行数 | 10,408 | |
| `kernel_entry.hl` 函数数 | 303 | |
| 内核模块总函数数 | 1,498 | 源码定义计数 |
| `hl-bootstrap.hl` 行数 | 4,301 | 自举编译器 |
| `stdlib.hl` 行数 | 1,371 | 标准库 |
| `scripts/*.ps1` | 22 | 构建/验证/诊断 |
| PS1 总行数 | 8,646 | |
| `shell.hl` 命令数 | 63 + pipe | |
| `.md` 文档 | 8 | |
| 仓库总文件数 | 311 | 含日志/文本 |

### 门禁结果

| 验证项 | 结果 |
|---|---|
| `hl-bootstrap build` | ✅ 118 模块编译 + 镜像重建 |
| `validate-workspace` | ✅ 179 HL / 116 模块 |
| `boot-readiness` | ✅ 启动链 + 内核初始化 |
| `image-layout-readiness` | ✅ MBR 签名 + 扇区布局 |
| `runtime-path-readiness` | ✅ IDT/PIT/KBD + SYSCALL + 网络 |
| `release-validate` | ✅ 18/18 |

### 产物尺寸（实测）

| 产物 | 大小 |
|---|---:|
| `hicos-hl.img`（BIOS） | 160,256 字节 |
| `hicos-uefi.img`（UEFI） | 34,603,008 字节 |
| `kernel.bin` | 27,805 字节 |

## 迭代 81-107 算法升级总汇（阶段 1-5）

| 阶段 | 迭代 | 模块 | 升级 | 复杂度 |
|---|---|---|---|---|
| 1 | 81 | `page_alloc.hl` | 位图 → 伙伴系统 | alloc O(n)→O(1) |
| 1 | 82 | `kmalloc.hl` | 首次适配 → 分级空闲链表 | alloc/free O(n)→O(1) |
| 1 | 83 | `block_cache.hl` | 线性扫描 → 哈希+LRU 双链 | lookup O(n)→O(1) |
| 1 | 84 | `hilbert_alloc.hl` | 插入排序 → 归并排序 | init O(n²)→O(n log n) |
| 2 | 86 | `tcp.hl` | 无流控 → Reno 拥塞控制+RTT | 新增 |
| 2 | 87 | `dns.hl` | 无缓存 → TTL 哈希缓存 | resolve O(query)→O(1) |
| 2 | 88 | `vfs.hl` | 线性匹配 → Trie 前缀树 | resolve O(n)→O(depth) |
| 3 | 91 | `arp.hl`+`net.hl` | 线性扫描 → 哈希表 | lookup O(n)→O(1) |
| 3 | 92 | `ext2.hl` | 每次磁盘读 → inode 哈希缓存 | read O(disk)→O(1) |
| 3 | 93 | `swap.hl` | 基础时钟 → 双链增强时钟 | 单指针→active/inactive |
| 3 | 94 | `smp.hl` | 全局调度锁 → Per-CPU 运行队列 | O(contention)→O(1) |
| 4 | 97 | `sched.hl` | CFS 参数 → MLFQ 4 级调度器 | 新增 |
| 4 | 98 | `mmap.hl` | 立即分配 → 按需分页+COW | 新增 |
| 4 | 99 | `pipe.hl` | 逐字节 → 批量 SPSC 环形缓冲 | 新增 |
| 4 | 100 | `tls.hl` | 空壳 → 8 状态 TLS 1.3 握手 | 新增 |
| 5 | 103 | `sync.hl` | 空壳 futex → 16 桶哈希等待队列 | 新增 |
| 5 | 104 | `poll.hl` | 水平触发 → 边缘触发+oneshot+futex | 新增 |
| 5 | 105 | `cgroup.hl` | 被动记账 → CPU/内存/IO 强制执行 | 新增 |
| 5 | 106 | `bpf.hl` | 新建 — eBPF 寄存器 VM | 新增 |

## 阶段 6 推进结果（迭代 109-114）

| 迭代 | 结果 |
|---|---|
| 109 | 链接器二次扫描 + stub trampoline，未解析重定位 `120 → 1` |
| 110 | `kinterp.hl` 增加 IR VM，双执行引擎形成 |
| 111 | `execve` + `argc/argv/envp` 用户栈构建 + ring3 跳转 |
| 112 | `quic.hl` 新建，QUIC v1 传输协议接入 |
| 113 | `task.hl`/`posix.hl`：`ZOMBIE` 生命周期 + `waitpid(WNOHANG)` |
| 114 | `pty.hl`：真实 ring buffer IO + `attach/detach/status` |

## 三层架构现状

| 层级 | 载体 | 说明 |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS 镜像生成链 |
| B | `hl-bootstrap.hl`（4,301 行） | 自举编译器/解释器/工具链 |
| C | `bare-kernel/hl/*.hl`（116 模块，36,534 行） | 内核模块 → `kernel.bin` |

## 下一阶段建议（阶段 6 收敛：迭代 115）

- 全量文档与策划案收敛到 `iter 115`
- 继续补足 PTY 任务绑定路径与双 shell 会话验证
- 远期推进内核自举原型 / TCP 回环 / DNS 实际解析
