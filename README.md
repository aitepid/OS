# HicOS 6.0

纯 `Hilbert-Lang` 编写的实验性 x86_64 操作系统与自举工具链。

## 当前状态

- 代码仓库包含 `176` 个活跃 `.hl` 文件
- `bare-kernel/hl/` 下有 `114` 个内核模块
- `scripts/` 下有 `19` 个 PowerShell 构建/验证脚本
- 当前主构建/测试入口：`scripts/hl-bootstrap-build-test.ps1`
- 当前仓库仍同时保留：
  - `Layer A`：`scripts/rebuild-image.ps1` 生成的可引导镜像路径
  - `Layer B`：`hl-bootstrap.hl` 自举编译器/工具链源码
  - `Layer C`：`bare-kernel/hl/*.hl` 内核源码与 `kernel.bin` 编译产物

## 本次同步后可确认的事实

- `hl-bootstrap-build-test.ps1` 已通过
- `boot-readiness.ps1` 已通过
- `runtime-path-readiness.ps1` 已通过
- `image-layout-readiness.ps1` 已通过
- `release-validate.ps1` 已通过
- `PROJECT_STATUS.md`、`ROADMAP.md`、`CHANGELOG.md`、`ARCHITECTURE.md` 已按当前仓库重新整理

说明：
- 本次文档清理未重新完整跑完 `full-gate.ps1`
- 因此 README 不再继续写入未经本次复核的 `QEMU 141/141`、`Full Gate 10/10` 等历史数字

## 当前功能轮廓

### `kernel_entry.hl` / `kernel.bin`
当前已包含并接入镜像构建链的重点能力：
- 串口、PIC、PIT、IDT、键盘中断
- PCI 扫描
- 物理页分配器、堆分配器、基础任务调度
- VirtIO-blk / VirtIO-net 相关路径
- FAT16 基础闭环、`run`、安装器
- 图形/窗口/字体相关命令接入
- 用户、服务、WiFi 检测、消息队列、环境变量、信号处理等迭代命令

### `shell.hl`
- 当前 `shell.hl` 为 `56` 个命令的串口 Shell
- `kill` 已切换为信号语义，默认发送 `SIGTERM`

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

