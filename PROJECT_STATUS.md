# HicOS — 项目状态快照

> 截至 **2026-05-20 23:29**（Sprint G1 + Pipeline-Run 之后）。
> 本文件是 **当前真值**，按需要随 Sprint 推进刷新。历史细节见 `CHANGELOG.md`。

---

## 1. 总览

HicOS 是一个用自研 **Hilbert-Lang (H-L)** 语言写的裸机 x86_64 实验性操作系统。零外部依赖（无 C/Rust/JSON/YAML/npm），整条工具链与内核模块全部 H-L 自举；唯一例外是镜像发射器 `scripts/rebuild-image.ps1`（PowerShell 直写机器码）。

| 指标 | 当前值 |
|---|---:|
| 总 `.hl` 源文件 | **539** |
| 内核模块 `bare-kernel/hl/*.hl` | **470** |
| 顶层子系统模块 `HicOS_*.hl` | **28** |
| `scripts/*.ps1` 工具脚本 | **33** |
| 仓库 MD 文件（根） | **6**（含本文件） |
| 最近 Sprint | **G1**（GUI 脚手架）+ **Pipeline-Run** |
| 已完成里程碑 | M1–M6（全部 ✦） |
| Bug-fix Sprints | 1–31（已收尾） |
| Codegen Sprints | 35–38（已落地） |
| GUI Sprints | G1（脚手架完成；G2–G8 计划中） |

---

## 2. 最近一次编译流水线（Phase 1–5）

| 项 | 数值 |
|---|---:|
| Modules compiled | **472 / 472** ✅ |
| Total tokens / AST / IR | 705,588 / 419,590 / 391,722 |
| IR live / dead | 292,591 / 99,131 |
| IR optimizations | 99,846 |
| x86_64 `.text` 字节 | 601,014 |
| Linker 符号数 / relocs resolved / stubs | 6,401 / 24,223 / 227 |
| **Unresolved relocs** | **1,871** ⚠ |
| Functions emitted | 5,598 |
| **Balance errors**（token 级） | **17** ⚠ |
| Parse warnings | 5（已 recovery） |
| `bare-kernel/kernel.bin` | **609,207 B @ 0x120000** |
| 流水线耗时 | ≈115 min |

> 完整结果见 `.tmp/pipe.log`；详细告警文件清单见下文 §4。

---

## 3. 关键产物现状

| 产物 | 路径 | 大小 / 状态 |
|---|---|---:|
| BIOS 启动镜像 | `hicos-hl.img` | 693,760 B |
| UEFI 启动镜像 | `hicos-uefi.img` | 34,603,008 B |
| 数据盘 | `hicos-disk.img` | 存在 |
| Kernel 二进制 | `bare-kernel/kernel.bin` | **609,207 B** @ 0x120000 |
| Kernel 符号表 | `bare-kernel/kernel-symbols.json` | 3 个符号（`serial_puts` / `serial_hex_byte` / `base`） |
| `BOOTX64.EFI` | `BOOTX64.EFI` | 存在（根目录） |
| 流水线日志 | `.tmp/pipe.log` | ≈30 KB（最新一次完整记录） |

---

## 4. 12 个告警文件（balance / parse warning）

| 文件 | balance errors | EOF depth `()` `{}` `[]` | 类别 |
|---|---:|---|---|
| `a11y.hl` | 1 | 0 / -1 / 0 | 字符串内 `}` |
| `app_texteditor.hl` | 2 | 0 / 0 / 0 | 字符串内成对 |
| `consistent_hash.hl` | 1 | 0 / 0 / 0 | 字符串内 `{` |
| `display_topology.hl` | 1 | 0 / -1 / 0 | 字符串内 `}` |
| `ime.hl` | 1 | 0 / -1 / 0 | 字符串内 `}` |
| `neural.hl` | **4** | 0 / 0 / 0 | 含 1 个 `Mismatched ]`，需重点排查 |
| `shell.hl` | 0 | — | 仅 parse warning |
| `shell_dock.hl` | 1 | 0 / -1 / 0 | 字符串内 `}` |
| `shell_form.hl` | 2 | 0 / -2 / 0 | 字符串内 |
| `shell_wallpaper.hl` | 1 | 0 / -1 / 0 | 字符串内 `}` |
| `vdesktop.hl` | 1 | 0 / -1 / 0 | 字符串内 `}` |
| `visual_audit.hl` | 2 | 0 / 0 / 0 | 字符串内 `{` 与 `(` 各 1 |

诊断脚本：`scripts/diag-balance.ps1`（独立运行，不需要重跑 95 分钟流水线）。

---

## 5. 待办与下一步

### 5.1 紧后置（next-up）

- **修 tokenizer 字符串处理**：让字符串字面量内的 `{ } ( ) [ ]` 不进入 token 流 → 17 个 balance errors 全部清零（仅剩 `neural.hl` 的真实 `Mismatched ]` 需要源码修正）。
- **枚举 unresolved relocs**：在 `Link-Pass2` 增加按 target 名分组的统计输出，导出到 `.tmp/unresolved.txt`，逐项决策（绑定真实符号 / 保留 stub / 删调用）。
- **扩 `kernel-symbols.json`**：从手写 kernel 暴露 framebuffer / heap / input 子系统符号，供 GUI 模块（compositor/wm/...）的 builtin trampoline 接通。

### 5.2 GUI 路线（Sprint G2 起）

| Sprint | 目标 |
|---|---|
| **G2** | `gfx_backbuffer` + `compositor` 接通真实 framebuffer；屏幕显示第一帧纯色 |
| **G3** | `font_atlas` + 文本渲染；`shell_topbar` 出文字 |
| **G4** | `widget_*` 控件首批可绘制（按钮 / 输入框） |
| **G5** | `input_pointer` + PS/2 鼠标 → `compositor` 入站事件链路 |
| **G6** | `shell_dock` / `shell_startmenu` 可点击 |
| **G7** | `app_terminal` 真实运行（GUI 内嵌 serial shell） |
| **G8** | 多 desktop / `mission_control` / 动效预算达标 |

详见 `GUI_DESIGN.md`。

### 5.3 长期议程

- POSIX/musl shim 真机互操作验证（M6 已落代码，未跑全套）
- WASM JIT 跨平台 demo
- IP-Protection 中两件 Patent 草稿的英文化与提交流程

---

## 6. 文档地图

| 文档 | 用途 |
|---|---|
| `README.md` | 项目入口、Build/Run、能力面 |
| `ARCHITECTURE.md` | 三层架构、启动链 |
| `HILBERT_LANG_BNF.md` | H-L 语言文法（BNF + Spatial 语义） |
| `GUI_DESIGN.md` | Win11 Fluent GUI 总体设计 + G1–G8 路线 |
| `CHANGELOG.md` | 全 Sprint / 迭代日志 |
| `PROJECT_STATUS.md` | **本文件**：当前真值快照 |
| `.github/copilot-instructions.md` | Copilot 协作约定 |
| `IP-Protection/` | 专利材料（.txt/.pdf/.docx，无 MD） |
