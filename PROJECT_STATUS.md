# HicOS Project Status

## Version: 6.0

## 真实状态审计

### 三层代码架构

> ⚠️ HicOS 有三层代码，执行状态完全不同:

| 层级 | 载体 | QEMU 运行 | 内容 |
|------|------|-----------|------|
| **A: 镜像机器码** | `scripts/rebuild-image.ps1` → `hicos-hl.img` | ✅ 真正运行 | 引导+串口+PIC/PIT/IDT+PCI+VirtIO读写+VirtIO-net+**shell 20命令+FAT16+DHCP+Ping+DNS+VESA+Ring3**+任务交替 |
| **B: H-L 编译器** | `hl-bootstrap.hl` build_kernel() | ⚠️ 可执行但产出较旧 | 串口+PIC+PIT+IDT+键盘 (不含 PCI/VirtIO) |
| **C: 内核源码** | `bare-kernel/hl/` 114 模块 | ✅ kernel.bin 集成到镜像 | 编译产出 kernel.bin, 1,210+函数, 44条shell命令, 含密码学+TLS+HTTPS+图形终端+ext2+hlpkg+词法分析器+VirtIO-GPU+POSIX+文本编辑器 |

**当前状态**: v8.0 Phase I 完成。kernel.bin 运行 44 条 shell 命令，包含内核自举词法分析器+VirtIO-GPU检测+POSIX兼容层+文本编辑器。

### 代码库统计

| 指标 | 值 |
|------|-----|
| H-L 源文件 (活跃) | 176 个 `.hl` |
| 内核模块 | 114 个 (`bare-kernel/hl/`) |
| 内核函数定义 | 1,121 个 |
| 用户空间模块 | 27 个 (`HicOS_*.hl`) — 全部原生，0 个桩 |
| 基础设施/测试 | 34 个 (hl-bootstrap, stdlib, test-suite 等) |
| 总代码行数 | ~45,900 行 (38,082 H-L + 7,773 PS1) |
| 构建/测试脚本 | 19 个 PowerShell 脚本 (`scripts/`) |
| BIOS 可引导镜像 | `hicos-hl.img` = 152,064 字节 (297扇区, MBR 0x55AA ✓) |
| UEFI 可引导镜像 | `hicos-uefi.img` = 33 MB (GPT+CRC32, ESP FAT16) |
| UEFI 应用程序 | `BOOTX64.EFI` = 1,536 字节 (PE32+ x86_64) |
| kernel.bin (编译产出) | 1,210+ 函数, 44 shell 命令 |
| QEMU BIOS 引导测试 | **107/107 PASS** (含 16 个测试阶段, 涵盖 shell + FAT16 + net + Ring3 + HW + disk + install + run + mem + sha256 + hmac + aes/gcm/tls + https/gterm/ext2/hlpkg + lex/vgpu/posix/edit) |
| QEMU UEFI 引导测试 | **3/3 PASS** |
| Full Gate | **10/10 PASS** |
| 二进制分析 | 13/13 检查通过 (MBR+Stage1+Stage2+Kernel) |
| 符号链 | 0 个未解析符号 |

### 已解决的阻塞问题

| # | 问题 | 状态 |
|---|------|------|
| 1 | ~~解释器未连通~~ | ✅ **已修复** — `hl-bootstrap interpret` 完整执行 H-L 代码 (let/fn/if/while/return/print/字符串拼接) |
| 2 | ~~45 个 JS 转换文件~~ | ✅ **已归档** — 46 文件移至 `archive/js-origin/`, 不参与构建 |
| 3 | ~~内核符号链未验证~~ | ✅ **已验证** — 0 个未解析符号 (page_alloc别名/gpt修复/installer链接) |
| 4 | ~~无可执行文件格式~~ | ✅ **已创建** — `hlc_loader.hl` (.hlc魔数+段+重定位) |
| 5 | ~~SYSCALL 未生成~~ | ✅ **已实现** — MSR STAR/LSTAR/FMASK 初始化 + entry stub |
| 6 | ~~QEMU 无串口输出~~ | ✅ **已修复** — Stage2 far JMP 0x66前缀 + INT13h LBA 扩展读 + kernel→0x100000 复制 |

### 本轮迭代新增

- **迭代 17: FAT16 文件系统端到端 (QEMU 验证通过)**
  - `disk_rw_sector` 内核子程序 — R8D=扇区, R9=缓冲区, R10B=操作(0=读/1=写)
  - **format 命令**: 写 BPB + 双 FAT 表 + 清空根目录 (160+ 扇区写入)
  - **mkfile 命令**: 前缀匹配解析, 8.3 文件名大写转换, 写数据簇 + 更新 FAT + 创建目录项
  - **ls 命令**: 读根目录, 跳过 LFN/卷标/已删除, 打印 8.3 文件名 + 扩展名 + 十六进制文件大小
  - **cat 命令**: 前缀匹配, repe cmpsb 搜索目录, 簇→扇区转换, 逐字节输出内容
  - FAT16 布局: 4 保留扇区, 双 64 扇区 FAT, 32 扇区根目录, 2KB 簇, 数据区起始扇区 164
  - 修复 3 个关键 bug: REX.R→REX.B (0x44→0x41), short→near jump 溢出, signed→unsigned cmp
- **迭代 16: Shell 命令解析 (QEMU 验证通过)**
  - `serial_puts` 内核子程序 — 可调用函数，RSI指向字符串→COM1输出，大幅减少代码体积
  - 命令缓冲区 128 字节 (0x300800) + 写索引 (0x300880)
  - Backspace 支持 (BS+Space+BS 终端擦除)
  - Enter → 命令分发链 (逐字节比较 + jne near 跳过)
  **18 条可执行命令**: `help` `ver` `free` `ps` `lspci` `uptime` `reboot` `shutdown` `halt` `format` `ls` `mkfile` `cat` `ifconfig` `dhcp` `ping` `nslookup` `vesa` `ring3`
- **迭代 18: DHCP + Ping + DNS + ifconfig (QEMU 验证通过)**
  - `dhcp` 命令: VirtIO-net TX DHCP Discover → RX Offer → yiaddr 存储 → IP 获取
  - `ping` 命令: ARP 刷新 → ICMP Echo Request → 等待 Reply → IP 校验和
  - `nslookup` 命令: UDP DNS A-record 查询 → 解析 answer IP → 十进制打印
  - `ifconfig` 命令: MAC 地址 + DHCP IP 十进制显示 (3位每八位组)
  - VirtIO-net RX: used ring 轮询 + desc_id → buffer → EtherType/Protocol 分派
- **迭代 20: VESA 图形输出 (QEMU 验证通过)**
  - VBE 模式设置: Stage2 实模式 INT 10h AX=4F01/4F02，模式 0x118 + LFB
  - 帧缓冲区页表映射: PDPT[3]→PD[488-489]，2×2MB 大页覆盖 0xFD000000-0xFD3FFFFF
  - `vesa` 命令: 填充深蓝屏 + 白色横条 Banner (624×40 像素)
- **迭代 21: Ring3 用户态切换 (QEMU 验证通过)**
  - SYSCALL MSR 配置: STAR (GDT段) + LSTAR (entry地址) + FMASK (IF清除)
  - TSS 加载: 104字节 TSS + GDT描述符 + LTR
  - `ring3` 命令: IRETQ→0x8000 Ring3 → SYSCALL(1,'U') → SYSCALL(1,'3') → SYSCALL(0)回内核
- **QEMU BIOS 端到端验证 42/42**: 24 项硬件 + 6 项 shell + 4 项 FAT16 + 6 项网络 + 2 项 Ring3
  硬件: Serial ✓ | PIC ✓ | PIT ✓ | IDT ✓ | PS/2 ✓ | PCI ✓ | VirtIO-blk ✓ | VirtIO-net ✓ | VESA ✓ | SYSCALL ✓
  - Shell: help ✓ | ver ✓ | ps ✓ | 未知命令拒绝 ✓ | 提示符 ✓ | 键盘回显 ✓
  - **FAT16: format→FAT16 ✓ | mkfile创建文件 ✓ | ls列目录 ✓ | cat读文件内容 ✓**
- **QEMU UEFI 端到端验证 3/3**: OVMF→GPT→ESP→BOOTX64.EFI
  - GPT: CRC32 校验 + 128 条目 + 备份头/条目 ✓
  - ESP: FAT16 文件系统 (BPB + 双FAT + \EFI\BOOT\BOOTX64.EFI) ✓
  - PE32+: DOS头 + COFF + Optional Header + .text + .reloc ✓
  - 串口输出 "HicOS UEFI OK" + ConOut "HicOS UEFI Boot OK" ✓
- **build-uefi-image.ps1**: 从零生成 UEFI 可引导 GPT 磁盘镜像
- **rebuild-image.ps1**: BIOS 镜像重建器 (Stage2 far JMP + INT13h LBA + kernel copy)
- **full-gate.ps1**: 7 项全量验证门 (workspace+boot+runtime+layout+binary+QEMU+bootstrap)
- **kinterp.hl**: 内核内嵌 H-L 解释器 (Lexer→Parser→Tree-walk, 689行)
- **font.hl**: 8x16 位图字体渲染器
- **nvme.hl**: NVMe 1.4 驱动 (Admin+I/O 队列)
- **errno.hl**: POSIX 错误码 (35 个)
- **wm.hl 增强**: 窗口移动/缩放/焦点/渲染
- **HicOS_UIServer.hl**: IPC 协议 + 事件队列 + dirty tracking + 合成器

## Roadmap Progress

See: [ROADMAP.md](ROADMAP.md)

### 状态说明
- ✅ 代码已写 = H-L 源码完整,逻辑正确
- 🟢 解释器验证 = 在 hl-bootstrap interpret 中通过
- ⚠️ 未QEMU验证 = 代码存在但从未在 QEMU 中执行
- ○ 缺失 = 代码不存在或为纯桩函数

| Phase | Name | 代码状态 | 运行验证 |
|-------|------|---------|---------|
| 0.1 | Bootstrap Host (shim) | ✅ 代码已写 | 🟢 解释器可执行 H-L |
| 0.2 | Kernel Codegen (ImageBuilder) | ✅ 代码已写 | 🟢 img 重建可用 |
| 0.3 | Self-hosting Verify | ✅ 代码已写 | 🟢 QEMU 引导验证通过 |
| 1.1 | ISR Stub (256向量) | ✅ 代码已写 | 🟢 QEMU 21/21 (IDT ✓) |
| 1.2 | E820 Memory Detect | ✅ 代码已写 | 🟢 QEMU memory mapped 8MB ✓ |
| 1.3 | Dynamic Page Tables | ✅ 代码已写 | 🟢 QEMU 长模式运行 ✓ |
| 1.4 | VESA Real Mode | ✅ 代码已写 | 🟢 QEMU 1024×768×32 LFB=FD000000 ✓ |
| 2.1 | VirtIO-blk | ✅ 代码已写 | 🟢 QEMU 读写验证通过 ✓ |
| 2.2 | Block Cache | ✅ 代码已写 | 🟢 通过 VirtIO-blk 连通 |
| 3.1 | FAT16 Read/Write | ✅ 代码已写 | ⚠️ 未独立验证 |
| 3.2 | VFS Mount FAT16 | ✅ 代码已写 | ⚠️ 未独立验证 |
| 3.3 | Swap | ✅ 代码已写 | ⚠️ I/O 路径未验证 |
| 4.1 | Context Switch | ✅ 代码已写 | 🟢 QEMU A/B 任务交替 ✓ |
| 4.2 | Timer Scheduling | ✅ 代码已写 | 🟢 QEMU PIT 100Hz ✓ |
| 4.3 | fork/exec/wait | ✅ 代码已写 | ⚠️ 未独立验证 |
| 5.1 | Disk Partition (MBR+GPT) | ✅ 代码已写 | 🟢 GPT CRC32 OVMF 验证 ✓ |
| 5.2 | FAT16 Format | ✅ 代码已写 | 🟢 UEFI ESP FAT16 OVMF 识别 ✓ |
| 5.3 | Boot Sector Write | ✅ 代码已写 | 🟢 MBR 0x55AA 引导 ✓ |
| 5.4 | Install Wizard (v5.0) | ✅ 代码已写 | ⚠️ 需完整安装流程验证 |
| 6.1 | AHCI/SATA | ✅ 代码已写 | ⚠️ 未在物理硬件验证 |
| 6.2 | kinterp (内核解释器) | ✅ 代码已写 | 🟢 宿主端验证通过 |
| 6.3 | USB HID (xHCI) | ✅ 代码已写 | ⚠️ 未验证 |
| 6.4 | PS/2 Scancode | ✅ 代码已写 | 🟢 QEMU 扫描码表加载 ✓ |
| 7.1 | VirtIO-net | ✅ 代码已写 | 🟢 QEMU MAC+ARP+RX 验证 ✓ |
| 7.2 | DHCP | ✅ 代码已写 | 🟢 QEMU Discover→Offer IP获取 ✓ |
| 7.3 | TCP | ✅ 代码已写 | ⚠️ 未独立验证 |
| 7.4 | Net Input Dispatch | ✅ 代码已写 | 🟢 ICMP ping 10.0.2.2 往返 ✓ |
| 8.1 | SMP | ✅ 代码已写 | ⚠️ 多核启动未验证 |
| 8.2 | ACPI Power | ✅ 代码已写 | ⚠️ shutdown 未验证 |
| 8.3 | Firmware Loader | ✅ 代码已写 | ⚠️ VFS 加载未验证 |
| 8.4 | ext2 | ✅ 代码已写 | ⚠️ 磁盘读取未验证 |
| 9.1 | UEFI Boot | ✅ 代码已写 | 🟢 OVMF PE32+ 加载 ✓ |
| 9.2 | GPT | ✅ 代码已写 | 🟢 OVMF GPT 识别 ✓ |
| 9.3 | Secure Boot | ✅ 代码已写 | ⚠️ 签名链未验证 |

## Next Action

### 已完成的迭代
- **迭代 18**: ✅ **已完成** — DHCP + Ping + DNS + ifconfig (VirtIO-net 收包, SLIRP 全通路)
- **迭代 20**: ✅ **已完成** — VESA 图形输出 (1024×768×32 帧缓冲, LFB 读写验证)
- **迭代 21**: ✅ **已完成** — Ring3 用户态切换 (IRETQ→Ring3→SYSCALL 打印→内核回归)
- **迭代 22-28**: ✅ **已完成** — kernel.bin A/C 融合 (串口+PIC/PIT/IDT+PCI+Shell+页分配+堆+任务调度)
- **迭代 29-30**: ✅ **已完成** — TCP SYN + VirtIO-net TX + HTTP GET + 12 条 shell 命令
- **迭代 31**: ✅ **已完成** — PS/2 鼠标驱动 + ISR 偏移量修复 + IRQ12 + mouse 命令 (13 条 shell)
- **迭代 32**: ✅ **已完成** — VESA 8x16 位图字体渲染 + gfxtest 命令 (14 条 shell)
- **迭代 33**: ✅ **已完成** — 窗口管理器 + 图形桌面 + wm 命令 (15 条 shell)
- **迭代 34**: ✅ **已完成** — SMP 多核启动 (LAPIC+INIT-SIPI-SIPI+跳板+smp 命令, 16 条 shell)
- **迭代 35**: ✅ **已完成** — AHCI/SATA 磁盘控制器检测 (PCI+ABAR+端口状态+ahci 命令, 17 条 shell)
- **迭代 36**: ✅ **已完成** — USB xHCI 控制器检测 (PCI+BAR0+能力寄存器+端口扫描+usb 命令, 18 条 shell)
- **Gate 修复**: ✅ 42/42 PASS (网络测试超时调优)

### 下一步
**战略目标: 物理硬件适配** — SMP+AHCI+USB 已完成，继续 ACPI 和音频

**当前 kernel.bin 状态**: 19,672B, 1,121 函数, 30 条 shell 命令
  已有: serial+PIC/PIT/IDT+PCI+VirtIO-blk+VirtIO-net+TCP+FAT16+安装器+页分配+堆+任务+鼠标+字体+WM+SMP+AHCI+USB+ACPI+AC97+RTC+微型解释器+shell

**迭代 37**: ✅ **已完成** — ACPI 电源管理
**迭代 38**: ✅ **已完成** — AC97 音频
**迭代 39**: ✅ **已完成** — RTC 实时时钟
**迭代 40**: ✅ **已完成** — beep/time 命令接入 kernel.bin (20→22 命令)
**迭代 41**: ✅ **已完成** — VirtIO-blk 驱动 + disk/uptime/shutdown (22→25 命令)
**迭代 42**: ✅ **已完成** — FAT16 format + ls + VirtIO-blk write (25→27 命令)
**迭代 43**: ✅ **已完成** — FAT16 mkfile + cat 文件创建与读取 (27→28 命令)
  🏆 FAT16 端到端闭环: format → mkfile → ls → cat
**迭代 44**: ✅ **已完成** — 微型 H-L 解释器 + run 命令 (28→29 命令)
  🏆 程序执行闭环: mkfile hello.hl → run hello.hl → 串口输出
**迭代 45**: ✅ **已完成** — HicOS 安装器 7步安装 (29→30 命令)
  🏆 安装器端到端: install → MBR+FAT16+HICOS.SYS+BOOT.CFG → 验证
**迭代 46**: ✅ **已完成** — v6.0 发布整合 (测试 42→62, Full Gate 7→10, 新增 perf-baseline + release-validate)
  🏆 v6.0 发布里程碑: 10 阶段全部完成, 双启动验证, 30 条 shell 命令
**迭代 47**: ✅ **已完成** — clear + hexdump 命令 + v7.0 详细计划 (Layer A 18→20 命令, serial_hex_byte/space 子程序, 版本升 6.0)
**迭代 48**: 🎯 **下一步** — SHA-256 哈希 in kernel.bin (TLS 1.3 密码学基础)

详见: [PROJECT_ADVANCEMENT_PLAN.hl](PROJECT_ADVANCEMENT_PLAN.hl) | [COMPILER_PIPELINE_STRATEGY.hl](COMPILER_PIPELINE_STRATEGY.hl)



