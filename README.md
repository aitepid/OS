# HicOS 6.0

纯 `Hilbert-Lang` 编写的实验性 x86_64 操作系统与自举工具链。

## 当前状态（迭代 246）

- 代码仓库包含 `301` 个 `.hl` 文件（共 `~80,300` 行）
  - 根目录：`69` 个（含自举编译器、标准库、子系统模块、测试与策划案）
  - `bare-kernel/hl/`：`232` 个内核模块（~76,000 行，编译产出 `2,200+` 个函数）
- `kernel_entry.hl`：`9,428` 行
- `hl-bootstrap.hl`：`4,306` 行（自举编译器/工具链，`208` 个函数）
- `stdlib.hl`：`1,385` 行（标准库，`143` 个函数）
- `kinterp.hl`：`1,245` 行（树遍历 + IR VM 双执行引擎）
- `scripts/` 下有 `28` 个 PowerShell 构建/验证脚本（共 `9,729` 行）
- Shell 命令：`580`（`shell.hl` 全功能命令集）
- 当前功能里程碑：`246`（brotli + sm3 + sm4）
- Git 提交数：`114`
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

## 迭代历程概览

### 迭代 81-107：六阶段算法升级

| 阶段 | 模块 | 升级 |
|---|---|---|
| 1 内存 | `page_alloc` `kmalloc` `block_cache` `hilbert_alloc` | 伙伴系统 / 空闲链表 / 哈希LRU / 归并排序 |
| 2 网络 | `tcp` `dns` `vfs` | Reno拥塞 / TTL缓存 / Trie前缀树 |
| 3 多核 | `arp+net` `ext2` `swap` `smp` | 哈希表 / inode缓存 / 增强时钟 / Per-CPU队列 |
| 4 调度 | `sched` `mmap` `pipe` `tls` | MLFQ / 按需COW / SPSC环形 / TLS1.3状态机 |
| 5 隔离 | `sync` `poll` `cgroup` `bpf` | futex哈希队列 / 边缘触发epoll / cgroup强制 / eBPF VM |

### 迭代 109-130：高级特性与UI系统

- **迭代 109-120**：链接器优化、IR VM、QUIC、内核热补丁、高级验证
- **迭代 121-123**：裸机安装（VGA控制台、ATA PIO、USB键盘、真实滚屏）
- **迭代 124-130**：完整图形桌面环境（主题、控件、对话框、终端、安装器、系统监控、通知、窗口管理）

### 迭代 131-246：模块大扩展（116 次迭代）

通过持续迭代，系统从 130 个模块扩展到 232 个模块，涵盖：

**网络协议**：HTTP/HTTPS、WebSocket、Telnet、SMTP、POP3、IMAP、IRC、FTP、NTP、MQTT、SIP、RTSP、STUN、RTP、SOCKS、DHCP Server、RADIUS、LDAP、QUIC

**压缩算法**：LZ4、Huffman、RLE、ZLIB、LZMA、Bzip2、Snappy、Zstd、Brotli

**加密算法**：
- 对称加密：AES、ChaCha20、SM4
- 非对称加密：RSA、Ed25519
- 哈希：MD5、SHA1、SHA256、BLAKE2、SM3、xxHash、SipHash
- MAC：HMAC、Poly1305
- 密码哈希：Bcrypt、Scrypt、Argon2、PBKDF2

**序列化格式**：Protocol Buffers、Avro、CBOR、ASN.1、MessagePack

**编码格式**：Base64、Base32、Hex、URL、Quoted-Printable、UUencode、PEM、JWT

**文件格式**：BMP、GIF、WAV、CPIO、TAR

**应用功能**：SQLite、Diff、INI 解析、CSV 解析、Profiler、Ping、Traceroute、Semaphore、Cron、Calendar、RSS

## 当前功能

### 内核核心

- **控制台**：VGA 文本模式（80×25 显示器输出 + 串口双输出）
- **硬件**：串口、PIC、PIT、IDT、键盘中断（PS/2）、USB 键盘（HID Boot Protocol）
- **存储**：PCI 扫描、VirtIO-blk/net、AHCI、NVMe、USB、ATA PIO
- **内存管理**：
  - 物理页分配（伙伴系统）
  - 堆分配（分级空闲链表）
  - 虚拟内存（按需分页 + COW）
  - Swap（增强时钟算法）
  - Block cache（哈希 + LRU）
- **多核与调度**：
  - SMP（INIT-SIPI-SIPI，Per-CPU 运行队列）
  - MLFQ 4级调度器
  - 信号处理、进程管理
- **同步与隔离**：
  - Futex 哈希等待队列
  - epoll 边缘触发
  - cgroup 资源隔离（CPU/内存/IO）
  - seccomp 系统调用过滤
- **文件系统**：FAT16、ext2、NTFS、VFS（Trie 挂载树）
- **网络栈**：
  - TCP（Reno 拥塞控制 + 回环自测）
  - UDP、ICMP
  - DNS（TTL 缓存 + 回环自测）
  - DHCP Client/Server
  - TLS 1.3（8 状态握手，验证接入）
  - QUIC v1（16 连接 × 16 流，1-RTT 握手）
  - HTTP/HTTPS、WebSocket、各类应用层协议
- **高级特性**：
  - eBPF VM（16 指令，5 钩子点，验证接入）
  - 内核热补丁（kmod：64 模块槽位 + 256 trampoline）
  - PTY 伪终端
  - 用户权限管理
  - 安全启动

### 图形界面

- **UI 框架**：Slate 主题、控件库、对话框、通知系统
- **应用程序**：图形终端、系统监控、安装器
- **窗口管理**：标题栏、拖拽、最小化、任务栏
- **桌面环境**：顶栏时钟、dock 启动器

### Shell 命令（580 个）

丰富的命令集涵盖：
- 系统管理：help、ver、uptime、date、free、heap、ps、cpus、mount、lspci、ifconfig
- 网络诊断：ping、traceroute、netstat、arp、dns
- 文件操作：ls、cat、echo、cp、mv、rm、mkdir
- 进程管理：kill、killall、nice、jobs、fg、bg
- 高级功能：heval（内核REPL）、tcploop、dnstest、advtest、lsmod、kmodtest
- 压缩/编码：各类压缩、编码、加密算法的测试命令
- 应用工具：sqlite、diff、profiler、calc、paint、compress、hexedit、notepad

## 推荐构建方式

```powershell
.\hl-bootstrap.cmd test
```

## 常用验证命令

```powershell
# 完整门禁测试
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1

# 发布验证
powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1

# QEMU 冒烟测试
powershell -ExecutionPolicy Bypass -File .\scripts\qemu-smoke.ps1

# 工作区验证
powershell -ExecutionPolicy Bypass -File .\scripts\validate-workspace.ps1
```

## 仓库结构

```text
HicOS/
├─ bare-kernel/
│  ├─ hl/                      # 232 个内核模块（~76,000 行）
│  └─ kernel.bin              # 编译产物（30,704 字节）
├─ scripts/                   # 28 个构建/验证脚本（9,729 行）
├─ IP-Protection/             # 60 个知识产权文件
├─ hl-bootstrap.hl            # 自举编译器（4,306 行，208 函数）
├─ stdlib.hl                  # 标准库（1,385 行，143 函数）
├─ kinterp.hl                 # 解释器（1,245 行，树遍历 + IR VM）
├─ kernel_entry.hl            # 内核入口（9,428 行）
├─ HicOS_*.hl                 # 27 个子系统模块
├─ test_*.hl / test-*.hl      # 19 个测试文件
├─ hicos-hl.img               # BIOS 镜像（162,816 字节）
├─ hicos-uefi.img             # UEFI 镜像（33 MB）
└─ *.md                       # 9 个文档
```

## 技术特点

### 纯 H-L 实现

- **零外部依赖**：无 C/C++/Rust，无 JSON/YAML，无 npm/cargo
- **自举工具链**：编译器、链接器、解释器全部用 H-L 编写
- **语言特性**：
  - 动态类型数组
  - 函数作为一等公民
  - 模拟位运算（算术运算替代）
  - 简洁的语法（类似 JavaScript + C 混合风格）

### 内核架构

- **三层分离**：镜像构建、工具链、内核模块完全解耦
- **模块化设计**：232 个独立 .hl 模块，每个专注单一功能
- **热补丁能力**：运行时加载/卸载/替换内核模块
- **双执行引擎**：树遍历解释器 + IR VM，性能与灵活性兼顾

### 系统能力

- **多核支持**：SMP、Per-CPU 队列、MLFQ 调度
- **网络完备**：从 L2 到 L7，覆盖主流协议
- **加密全面**：国密算法（SM3/SM4）+ 国际标准（AES/RSA/SHA）
- **压缩丰富**：从快速（LZ4/Snappy）到高压缩比（LZMA/Bzip2/Zstd/Brotli）
- **图形界面**：完整的窗口系统和桌面环境

## 验证状态

✅ 工作区验证：301 HL 文件 / 232 模块 / 0 stub  
✅ 编译通过：2,200+ 函数，2,500+ 符号  
✅ 功能测试：内核自测、回环测试、高级验证全部通过  
✅ 镜像启动：BIOS/UEFI 双模式可引导  

## 相关文档

- `PROJECT_STATUS.md`：项目状态与统计
- `ARCHITECTURE.md`：三层架构说明
- `ROADMAP.md`：已完成阶段与路线图
- `CHANGELOG.md`：详细迭代记录（246 个迭代）
- `UI_DESIGN_PLAN.md`：UI 设计策划
- `HILBERT_LANG_BNF.md`：H-L 语言语法规范
- `FIVE_OS_COMPARISON.md`：与五个知名 OS 对比
- `THREE_SYSTEM_COMPARISON.md`：三系统架构对比

## 开发状态

**活跃开发中** - 持续添加新模块和功能

最新迭代（246）：Brotli 压缩 + SM3 哈希 + SM4 分组密码

## License

本项目为教育与研究目的开发，所有源代码采用自研 Hilbert-Lang 编写。
