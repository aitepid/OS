# HicOS 项目推进大纲

> 生成日期：2026-06-01 ｜ 基线：Sprint 33 完成（GUI render loop 已接线）
> 配套文档：`ROADMAP.md`（详细版）、`PROJECT_STATUS.md`（实时快照）、`CHANGELOG.md`（历史细节）

---

## 一、项目定位

HicOS 是一台用自研 **Hilbert-Lang (H-L)** 语言从零自举的裸机 x86_64 实验性操作系统：

- **零外部依赖**：无 C/Rust/Node/Python 运行依赖；编译器、内核、Shell、GUI 均为 H-L
- **唯一例外**：`scripts/rebuild-image.ps1`（PowerShell 直写机器码作镜像发射器）
- **可运行形态**：BIOS 启动盘 `hicos-hl.img`（741 KB）+ UEFI 镜像 `hicos-uefi.img`
- **关联 IP 资产**：`IP-Protection/` 内已备齐 2 件 USPTO 专利申请草案（Hilbert-Curve OS / Self-Bootstrap Toolchain）

---

## 二、当前基线（Sprint 33 实测）

| 指标 | 值 |
|---|---:|
| 总 H-L 源文件 | 539 |
| 内核模块 (`bare-kernel/hl/`) | 470 |
| 顶层子系统 (`HicOS_*.hl`) | 28 |
| H-L 总行数 | 131,362 |
| Shell 命令 | 1,800 |
| 编译产出函数 | 5,598 |
| Linker 符号 | 6,401 |
| `kernel.bin` | 609,207 B @ 0x120000 |
| 启动镜像 | 741,376 B |
| 流水线耗时 | ≈115 min |
| **未解析重定位** ⚠ | 1,871 |
| **Token balance errors** ⚠ | 17 |

---

## 三、文件资产盘点

### 3.1 源码层

| 类别 | 路径 | 数量 | 角色 |
|---|---|---:|---|
| 顶层子系统 | `HicOS_*.hl` | 28 | Kernel / FS / Net / GUI / Audio / 安全栈 |
| 内核模块 | `bare-kernel/hl/*.hl` | 470 | gfx / compositor / widget / shell / app / 算法库 |
| 编译/构建链 | `bootstrap.hl` `build.hl` `build-hl-image.hl` `manifest.hl` `stdlib.hl` | 5 | 自举入口 |
| 测试套件 | `test_*.hl` `test-suite.hl` `test-runner.hl` | 18 | 单元 / 链路 / 回归 |
| 计划文档 (HL) | `*_PLAN.hl` `EVOLUTION_PLAN.hl` `PROGRESS_ANALYSIS.hl` | 6 | 内部规划（H-L 描述） |

### 3.2 工具链层

| 路径 | 数量 | 用途 |
|---|---:|---|
| `scripts/*.ps1` | 33 | 编译流水线 / 镜像构建 / QEMU 启动 / 诊断 / 发布闸门 |
| `bare-kernel/kernel.bin` `kernel.entry` `kernel-symbols.json` | 3 | 当前内核产物与符号表 |
| `BOOTX64.EFI` | 1 | UEFI 启动器 |

### 3.3 文档与 IP

| 路径 | 内容 |
|---|---|
| `README.md` `ARCHITECTURE.md` `ROADMAP.md` `CHANGELOG.md` `PROJECT_STATUS.md` `GUI_DESIGN.md` `HILBERT_LANG_BNF.md` | 项目主文档（共 ~6,200 行） |
| `IP-Protection/` | 2 件 USPTO 专利草案 + 表格 + 证据保全 + 商业机密政策 |
| `LICENSE.txt` | 许可证 |

### 3.4 运行时产物（构建/调试输出）

- `hicos-hl.img` / `hicos-uefi.img` / `hicos-disk.img` — 三种镜像
- `qemu-*.log`（120+ 文件）— 每轮 QEMU 测试串口/调试输出
- `pipeline-*.log`、`rebuild-*.log`、`serial*.log` — 编译/重建/串口日志
- `qemu-screen*.ppm` — 屏幕截图

> 这些日志体量大，长期建议挪到 `logs/` 子目录或加入 `.gitignore`，本次按用户指示全量推送。

---

## 四、推进大纲（按优先级与依赖排序）

### 阶段 A — 编译质量收尾（P1，必做）

| 编号 | 任务 | 依赖 | 验收 |
|---|---|---|---|
| **A1** | Sprint 34：tokenizer 字符串内括号修复 | `scripts/hl-compile-pipeline.ps1` lex 阶段改造 | balance errors = 0 |
| **A2** | Sprint 35：unresolved relocs 枚举 + 分类 | `Link-Pass2` 增加 dump | `unresolved-syms.txt` 完整产出 |
| **A3** | A2 后续：按类别绑定/补 stub/删死代码 | `kernel-symbols.json` 扩展 | unresolved < 50 |
| **A4** | `neural.hl` 真实 `Mismatched ]` 修正 | 源码修正 | parse warning ≤ 5 |

### 阶段 B — GUI 实化（P1，并行启动 G2/G3）

| 编号 | Sprint | 产物 | 关键模块 | 可视验收 |
|---|---|---|---|---|
| **B1** | G2 | 双缓冲 + 矢量图形 | `gfx_backbuffer.hl` `gfx_aa.hl` `gfx_path.hl` `font_atlas.hl` | QEMU 中 AA 文字 + 圆角窗口 |
| **B2** | G3 | 合成器 + 模糊 + 阴影 | `compositor.hl` `gfx_blur.hl` `gfx_shadow.hl` | 毛玻璃 + 阴影可见 |
| **B3** | G4 | 输入路由 + 鼠标指针 | `input_pointer.hl` `input_gesture.hl` | 鼠标可点击 Dock 与拖拽窗口 |
| **B4** | G5 | 动画系统 | `gfx_anim.hl` `anim_tuning.hl` | 60 FPS 窗口动画 |
| **B5** | G6 | 应用框架完整化 | `app_terminal` `app_files` `app_settings` `app_sysmon` `app_texteditor` | 五应用可用不崩 |
| **B6** | G7 | HiDPI + 多显示器 | `gfx_hidpi.hl` `display_topology.hl` `multimon.hl` | 1×/1.5×/2× 缩放 + 跨屏 |
| **B7** | G8 | IME + A11y + 护眼 | `ime.hl` `a11y.hl` `eyecare.hl` | 拼音输入 + 屏幕阅读器 |

### 阶段 C — 内核与系统强化（P2）

| 编号 | 任务 | 摘要 |
|---|---|---|
| C1 | POSIX/musl shim 真机互操作验证 | M6 代码已落，需通跑全套测试 |
| C2 | TCP/IP 一致性测试 | 通过 RFC 一致性测试套件 |
| C3 | 文件系统持久化压测 | ext2 + 加密层 IO 压力 |
| C4 | 容器运行时端到端 | `HicOS_ContainerRuntime.hl` 端到端 demo |

### 阶段 D — 平台扩展（P3，长期）

| 编号 | 方向 | 关键产物 |
|---|---|---|
| D1 | WASM 后端 | H-L → WebAssembly，浏览器中运行 HicOS shell |
| D2 | ARM64 移植 | 树莓派 / Apple Silicon 启动 |
| D3 | RISC-V 移植 | RV64GC，QEMU RISC-V 启动 |
| D4 | 分布式 HicOS | 多节点 Raft + 分布式 FS |
| D5 | 正式验证 | 核心分配器 Coq/Lean 证明 |

### 阶段 E — 知识产权与发布（P2 平行推进）

| 编号 | 任务 | 状态 |
|---|---|---|
| E1 | Patent 01（Hilbert-Curve OS）USPTO 提交 | 草案+签名件齐全，待最终提交 |
| E2 | Patent 02（Self-Bootstrap Toolchain）USPTO 提交 | 同上 |
| E3 | 商业机密政策落地 | `TRADE_SECRET_POLICY.txt` 已起草 |
| E4 | 仓库 release tag 与发布闸门 | `scripts/release-validate.ps1` `full-gate.ps1` 已就位 |

### 阶段 F — 仓库卫生（P2，建议本周完成）

| 编号 | 任务 | 收益 |
|---|---|---|
| F1 | 日志归档：`pipeline-*.log` `qemu-*.log` `serial*.log` 移至 `logs/` 并 `.gitignore` | 减少 Git 噪声 ~150 文件 |
| F2 | `.tmp/`、`*.ppm`、`rebuild-*.log` 加 `.gitignore` | 同上 |
| F3 | 添加 `.editorconfig` 与 PowerShell `-Encoding UTF8` 规范（已修过 1 次根因） | 防 GB2312/UTF-8 误读 |
| F4 | CI 接入（GitHub Actions）：每 PR 跑 `diag-balance.ps1` + lint | 防回退 |

---

## 五、关键命令速查

```powershell
# 完整编译流水线（≈115 min）
powershell -ExecutionPolicy Bypass -File .\scripts\hl-compile-pipeline.ps1

# Balance error 快速诊断（独立 < 1 min）
powershell -ExecutionPolicy Bypass -File .\scripts\diag-balance.ps1

# 镜像重建
powershell -ExecutionPolicy Bypass -File .\scripts\rebuild-image.ps1

# 发布闸门
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1

# QEMU 启动（GUI）
qemu-system-x86_64 -drive format=raw,file=hicos-hl.img -vga std -display sdl -m 256M

# QEMU 启动（串口）
qemu-system-x86_64 -drive format=raw,file=hicos-hl.img -serial stdio -display none -m 256M
```

---

## 六、推进里程碑预测

| 里程碑 | 内容 | 预估 |
|---|---|---|
| **M7** | 阶段 A 全部完成（编译零警告） | 1–2 个 Sprint |
| **M8** | 阶段 B 完成 G2–G4（GUI 可见可交互） | 3–4 个 Sprint |
| **M9** | 阶段 B 完成 G5–G8（GUI 全功能） | 4–6 个 Sprint |
| **M10** | 阶段 E 专利 USPTO 提交完成 | 与 M7 平行 |
| **M11** | 阶段 D1（WASM 后端 demo） | M9 之后 |
| **M12** | 阶段 D2/D3 之一（ARM64 或 RISC-V） | 长期 |

---

## 七、风险与依赖

| 风险 | 等级 | 缓解 |
|---|---|---|
| 1,871 unresolved relocs 中含真实运行时缺失 | 高 | A2 枚举先行，按类别分流 |
| GUI 路径无符号导致 boot 后空指针 | 中 | A3 扩 `kernel-symbols.json` |
| PowerShell 脚本编码差异（GB2312 vs UTF-8） | 中 | F3 强制 `-Encoding UTF8`（根因已修） |
| 日志/镜像膨胀仓库体积 | 低 | F1/F2 .gitignore + logs/ |
| 无 CI 时回归难发现 | 中 | F4 GitHub Actions 接入 |

---

## 八、相关文档索引

- `ROADMAP.md` — Sprint 详细路线（G2–G8 + 长期）
- `PROJECT_STATUS.md` — 实时基线快照
- `CHANGELOG.md` — 全 Sprint 历史
- `ARCHITECTURE.md` — 三层架构与启动链
- `GUI_DESIGN.md` — Fluent Design 设计基线
- `HILBERT_LANG_BNF.md` — H-L 语言形式化文法
- `IP-Protection/` — 专利与商业机密资产
