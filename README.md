# HicOS 6.0

纯 `Hilbert-Lang` 编写的实验性 x86_64 操作系统与自举工具链。

## 当前状态

- 代码仓库包含 `176` 个活跃 `.hl` 文件（共 `42187` 行）
- `bare-kernel/hl/` 下有 `114` 个内核模块
- `kernel_entry.hl`：`10404` 行，`301` 个函数，`66` 个原生命令
- `scripts/` 下有 `19` 个 PowerShell 构建/验证脚本（共 `9486` 行）
- Shell 命令数：`61` + pipe 操作符（`cmd1 | cmd2`）+ `grep` 过滤
- 最新完成迭代：`80`（迭代 73-80 连续完成）
- 当前主构建/测试入口：`scripts/hl-bootstrap-build-test.ps1`
- 当前仓库仍同时保留：
  - `Layer A`：`scripts/rebuild-image.ps1` 生成的可引导镜像路径
  - `Layer B`：`hl-bootstrap.hl` 自举编译器/工具链源码
  - `Layer C`：`bare-kernel/hl/*.hl` 内核源码与 `kernel.bin` 编译产物

## 迭代 80 阶段发布整理 — 门禁结果

| 验证项 | 结果 | 说明 |
|---|---|---|
| `validate-workspace.ps1 -StrictLanguagePurity` | ✅ 通过 | 176 HL / 114 模块 / 0 非 HL |
| `boot-readiness.ps1` | ✅ 通过 | 启动链 / 内核初始化 / 镜像 |
| `runtime-path-readiness.ps1` | ✅ 通过 | IDT/PIT/KBD / SYSCALL / 网络 |
| `image-layout-readiness.ps1` | ✅ 通过 | MBR 签名 / 扇区布局 |
| `boot-binary-analysis.ps1` | ✅ 13/13 | Stage1+2+内核全部通过 |
| `perf-baseline.ps1` | ✅ 4/4 | 产物尺寸与源码规模正常 |
| `release-validate.ps1` | ✅ 18/18 | 双镜像 + EFI + 完整性 |
| `hl-bootstrap-build-test.ps1` | ✅ 通过 | 编译管线 + 镜像重建 + 验证 |
| `qemu-boot-test.ps1` | ⬚ 主机相关 | 依赖当前主机已安装 QEMU |
| `qemu-uefi-test.ps1` | ⬚ 主机相关 | 依赖当前主机已安装 QEMU + OVMF |

## 当前功能轮廓

### `kernel_entry.hl` / `kernel.bin`
当前已包含并接入镜像构建链的重点能力：
- 串口、PIC、PIT、IDT、键盘中断（含 PS/2 扫描码扩展）
- PCI 扫描
- 物理页分配器、堆分配器、基础任务调度
- VirtIO-blk / VirtIO-net 相关路径
- FAT16 基础闭环、`run`、安装器
- 图形/窗口/字体相关命令接入
- 用户、服务、WiFi 检测、消息队列、环境变量、信号处理
- 命令历史 + 方向键（↑↓ 历史浏览，←→ 光标移动）
- `hostname` / `uname` / `date` 原生命令
- `netstat`（TCP 连接表）/ `arp`（ARP 缓存）
- Shell pipe（`cmd1 | cmd2`，输出捕获 + 右侧过滤）
- `grep`（管道子串过滤）

### `shell.hl`
- 当前 `shell.hl` 为 `61` 个命令的串口 Shell + pipe 操作符
- `kill` 已切换为信号语义，默认发送 `SIGTERM`
- `uname` 输出统一为 `HicOS 6.0 x86_64 Hilbert-Lang`

## 推荐构建方式

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\hl-bootstrap-build-test.ps1
```

该入口会执行：
- `boot-readiness.ps1`
- `image-layout-readiness.ps1`
- `hl-compile-pipeline.ps1`
- `rebuild-image.ps1`
- `validate-workspace.ps1 -StrictLanguagePurity`
- `runtime-path-readiness.ps1`

## 常用验证命令

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-workspace.ps1 -StrictLanguagePurity
powershell -ExecutionPolicy Bypass -File .\scripts\boot-readiness.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\runtime-path-readiness.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\image-layout-readiness.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1
```

如需完整门禁：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1
```

如当前主机未准备好 `QEMU/OVMF`，可显式跳过：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1 -SkipQemu
```

如要求 `QEMU` 门禁必须通过（缺少前置条件也视为失败）：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1 -RequireQemu
```

## 仓库结构

```text
HicOS/
├─ bare-kernel/
│  ├─ hl/                      # 114 个内核模块
│  └─ kernel.bin              # 编译产物
├─ scripts/                   # 构建、镜像、QEMU、验证脚本
├─ hl-bootstrap.hl            # 自举编译器/工具链源码
├─ stdlib.hl                  # 标准库
├─ hicos-hl.img               # BIOS 镜像产物
├─ hicos-uefi.img             # UEFI 镜像产物
├─ BOOTX64.EFI                # UEFI 应用产物
└─ *.md / *.hl               # 文档、策划案、分析与测试文件
```

## 相关文档

- `PROJECT_STATUS.md`：当前项目状态与本次验证结论
- `ARCHITECTURE.md`：三层架构与启动/构建链说明
- `ROADMAP.md`：已完成阶段与下一阶段路线
- `CHANGELOG.md`：最近迭代更新
- `PROJECT_ADVANCEMENT_PLAN.hl`：同步后的推进策划案

## 约束

- 项目必须保持 `Pure H-L`
- 不引入 JS / Rust / JSON 等新依赖
- 优先使用 `hl-bootstrap` 入口推进构建与验证

