# HicOS Roadmap

> 最后更新：2026-05-22（Sprint 33 完成后）

---

## 当前同步基线（Sprint 33，2026-05-20 实测）

| 指标 | 当前值 |
|---|---:|
| 总 `.hl` 源文件 | **539** |
| `bare-kernel/hl/` 内核模块 | **470** |
| 顶层子系统 `HicOS_*.hl` | **28** |
| H-L 总行数 | **131,362** |
| Shell 命令 | **1,800** |
| 编译产出函数 | **5,598** |
| Linker 符号数 | **6,401** |
| `bare-kernel/kernel.bin` | **609,207 B @ 0x120000** |
| `hicos-hl.img`（BIOS 启动盘） | **741,376 B** |
| 未解析重定位 ⚠ | **1,871** |
| Token 级 balance error ⚠ | **17** |
| 最近完成 Sprint | **Sprint 33**（GUI render loop 接线，桌面 boot 后可见）|

---

## 已完成阶段总览

### 里程碑 M1–M6（全部完成 ✦）

| 里程碑 | 内容 | 完成时间 |
|---|---|---|
| M1 | 核心内核（内存/中断/进程/文件系统） | iter 1–80 |
| M2 | 网络协议栈（TCP/IP/DNS/DHCP/TLS/QUIC） | iter 81–120 |
| M3 | 加密全覆盖 + 高级序列化格式 | iter 121–180 |
| M4 | 编译器 / H-L 自举 + 完整 Shell | iter 181–246 |
| M5 | 算法大库（数据结构 + 图论 + AI/ML） | iter 247–320 |
| M6 | GUI 脚手架（47 模块，Fluent Design 骨架） | Sprint G1 |

---

### Bug-fix Sprints 1–33（全部完成 ✦）

**Sprint 1–16**：初始质量修复——变量遮蔽、数组越界、null 解引用、作用域错误；覆盖 400+ 模块。

**Sprint 17**：全仓函数体变量 `let mut` 规范化（400+ 文件）。

**Sprint 18–20**：商业级 UI Design Token 系统 + Widget 控件扩展。

**Sprint 21–25**：所有 UI 应用 Design Token 迁移（terminal / calculator / settings / sysmon / taskman / clock 等 6 个应用全量升级）。

**Sprint 26–28**：QEMU 可视化压力测试（3 轮次），修复 BUG-001 至 BUG-040。

**Sprint 29–31**：文档整合 + 遗留模块修复。

**Sprint 32**：QEMU Round 5 压力测试，修复 BUG-061 至 BUG-064（mime / http2 / toml / xml 边界问题）。

**Sprint 33**：GUI render loop 接线——`shell_wallpaper_paint` / `shell_topbar_paint` / `shell_dock_paint` / `compositor_present` / `gfx_present` / `vesa_flip` 插入 kernel_init，boot 后桌面可见。

---

### Codegen Sprints 35–38（全部完成 ✦）

| Sprint | 内容 |
|---|---|
| 35 | IR lowering 基础框架，`_start` 入口函数生成 |
| 36 | parser recovery 修复，AST 一致性 |
| 37 | `IR-LowerStmt` 单层数组包装根因修复（IR instr ×9.4，.text ×3.6） |
| 38 | 字符串字面量池 + abs64 重定位（`IR_STR_CONST` 全链路） |

---

### GUI Sprints G1（完成 ✦）

| Sprint | 内容 |
|---|---|
| G1 | 47 GUI 模块脚手架落地（gfx / compositor / wm_snap / widget_\* / shell_\* / app_\* / input_\* / 服务层）；`GUI_DESIGN.md` 设计基线文档；3 个审计脚本 |

---

## 当前已知问题 ⚠

| 问题 | 数量 | 定位 | 优先级 |
|---|---:|---|---|
| 未解析重定位（unresolved relocs） | **1,871** | 跨模块前向声明 + builtin 绑定缺失 | P1 |
| Token 级 balance error | **17** | 字符串字面量内含 `{` `}`（tokenizer 误识别） | P1 |
| 告警模块（parse/balance warning） | **12** | a11y / app_texteditor / consistent_hash / display_topology / ime / neural / shell_dock / shell_form / shell_wallpaper / vdesktop / visual_audit | P2 |
| kernel-symbols.json 符号不全 | 3 个（仅 serial_puts / serial_hex_byte / base） | 缺 framebuffer / input / heap 等 GUI 路径符号 | P2 |

---

## 下一阶段计划

### Sprint 34 — Tokenizer 字符串括号修复（balance errors → 0）

**目标**：修复 `scripts/hl-compile-pipeline.ps1` tokenizer，在字符串字面量内不把 `{` `}` `[` `]` 算作 bracket token，让 17 个 balance error 归零。

**工作范围**：
- 修改 `hl-compile-pipeline.ps1` 的 lex 阶段，添加字符串内括号跳过逻辑
- 重跑 `scripts/diag-balance.ps1` 验证 balance error = 0
- 重跑完整编译流水线确认 17 → 0

**验收**：`hl-compile-pipeline.ps1` 472/472，balance errors = 0，5 个 parse warnings ≤ 5。

---

### Sprint 35 — Unresolved Relocs 枚举 + 绑定

**目标**：把 1,871 个未解析重定位降到 0 或 < 50（合理 stub 范围）。

**步骤**：
1. 在 `Link-Pass2` 阶段 dump 所有 unresolved 目标符号名到 `unresolved-syms.txt`
2. 分类：① 真前向声明（需 H-L 实现）；② builtin/runtime（需 PowerShell stub）；③ 死代码（可删调用）
3. 按类别处理：扩展 `kernel-symbols.json`，添加 framebuffer / input / heap 等路径符号
4. 重跑流水线验证

**验收**：unresolved relocs < 50，kernel.bin 启动后 `HicOS>` 正常，GUI 路径无空指针。

---

### Sprint G2 — 双缓冲 + 矢量图形基础

**目标**：`gfx_backbuffer.hl` / `gfx_aa.hl` / `gfx_path.hl` / `font_atlas.hl` 从脚手架转为可工作实现。

| 模块 | 目标实现 |
|---|---|
| `gfx_backbuffer.hl` | 双缓冲交换（前帧/后帧 VESA LFB，`gfx_flip()` 原子切换） |
| `gfx_aa.hl` | 4× 超采样抗锯齿，线段/圆弧 AA 路径 |
| `gfx_path.hl` | 矢量路径：移动/直线/贝塞尔曲线，填充 + 描边 |
| `font_atlas.hl` | 位图字体 atlas（8/13/17/22 px），ASCII + 3500 CJK 字形 |

**验收**：QEMU 中看到 AA 渲染的文字和圆角窗口，无闪烁。

---

### Sprint G3 — 合成器 + 模糊 + 阴影

**目标**：`compositor.hl` / `gfx_blur.hl` / `gfx_shadow.hl` 实现化。

| 模块 | 目标实现 |
|---|---|
| `compositor.hl` | 脏矩形合成，Z-order 层叠，`compositor_present()` 真实实现 |
| `gfx_blur.hl` | Box blur × 3 pass 模拟高斯，Mica/Acrylic 毛玻璃效果 |
| `gfx_shadow.hl` | 三档阴影（16/24/32 px，RGB 扩散），窗口投影 |

**验收**：窗口后方有毛玻璃模糊效果，窗口阴影清晰。

---

### Sprint G4 — 输入路由 + 鼠标指针

**目标**：`input_pointer.hl` / `input_gesture.hl` 实现化，鼠标事件从 PS/2 驱动路由到 WM 再到窗口。

| 工作项 | 说明 |
|---|---|
| 鼠标指针渲染 | 32×32 ARGB 软件光标，覆盖 compositor 最顶层 |
| WM 鼠标分发 | 点击 hit-test → 窗口 focus/raise；拖拽移动窗口；边缘 resize |
| 手势识别 | 双指捏合缩放、三指切换虚拟桌面 |
| Shell 集成 | Dock/Topbar 响应点击，启动/切换应用 |

**验收**：鼠标可移动，可点击 Dock 图标，可拖拽/调整窗口大小。

---

### Sprint G5 — 动画系统

**目标**：`gfx_anim.hl` / `anim_tuning.hl` 实现化，窗口打开/关闭/最小化有 Fluent 动画。

| 工作项 | 说明 |
|---|---|
| 动画计时器 | 基于 `hrtimer.hl`，16 ms 帧间隔（60 FPS 目标） |
| Easing 曲线 | cubic-bezier(0.2, 0, 0, 1)，167/250/333 ms 档位 |
| 窗口动画 | 打开放大（scale 0.96→1.0），关闭缩小（1.0→0.96），最小化飞入 Dock |
| 微交互 | 按钮按下 scale 0.96×，Reveal 高光悬停跟随 |

**验收**：窗口打开/关闭有平滑动画，60 FPS 稳定。

---

### Sprint G6 — 应用框架完整化

**目标**：将 `app_terminal` / `app_files` / `app_settings` / `app_sysmon` / `app_texteditor` 从脚手架升级为可用应用。

| 应用 | 目标 |
|---|---|
| `app_terminal.hl` | 接入 `pty.hl` + `shell.hl`，真实终端交互（输入/回显/滚动） |
| `app_files.hl` | VFS 文件列表、目录导航、图标网格视图 |
| `app_settings.hl` | 主题切换（亮/暗/护眼）、分辨率、用户账户 |
| `app_sysmon.hl` | CPU/内存/网络实时图表（读 `procfs.hl` / `sched.hl`） |
| `app_texteditor.hl` | 语法高亮、多 tab、文件保存（接 `ext2.hl`） |

**验收**：五个应用可独立使用，不崩溃。

---

### Sprint G7 — HiDPI + 多显示器

**目标**：`gfx_hidpi.hl` / `display_topology.hl` / `multimon.hl` 实现化。

| 工作项 | 说明 |
|---|---|
| HiDPI 缩放 | 1×/1.5×/2× 缩放，DPI 感知布局 |
| 多显示器检测 | EDID 读取，虚拟桌面跨屏 |
| 窗口跨屏拖拽 | 窗口可以从一个显示器拖到另一个 |

---

### Sprint G8 — 输入法 + 辅助功能 + 护眼模式

**目标**：`ime.hl` / `a11y.hl` / `eyecare.hl` 实现化。

| 工作项 | 说明 |
|---|---|
| IME | 拼音输入法框架（候选词窗口，Up/Down 选词） |
| A11y | 屏幕阅读器 API（role/label/描述），高对比度主题 |
| 护眼 | 色温滑块 4500–6500 K，定时启用，全屏 LUT 后处理 |

---

## 长期目标（Sprint G8 之后）

| 方向 | 目标 |
|---|---|
| **修复 1,871 unresolved relocs 到 0** | 完整符号表 + 运行时库绑定 |
| **自举完整性** | H-L 编译器完全由 H-L 源码编译自身（无 PowerShell 依赖） |
| **WASM 后端** | 将 H-L 编译到 WebAssembly，在浏览器中运行 HicOS shell |
| **ARM64 移植** | 添加 ARM64 codegen 后端，在树莓派/苹果 M 系芯片上启动 |
| **RISC-V 移植** | RISC-V RV64GC 后端，支持 QEMU RISC-V 启动 |
| **分布式 HicOS** | 多节点 Raft 集群 + 分布式文件系统 |
| **TCP/IP 一致性测试** | 通过 RFC 一致性测试套件验证协议正确性 |
| **正式验证** | 核心内存分配器用 Coq/Lean 辅助证明正确性 |

---

## 推荐执行命令

```powershell
# 完整编译流水线（≈115 min）
powershell -ExecutionPolicy Bypass -File .\scripts\hl-compile-pipeline.ps1

# Balance error 诊断（独立快速运行）
powershell -ExecutionPolicy Bypass -File .\scripts\diag-balance.ps1

# 镜像重建（编译后）
powershell -ExecutionPolicy Bypass -File .\scripts\rebuild-image.ps1

# QEMU 启动（GUI 模式）
qemu-system-x86_64 -drive format=raw,file=hicos-hl.img -vga std -display sdl -m 256M

# QEMU 启动（串口只读模式）
qemu-system-x86_64 -drive format=raw,file=hicos-hl.img -serial stdio -display none -m 256M
```

---

## 相关文件

- `PROJECT_STATUS.md` — 当前状态快照（自动随 Sprint 刷新）
- `CHANGELOG.md` — 每 Sprint 详细记录
- `GUI_DESIGN.md` — Fluent Design 设计基线（G1–G8 分层计划）
- `HILBERT_LANG_BNF.md` — H-L 语言语法正式定义
- `ARCHITECTURE.md` — 系统架构概览
