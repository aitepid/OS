# HicOS

HicOS 是一个实验性的 x86_64 裸机操作系统项目。它通过 BIOS 启动，使用 QEMU 作为主要验证环境，并以 Hilbert-Lang（H-L）源码实现内核模块、标准库、Shell 与大量子系统原型。

当前工程同时包含两部分启动实现：Python 镜像生成器负责输出 BIOS Stage 1、Stage 2 和底层机器码启动环境；Python H-L 编译流水线将 `bare-kernel/hl/` 下的 H-L 模块链接为 `kernel.bin`，由启动镜像在 `0x120000` 调用 `_start`。

## 当前状态

已验证的 QEMU 启动路径：

- BIOS Stage 1 和 Stage 2 启动
- 串口、PIC、PIT、PS/2、PCI、VESA 与 SYSCALL 的底层初始化日志
- H-L `_start` 入口调用
- H-L 串口、PIC、PIT、Stage 2 IDT 复用、物理页元数据、堆和任务初始化路径
- H-L 编译器的条件分支、调用重定位、整数除法/取模和严格错误模式

当前 H-L 启动日志会推进到 `KB-OK`、`PIC OK`、`PIT OK`、`IDT OK`、`INT-OK` 以及初始化阶段标记。后续 VirtIO、字体、用户系统、模块初始化和 H-L Shell 路径仍在持续修复中。

## 快速开始

### 前置条件

- Python 3
- QEMU x86_64：`qemu-system-x86_64`

### 构建

在仓库根目录执行：

```bash
HL_STRICT=1 python3 scripts/hl_pipeline.py
python3 scripts/rebuild-image.py
```

第一步会解析并链接 H-L 模块，生成：

- `bare-kernel/kernel.bin`：链接后的 H-L 内核负载
- `bare-kernel/kernel.entry`：`_start` 在内核负载内的偏移

第二步会把 BIOS 启动代码和 `kernel.bin` 组合为 `hicos-hl.img`。

### 运行

```bash
qemu-system-x86_64 \
  -drive format=raw,file=hicos-hl.img \
  -no-reboot \
  -display none \
  -serial mon:stdio \
  -m 256M
```

使用 `Ctrl-A X` 退出 QEMU。自动化验证可用有限时运行：

```bash
timeout 30 qemu-system-x86_64 \
  -drive format=raw,file=hicos-hl.img \
  -no-reboot \
  -display none \
  -serial mon:stdio \
  -m 256M
```

### 编译器回归测试

```bash
python3 -m unittest scripts/test_hl_pipeline.py
```

该测试覆盖 H-L IR 条件跳转：条件值来自 `dst` 虚拟寄存器，且分支重定位写入真实的 `rel32` 操作数字段。

## 启动架构

```text
BIOS
  -> Stage 1 (MBR)
  -> Stage 2 (模式切换、平台初始化、底层中断环境)
  -> 手写 x86_64 启动内核（0x100000）
  -> CALL 0x120000 + kernel.entry
  -> H-L _start
  -> H-L 子系统初始化与 Shell
```

`scripts/rebuild-image.py` 生成前三级内容并将 `kernel.bin` 附加到镜像。`scripts/hl_pipeline.py` 负责词法分析、解析、IR 构建、优化、x86_64 代码生成和跨模块链接。

## 项目结构

```text
.
├── bare-kernel/
│   ├── hl/                    H-L 内核模块、驱动、Shell 和运行时
│   ├── kernel.bin             构建生成的 H-L 内核负载
│   └── kernel.entry           构建生成的 H-L _start 偏移
├── scripts/
│   ├── hl_pipeline.py         H-L 编译、代码生成与链接流水线
│   ├── rebuild-image.py       BIOS 启动镜像生成器
│   └── test_hl_pipeline.py    编译器回归测试
├── hl-bootstrap.hl            H-L 自举编译器、解释器、链接器与 REPL
├── stdlib.hl                  H-L 标准库
├── HicOS_*.hl                 顶层子系统与服务原型
├── manifest.hl                项目元数据
├── hicos-hl.img               构建生成的 BIOS 启动镜像
└── BOOTX64.EFI                UEFI 启动文件
```

## 关键运行时地址

| 地址或范围 | 用途 |
|---|---|
| `0x7C00` | BIOS MBR / Stage 1 加载地址 |
| `0x8000` | Stage 2 加载地址 |
| `0x100000` | 手写 x86_64 启动内核 |
| `0x120000` | H-L `kernel.bin` 负载地址 |
| `0x300000` | 定时器、键盘和鼠标共享状态 |
| `0x720000` | H-L IDT 预留区域 |
| `0x730000` | H-L ISR thunk 预留区域 |
| `0x7D0000` | 键盘注入队列 |
| `0x7E0000` | Shell 管道捕获缓冲区 |
| `0xFD000000` | VESA 线性帧缓冲区 |

## 已知限制

- H-L IDT 构建器仍在隔离修复中；当前 `_start` 复用 Stage 2 建立的中断环境。
- H-L 物理页分配器的启动元数据已经写入，`pmem` 诊断路径仍需独立修复。
- H-L 后续设备、模块和 Shell 初始化仍在推进，README 不将其标注为端到端可用能力。
- `BOOTX64.EFI` 位于仓库中，UEFI 启动路径尚未在当前构建流程内验证。

## 许可证

见 `LICENSE.txt`。
