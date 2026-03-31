# HicOS 6.0

纯 `Hilbert-Lang` 编写的实验性 x86_64 操作系统与自举工具链。

## 当前状态

- 代码仓库包含 `198` 个 `.hl` 文件（共 `46,499` 行）
  - 根目录：`68` 个（含自举编译器、标准库、子系统模块、测试与策划案）
  - `bare-kernel/hl/`：`130` 个内核模块（`36,455` 行，编译产出 `1,700` 个函数）
- `kernel_entry.hl`：`9,428` 行
- `hl-bootstrap.hl`：`4,306` 行（自举编译器/工具链，`208` 个函数）
- `stdlib.hl`：`1,385` 行（标准库，`143` 个函数）
- `kinterp.hl`：`1,245` 行（树遍历 + IR VM 双执行引擎）
- `scripts/` 下有 `28` 个 PowerShell 构建/验证脚本（共 `9,729` 行）
- Shell 命令：`68`（`shell.hl` 中 `if cmd ==` 匹配数）
- 当前功能里程碑：`130`（UI Phase 1-6 完成：主题 / 控件 / 对话框 / 桌面 / 终端 / 安装器 / 系统监控 / 通知）
- 当前主构建/测试入口：`hl-bootstrap.cmd test`（封装 `scripts/hl-bootstrap-build-test.ps1`）
- 三层架构：
  - `Layer A`：`scripts/rebuild-image.ps1` → 可引导 BIOS 镜像
  - `Layer B`：`hl-bootstrap.hl` 自举编译器/工具链
  - `Layer C`：`bare-kernel/hl/*.hl` → `kernel.bin`

## 产物

| 产物 | 大小 |
|---|---:|
| `hicos-hl.img`（BIOS） | 162,816 字节（318 扇区） |
| `hicos-uefi.img`（UEFI） | 34,603,008 字节 |
| `kernel.bin` | 30,704 字节 |

## 迭代 81-120：六阶段完成 + 高级特性验证接入 + 内核热补丁

| 阶段 | 模块 | 升级 |
|---|---|---|
| 1 内存 | `page_alloc` `kmalloc` `block_cache` `hilbert_alloc` | 伙伴系统 / 空闲链表 / 哈希LRU / 归并排序 |
| 2 网络 | `tcp` `dns` `vfs` | Reno拥塞 / TTL缓存 / Trie前缀树 |
| 3 多核 | `arp+net` `ext2` `swap` `smp` | 哈希表 / inode缓存 / 增强时钟 / Per-CPU队列 |
| 4 调度 | `sched` `mmap` `pipe` `tls` | MLFQ / 按需COW / SPSC环形 / TLS1.3状态机 |
| 5 隔离 | `sync` `poll` `cgroup` `bpf` | futex哈希队列 / 边缘触发epoll / cgroup强制 / eBPF VM |

### 阶段 6（迭代 109-119）
- `linker.hl` / `scripts/hl-compile-pipeline.ps1`：链接器二次扫描 + stub trampoline
- `stdlib.hl`：零警告编译
- `kinterp.hl`：树遍历 + IR VM 双执行引擎
- `posix.hl` / `task.hl`：`execve` + `waitpid` + `ZOMBIE` 生命周期
- `quic.hl`：QUIC v1 传输协议
- `pty.hl`：真实读写修复 + `attach/detach/status`
- `kernel_entry.hl`：`heval` 命令 — 内核 lex→parse→eval 自举原型
- `tcp.hl`：TCP 回环自测 — 127.0.0.1 SYN→SYN_RCVD→ESTABLISHED→DATA→FIN→CLOSE_WAIT
- `dns.hl`：DNS 回环自测 — 查询→mock响应→解析→缓存→命中→过期→未命中→static
- `advanced_verify.hl`：eBPF / TLS 1.3 / QUIC 统一验证接入基线 + `advtest` 命令

### 迭代 120：内核热补丁
- `kmod.hl`：运行时模块加载/卸载/热替换框架
- 64 模块槽位 + 256 trampoline + 256 KB 代码 arena
- FNV-1a 哈希符号查找 + 引用计数 + 依赖位掩码
- 原子热补丁：MOV RAX, imm64 + JMP RAX trampoline 重定向
- `lsmod` / `kmodtest` 命令接入 shell + kernel_entry 分发

### 迭代 121：裸机安装基础
- `vga_console.hl`：VGA 文本模式控制台（80×25，0xB8000 直接写显存）
  - 硬件光标同步（CRTC 0x3D4/0x3D5）、滚屏、退格、制表符
  - 多色属性：banner/ok/err/warn + `dual_print()` 串口+显示器双输出
- `ata_pio.hl`：ATA PIO 磁盘驱动（真实 IDE/SATA 硬件，28-bit LBA）
  - 主/从 × 主/副通道（4 设备检测）、IDENTIFY DEVICE、读/写扇区、CACHE FLUSH
- `installer.hl` 升级 v6.0：三后端磁盘自动检测
  - 优先级：ATA PIO（真实硬件）→ AHCI DMA → VirtIO-blk（虚拟机）
  - 统一 `installer_disk_read/write` 调度器
- `rebuild-image.ps1`：原生内核 VGA 文本双输出（启动消息 + Shell 提示符同步显示到显示器）

### 迭代 122：原生 VGA Shell 交互 + 自安装映像感知
- `rebuild-image.ps1` 原生内核 `vga_putchar` 子程序（x86_64 机器码）
  - 键盘字符回显 → VGA 文本缓冲区（输入即可见于显示器）
  - 退格键 → VGA 光标回退 + 字符擦除
  - 回车键 → VGA 换行
  - 11 条关键启动消息转为串口+VGA 双输出
- `self_image.hl`：内核自映像感知模块
  - 内核知晓自身镜像在内存中的布局（地址/大小/扇区数）
  - `self_install_to_disk()`：逐扇区将引导镜像写入目标磁盘
  - 为后续"一键安装到硬盘"提供基础能力

### 迭代 123：VGA 完整交互闭环 + USB 键盘
- 原生内核 VGA 真实滚屏（`rep movsb` 复制 3840 字节 + 清空末行，替代简单截断）
- `_ke_putc()` 双输出：所有 H-L 内核命令输出自动同步到 VGA 文本缓冲区
  - `help`、`ps`、`install` 等命令的输出均可在显示器上看到
- `usb_kbd.hl`：USB HID 键盘驱动（Boot Protocol，8 字节报文）
  - HID Usage ID → ASCII 完整映射（字母/数字/符号/Shift 变体）
  - 自动检测 HID class=3 subclass=1 protocol=1
  - 轮询式输入 + 修饰键状态跟踪

### 迭代 124-130：UI Phase 1-6 — 完整图形桌面环境
- `ui_theme.hl`：统一视觉基线（Slate 配色系统 + 10 色板 + 间距常量）
- `ui_controls.hl`：控件系统（按钮 / 标签 / 进度条 / 分隔线 / 徽章 / 命中检测）
- `ui_dialog.hl`：模态对话框（INFO / CONFIRM / WARNING / ERROR + 键盘/鼠标导航）
- `ui_terminal.hl`：图形终端（24×80 字符网格 + 光标 + 滚屏 + 命令输入）
- `ui_installer.hl`：5 步图形安装器（Welcome→Detect→Confirm→Install→Complete）
- `ui_sysmon.hl`：系统监控窗口（运行时间 / 内存 / 任务 / 窗口状态）
- `ui_notify.hl`：Toast 通知系统（4 类型 × 4 并发 + 自动消失）
- `ui_desktop.hl`：桌面编排层（顶栏时钟 + dock 启动器 + 窗口标题按钮）
- `wm.hl`：窗口管理器增强（标题文字 / 拖拽 / 最小化 / 任务栏 / 点击路由）
- `HicOS_UIServer.hl`：UI 服务器集成（IPC 完善 + 焦点通知 + 桌面 tick）

## 当前功能

### 内核
- VGA 文本模式控制台（80×25 显示器输出 + 串口双输出）
- 串口、PIC、PIT、IDT、键盘中断（PS/2 扫描码）
- PCI 扫描、VirtIO-blk/net、AHCI、NVMe、USB、ATA PIO
- 物理页分配（伙伴）、堆分配（分级链表）、虚拟内存（按需+COW）
- 多核 SMP（INIT-SIPI-SIPI）、Per-CPU 运行队列
- MLFQ 调度、信号处理、进程管理
- Futex 哈希等待队列、epoll 边缘触发、cgroup 资源隔离
- eBPF 寄存器虚拟机（16 指令，5 钩子点）
- FAT16/ext2/NTFS/VFS（Trie挂载）
- TCP（Reno拥塞 + 回环自测）、UDP、DNS（TTL缓存 + 回环自测）、DHCP、TLS 1.3（验证接入）
- QUIC v1（16 连接 × 16 流，1-RTT 握手，NewReno）
- eBPF VM（验证接入：程序装载 / hook attach / 运行）
- Block cache（哈希LRU）、swap（增强时钟）
- 内核热补丁（kmod：64 模块槽位 + trampoline 热替换）

### Shell 命令（68 唯一命令 + pipe）
- 环境变量、信号处理、命令历史、方向键导航
- shell.hl（68 cmd== 匹配）：hostname / uname / date / netstat / arp / grep / heval / tcploop / dnstest / advtest / lsmod / kmodtest / ...

## 推荐构建方式

```powershell
.\hl-bootstrap.cmd test
```

## 常用验证命令

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\qemu-smoke.ps1
```

## 仓库结构

```text
HicOS/
├─ bare-kernel/
│  ├─ hl/                      # 130 个内核模块（36,455 行）
│  └─ kernel.bin              # 编译产物（30,704 字节）
├─ scripts/                   # 28 个构建/验证脚本（9,729 行）
├─ IP-Protection/             # 60 个知识产权文件
├─ hl-bootstrap.hl            # 自举编译器（4,306 行）
├─ stdlib.hl                  # 标准库（1,385 行）
├─ HicOS_*.hl                 # 27 个子系统模块
├─ test_*.hl / test-*.hl      # 19 个测试文件
├─ hicos-hl.img               # BIOS 镜像（162,816 字节）
├─ hicos-uefi.img             # UEFI 镜像（33 MB）
└─ *.md                       # 10 个文档
```

## 相关文档

- `PROJECT_STATUS.md`：当前项目状态
- `ARCHITECTURE.md`：三层架构说明
- `ROADMAP.md`：已完成阶段与路线图
- `CHANGELOG.md`：迭代更新记录
- `UI_DESIGN_PLAN.md`：UI 设计策划案
- `HILBERT_LANG_BNF.md`：语言语法规范
- `PROJECT_ADVANCEMENT_PLAN.hl`：推进策划案
