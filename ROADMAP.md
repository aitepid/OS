# HicOS Roadmap

## 当前同步基线

本路线图基于当前仓库内容与本次已复核结果整理：
- `176` 个活跃 `.hl` 文件
- `114` 个内核模块
- `19` 个 PowerShell 脚本
- 构建/测试主入口：`scripts/hl-bootstrap-build-test.ps1`
- 最近已完成并接入文档的迭代：`73`、`74`

## 已完成的关键阶段

### 基础启动链
- BIOS 镜像生成链存在并可构建
- UEFI 镜像与 `BOOTX64.EFI` 产物存在
- `kernel.bin` 已接入镜像链

### 已接入 `kernel_entry.hl` 的连续能力
- 串口 / PIC / PIT / IDT / 键盘
- PCI 扫描
- 物理页分配器、堆分配器、任务表/基础调度
- VirtIO-blk / VirtIO-net 路径
- FAT16 基础命令
- `run` / 安装器 / 图形命令 / 用户命令 / 服务命令
- WiFi 检测 / 消息队列 / 环境变量 / 信号处理

### 最近两次迭代
- **Iteration 73**：环境变量与 `echo`
- **Iteration 74**：POSIX 风格信号处理与 `kill`

## 当前更准确的项目判断

- 项目已经不是“只有早期 20～30 条命令”的状态
- 但也不能将所有源码模块都视为“已完整完成运行验证”
- 更准确的说法是：
  - 仓库源码覆盖面很大
  - `kernel.bin` 集成功能在持续增长
  - 统一构建验证入口已经切到 `hl-bootstrap`
  - 文档必须区分“源码存在”“已接入镜像”“本轮已复核通过”三个层次

## 下一阶段建议

### P0：文档与验证口径继续收敛
- 保持 `README.md` / `PROJECT_STATUS.md` / `CHANGELOG.md` / `ARCHITECTURE.md` 一致
- 避免继续写入未经本轮复核的历史统计数字
- 需要时补跑 `full-gate.ps1` 并再同步一次结果

### P0：Shell / kernel.bin 连续迭代
建议沿当前迭代序列继续推进：
- `75`：命令历史 + 方向键
- `76`：`hostname` / `uname` / `date`
- `77`：`netstat` / `arp` 可视化增强
- `78`：管道重定向
- `79`：`grep`
- `80`：阶段性发布整理

### P1：将“源码存在”进一步转化为“接入镜像并验证”
重点关注：
- SMP / ACPI / 音频等真实运行路径
- 文件系统与 VFS 的更多真实命令闭环
- 网络命令的更完整接入与验证

### P1：继续以 `hl-bootstrap` 为中心
- 优先通过 `hl-bootstrap-build-test.ps1` 驱动构建与验证
- 避免重新回退到散乱脚本入口描述

## 当前推荐执行顺序

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\hl-bootstrap-build-test.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1
```

## 相关文件

- `PROJECT_STATUS.md`
- `CHANGELOG.md`
- `PROJECT_ADVANCEMENT_PLAN.hl`
- `COMPILER_PIPELINE_STRATEGY.hl`





