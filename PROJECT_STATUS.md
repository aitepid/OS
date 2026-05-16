# HicOS Project Status

## 版本定位

当前仓库处于 `v6.0` 发布线，最新功能里程碑为迭代 264（skiplist + hyperloglog + consistent_hash）。

## 本轮已核实状态（迭代 264 基线）

### 仓库规模（精确计数）

| 指标 | 当前值 | 说明 |
|---|---:|---|
| 全部 `.hl` 文件 | 319 | 69 根目录 + 250 内核模块 |
| H-L 总行数 | ~97,500 | 持续增长 |
| `bare-kernel/hl/` 内核模块 | 250 | 编译进 `kernel.bin` |
| `kernel_entry.hl` 行数 | 9,428 | 内核入口 + 命令分发 |
| 编译产出函数数 | 2,200+ | 编译管线实测 |
| 链接符号数 | 2,500+ | linker 实测 |
| `hl-bootstrap.hl` 行数 | 4,306 | 自举编译器（208 函数） |
| `stdlib.hl` 行数 | 1,385 | 标准库（143 函数） |
| Shell 命令数 | 670 | shell.hl（+skiplist/hll/chash）|
| `test_*.hl` / `test-*.hl` | 19 | |
| `IP-Protection/` 文件数 | 60 | 知识产权文件 |
| `.md` 文档 | 10 | |

### 门禁结果

| 验证项 | 结果 |
|---|---|
| `hl-bootstrap build` | ✅ 132 模块编译 + 镜像重建 |
| `validate-workspace` | ✅ 319 HL / 250 模块 / 0 stub |
| `runtime-path-readiness` | ✅ IDT/PIT/KBD + SYSCALL + 网络 + eBPF/TLS/QUIC |
| `release-validate` | ✅ 18/18 |

### 产物尺寸（实测）

| 产物 | 大小 |
|---|---:|
| `hicos-hl.img`（BIOS） | 162,816 字节（318 扇区） |
| `hicos-uefi.img`（UEFI） | 34,603,008 字节 |
| `kernel.bin` | 30,704 字节 |

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

## 阶段 6 推进结果（迭代 109-121）

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
| 120 | `kmod.hl`：内核热补丁框架 — 64 模块槽位 + 256 trampoline + 原子热替换 + 自测 |
| 121 | 裸机安装基础：`vga_console.hl` VGA 文本 80×25 + `ata_pio.hl` ATA PIO 磁盘 + `installer.hl` 三后端 |
| 122 | 原生 VGA Shell 交互：键盘回显→VGA + 退格/回车→VGA + 自安装映像 `self_image.hl` |
| 123 | VGA 完整交互闭环：真实滚屏 + `_ke_putc` 双输出 + `usb_kbd.hl` USB HID 键盘 |

## 三层架构现状

| 层级 | 载体 | 说明 |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS 镜像生成链 |
| B | `hl-bootstrap.hl`（4,306 行，208 函数） | 自举编译器/解释器/工具链 |
| C | `bare-kernel/hl/*.hl`（130 模块，36,455 行，1,700 函数） | 内核模块 → `kernel.bin` |

## UI 模块栈（迭代 125-130）

| 模块 | 功能 |
|---|---|
| `ui_theme.hl` | Slate 配色 + 间距常量 |
| `ui_controls.hl` | 按钮 / 标签 / 进度条 / 分隔线 / 徽章 |
| `ui_dialog.hl` | 模态对话框（INFO / CONFIRM / WARNING / ERROR） |
| `ui_terminal.hl` | 图形终端 24×80 |
| `ui_installer.hl` | 5 步图形安装器向导 |
| `ui_sysmon.hl` | 系统监控（运行时间 / 内存 / 任务） |
| `ui_notify.hl` | Toast 通知（4 类型 × 4 并发） |
| `ui_desktop.hl` | 桌面编排（顶栏时钟 + dock 启动器） |
| `wm.hl` | 窗口管理器（标题文字 / 拖拽 / 最小化） |
| `HicOS_UIServer.hl` | UI 服务器（IPC + 焦点通知） |

## 下一阶段建议

- 文件管理器（`ui_files.hl`）
- 设置中心（`ui_settings.hl`）
- 音频管道（audio→mixer）— AC97 PCM 播放
- GPU 2D 加速 — framebuffer 硬件 blit
