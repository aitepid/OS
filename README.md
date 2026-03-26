# HicOS 6.0

纯 `Hilbert-Lang` 编写的实验性 x86_64 操作系统与自举工具链。

## 当前状态

- 代码仓库包含 `185` 个 `.hl` 文件（共 `43,246` 行）
  - 根目录：`68` 个（含自举编译器、标准库、子系统模块、测试与策划案）
  - `bare-kernel/hl/`：`117` 个内核模块（`33,260` 行，源码定义 `1,499` 个函数）
- `kernel_entry.hl`：`9,565` 行
- `hl-bootstrap.hl`：`4,306` 行（自举编译器/工具链，编译管线统计 `208` 个函数）
- `stdlib.hl`：`1,385` 行（标准库，编译管线统计 `143` 个函数）
- `kinterp.hl`：`1,245` 行（树遍历 + IR VM 双执行引擎）
- `scripts/` 下有 `22` 个 PowerShell 构建/验证脚本（共 `8,816` 行）
- Shell + 内核命令总数：`112`（去重后）
- 当前功能里程碑仍为 `119`（高级特性验证接入基线：eBPF / TLS 1.3 / QUIC），其后已完成多轮工程化修复与回归补强
- 当前主构建/测试入口：`hl-bootstrap.cmd test`（封装 `scripts/hl-bootstrap-build-test.ps1`）
- 三层架构：
  - `Layer A`：`scripts/rebuild-image.ps1` → 可引导 BIOS 镜像
  - `Layer B`：`hl-bootstrap.hl` 自举编译器/工具链
  - `Layer C`：`bare-kernel/hl/*.hl` → `kernel.bin`

## 产物

| 产物 | 大小 |
|---|---:|
| `hicos-hl.img`（BIOS） | 160,256 字节 |
| `hicos-uefi.img`（UEFI） | 34,603,008 字节 |
| `kernel.bin` | 27,970 字节 |

## 迭代 81-119：六阶段完成 + 高级特性验证接入

| 阶段 | 模块 | 升级 |
|---|---|---|
| 1 内存 | `page_alloc` `kmalloc` `block_cache` `hilbert_alloc` | 伙伴系统 / 空闲链表 / 哈希LRU / 归并排序 |
| 2 网络 | `tcp` `dns` `vfs` | Reno拥塞 / TTL缓存 / Trie前缀树 |
| 3 多核 | `arp+net` `ext2` `swap` `smp` | 哈希表 / inode缓存 / 增强时钟 / Per-CPU队列 |
| 4 调度 | `sched` `mmap` `pipe` `tls` | MLFQ / 按需COW / SPSC环形 / TLS1.3状态机 |
| 5 隔离 | `sync` `poll` `cgroup` `bpf` | futex哈希队列 / 边缘触发epoll / cgroup强制 / eBPF VM |

### 阶段 6（迭代 109-114）
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

## 当前功能

### 内核
- 串口、PIC、PIT、IDT、键盘中断（PS/2 扫描码）
- PCI 扫描、VirtIO-blk/net、AHCI、NVMe、USB
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

### Shell + 内核命令（112 唯一命令 + pipe）
- 环境变量、信号处理、命令历史、方向键导航
- shell.hl（64 命令）：hostname / uname / date / netstat / arp / grep / heval / tcploop / dnstest / advtest / ...
- kernel_entry.hl（70 命令）：compile / lex / parse / malloc / palloc / sha256 / tls / wget / browse / ...

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
│  ├─ hl/                      # 117 个内核模块（33,260 行）
│  └─ kernel.bin              # 编译产物（27,970 字节）
├─ scripts/                   # 22 个构建/验证脚本（8,816 行）
├─ hl-bootstrap.hl            # 自举编译器（4,306 行）
├─ stdlib.hl                  # 标准库（1,385 行）
├─ HicOS_*.hl                 # 27 个子系统模块
├─ test_*.hl / test-*.hl      # 18 个测试文件
├─ hicos-hl.img               # BIOS 镜像
├─ hicos-uefi.img             # UEFI 镜像
└─ *.md                       # 8 个文档
```

## 相关文档

- `PROJECT_STATUS.md`：当前项目状态
- `ARCHITECTURE.md`：三层架构说明
- `ROADMAP.md`：已完成阶段与路线图
- `CHANGELOG.md`：迭代更新记录
- `PROJECT_ADVANCEMENT_PLAN.hl`：推进策划案
- `HILBERT_LANG_BNF.md`：语言语法规范
