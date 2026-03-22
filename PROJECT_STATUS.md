# HicOS Project Status

## 版本定位

当前仓库处于 `v6.0` 发布线之后、继续沿高迭代号扩展 `kernel.bin` 命令与功能的状态。

## 本轮已核实状态

### 仓库规模

| 指标 | 当前值 |
|---|---:|
| 活跃 `.hl` 文件 | 176 |
| `bare-kernel/hl/` 内核模块 | 114 |
| `scripts/*.ps1` | 19 |
| `shell.hl` 注释命令数 | 56 |
| `kernel_entry.hl` 侧命令分发 | 已扩展到 iteration 74 |

### 本轮已执行并通过的验证

| 验证项 | 结果 |
|---|---|
| `scripts/hl-bootstrap-build-test.ps1` | ✅ 通过 |
| `scripts/boot-readiness.ps1` | ✅ 通过 |
| `scripts/runtime-path-readiness.ps1` | ✅ 通过 |
| `scripts/image-layout-readiness.ps1` | ✅ 通过 |
| `scripts/release-validate.ps1` | ✅ 通过 |

### 本轮未完整复核

- `scripts/full-gate.ps1`：本轮执行被中断，未作为“最新结论”写入文档
- 因此本文件不再把历史 `QEMU BIOS xxx/xxx`、`Full Gate 10/10` 直接当作最新现状陈述

## 三层架构现状

| 层级 | 载体 | 当前说明 |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | 当前 BIOS 镜像生成链仍在使用 |
| B | `hl-bootstrap.hl` | 自举编译器/解释器/工具链源码 |
| C | `bare-kernel/hl/*.hl` | 114 个内核模块源码，持续编译到 `kernel.bin` |

## 最近已同步到仓库的功能更新

### Iteration 73
- 环境变量表接入
- `env` / `setenv` / `echo`
- `_start()` 中已接入环境初始化

### Iteration 74
- 信号位掩码机制接入
- `kill <pid> [sig]`
- `ps` 增加信号相关显示
- `shell.hl` 的 `kill` 已从直接 `task_kill` 切换为 `signal_send(..., SIGTERM)`

## 当前更准确的结论

1. 项目已经完成从“仅靠手写早期引导逻辑”到“`kernel.bin` 持续接管功能”的长期迁移。
2. `hl-bootstrap` 已经是当前推荐的构建/测试入口。
3. 仓库中存在大量功能源码，但文档必须区分：
   - 源码存在
   - 已接入 `kernel.bin`
   - 本轮已重新验证
4. 当前文档已按这个口径清理。

## 下一步建议

- 补跑 `full-gate.ps1`，再同步一次门禁结果
- 继续沿 `75+` 迭代推进 Shell 能力
- 保持 `README.md` / `ROADMAP.md` / `CHANGELOG.md` / `PROJECT_ADVANCEMENT_PLAN.hl` 同步



