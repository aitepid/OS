# HicOS Project Status

## 版本定位

当前仓库处于 `v6.0` 发布线之后、迭代 87 DNS TTL 哈希缓存里程碑。

## 本轮已核实状态

### 仓库规模

| 指标 | 当前值 |
|---|---:|
| 活跃 `.hl` 文件 | 176 |
| H-L 总行数 | 42,187 |
| `bare-kernel/hl/` 内核模块 | 114 |
| `kernel_entry.hl` 行数 | 10,404 |
| `kernel_entry.hl` 函数数 | 301 |
| `kernel_entry.hl` 原生命令 | 66 |
| `scripts/*.ps1` | 19 |
| PS1 总行数 | 9,486 |
| `shell.hl` 命令数 | 61 + pipe |
| `kernel_entry.hl` 侧命令分发 | 已扩展到 iteration 80 (含 pipe + grep) |

### 迭代 80 门禁结果（全量）

| 验证项 | 结果 | 详情 |
|---|---|---|
| `validate-workspace.ps1` | ✅ 通过 | 176 HL / 114 模块 / 0 非 HL |
| `boot-readiness.ps1` | ✅ 通过 | 启动链 + 内核初始化 + 镜像 |
| `runtime-path-readiness.ps1` | ✅ 通过 | IDT/PIT/KBD + SYSCALL + 网络 |
| `image-layout-readiness.ps1` | ✅ 通过 | MBR 签名 + 扇区布局 |
| `boot-binary-analysis.ps1` | ✅ 13/13 | Stage1/2 入口 + GDT/PAE/CR3/MSR |
| `perf-baseline.ps1` | ✅ 4/4 | 产物尺寸与源码规模 |
| `release-validate.ps1` | ✅ 18/18 | 双镜像 + EFI + 语言纯度 |
| `hl-bootstrap-build-test.ps1` | ✅ 通过 | 114 模块编译 + 镜像重建 |
| `qemu-boot-test.ps1` | ⬚ 跳过 | 当前环境未安装 QEMU |
| `qemu-uefi-test.ps1` | ⬚ 跳过 | 当前环境未安装 QEMU |

### 产物尺寸

| 产物 | 大小 |
|---|---:|
| `hicos-hl.img`（BIOS） | 150,528 字节 |
| `hicos-uefi.img`（UEFI） | 34,603,008 字节 |
| `BOOTX64.EFI` | 1,536 字节 |
| `kernel.bin` | 18,058 字节 |

## 三层架构现状

| 层级 | 载体 | 当前说明 |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | 当前 BIOS 镜像生成链仍在使用 |
| B | `hl-bootstrap.hl` | 自举编译器/解释器/工具链源码 |
| C | `bare-kernel/hl/*.hl` | 114 个内核模块源码，持续编译到 `kernel.bin` |

## 最近已同步到仓库的功能更新

### Iteration 80
- 阶段发布整理完成：README / STATUS / ROADMAP / CHANGELOG / PLAN 口径统一
- Host-side 门禁全部复核通过
- QEMU 相关门禁因当前环境未安装 QEMU 而标记为“跳过”

### Iteration 79
- `grep` 接入 kernel.bin 原生命令分发
- `_ke_putc` 集成管道捕获检查，`cmd1 | grep pattern` 可正常工作
- Shell 命令数 60 → 61

### Iteration 78
- Shell pipe 语法 (`cmd1 | cmd2`) 接入 kernel.bin 原生 shell
- 管道捕获缓冲区 4KB @ 0x370000
- `_ke_sc2ascii()` 扫描码表扩展 (`|` `[` `]` `` ` ``)

### Iteration 77
- `netstat` / `arp` 接入 kernel.bin 原生命令分发
- TCP 连接表扫描 + ARP 缓存显示 + 网络配置摘要
- Shell 命令数 58 → 60

### Iteration 76
- `hostname` / `uname` / `date` 接入 `kernel.bin` 原生命令分发
- `_ke_cmd_hostname()` / `_ke_cmd_uname()` / `_ke_cmd_date()` 新增
- 帮助文本新增第 11 行
- `shell.hl` 中 `uname` 输出统一

### Iteration 75
- 命令历史环形缓冲区（32 条 × 64 字节 @ 0x350000）
- ↑/↓ 方向键浏览历史、←/→ 光标移动（PS/2 扩展扫描码 0xE0 前缀）
- `history` 命令显示历史列表
- `hostname` 命令
- `shell.hl` 命令数 56 → 58
- 版本字符串统一更新为 6.0

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

- 在安装 QEMU 的主机上补跑 `qemu-boot-test.ps1` / `qemu-uefi-test.ps1`
- 进入 `81+` 阶段，优先做“发布后收敛 + 真实运行路径补齐”
- 继续保持 `README.md` / `ROADMAP.md` / `CHANGELOG.md` / `PROJECT_ADVANCEMENT_PLAN.hl` 同步



