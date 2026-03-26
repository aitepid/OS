# HicOS Project Status

## 版本定位

当前仓库处于 `v6.0` 发布线，功能里程碑仍为迭代 119（高级特性验证接入基线）；其后已完成多轮工程化、验证与文档同步修复。

## 本轮已核实状态（迭代 119 功能基线 + 后续维护修复）

### 仓库规模（精确计数）

| 指标 | 当前值 | 说明 |
|---|---:|---|
| 全部 `.hl` 文件 | 185 | 68 根目录 + 117 内核模块 |
| H-L 总行数 | 43,246 | 根 9,986 + 内核 33,260 |
| `bare-kernel/hl/` 内核模块 | 117 | 编译进 `kernel.bin` |
| `kernel_entry.hl` 行数 | 9,565 | 内核入口 + 命令分发 |
| 内核模块总函数数 | 1,499 | 源码定义计数 |
| `hl-bootstrap.hl` 行数 | 4,306 | 自举编译器（208 函数） |
| `stdlib.hl` 行数 | 1,385 | 标准库（143 函数） |
| `kinterp.hl` 行数 | 1,245 | 内核解释器（tree-walk + IR VM） |
| `scripts/*.ps1` | 22 | 构建/验证/诊断 |
| PS1 总行数 | 8,816 | |
| Shell + 内核命令（去重） | 112 | shell.hl 64 + kernel_entry.hl 70 |
| `HicOS_*.hl` 子系统模块 | 27 | |
| `test_*.hl` / `test-*.hl` | 18 | |
| `.md` 文档 | 8 | |
| 活跃仓库文件数 | 283 | 排除 `.git/.vs/archive` |

### 门禁结果

| 验证项 | 结果 |
|---|---|
| `hl-bootstrap build` | ✅ 119 模块编译 + 镜像重建 |
| `validate-workspace` | ✅ 185 HL / 117 模块 |
| `boot-readiness` | ✅ 启动链 + 内核初始化 |
| `image-layout-readiness` | ✅ MBR 签名 + 扇区布局 |
| `runtime-path-readiness` | ✅ IDT/PIT/KBD + SYSCALL + 网络 |
| `release-validate` | ✅ 18/18 |

### 产物尺寸（实测）

| 产物 | 大小 |
|---|---:|
| `hicos-hl.img`（BIOS） | 160,256 字节 |
| `hicos-uefi.img`（UEFI） | 34,603,008 字节 |
| `kernel.bin` | 27,970 字节 |

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

## 阶段 6 推进结果（迭代 109-119）

| 迭代 | 结果 |
|---|---|
| 109 | 链接器二次扫描 + stub trampoline，未解析重定位 `120 → 1` |
| 110 | `kinterp.hl` 增加 IR VM，双执行引擎形成 |
| 111 | `execve` + `argc/argv/envp` 用户栈构建 + ring3 跳转 |
| 112 | `quic.hl` 新建，QUIC v1 传输协议接入 |
| 113 | `task.hl`/`posix.hl`：`ZOMBIE` 生命周期 + `waitpid(WNOHANG)` |
| 114 | `pty.hl`：真实 ring buffer IO + `attach/detach/status` |
| 115 | 全量文档与策划案收敛到实际状态 |
| 116 | `kernel_entry.hl`：`heval` 命令 — 内核 lex→parse→eval 自举原型 |
| 117 | `tcp.hl`：TCP 回环自测 — 127.0.0.1 SYN→ESTABLISHED→DATA(5B)→FIN→CLOSE_WAIT |
| 118 | `dns.hl`：DNS 回环自测 — 查询→mock响应→解析→缓存命中→TTL过期→未命中→static |
| 119 | `advanced_verify.hl`：eBPF / TLS1.3 / QUIC 统一自测 + `advtest` 命令 + 门禁接入 |

## 三层架构现状

| 层级 | 载体 | 说明 |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS 镜像生成链 |
| B | `hl-bootstrap.hl`（4,306 行，208 函数） | 自举编译器/解释器/工具链 |
| C | `bare-kernel/hl/*.hl`（117 模块，33,260 行，1,499 函数） | 内核模块 → `kernel.bin` |

## 下一阶段建议（迭代 120+）

- `kmod.hl` 内核热补丁
- 音频管道 / GPU 2D 加速
