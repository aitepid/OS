# Sprint 35 — Unresolved Relocations 分类诊断

> 生成日期：2026-06-01 ｜ 输入：`.tmp/unresolved-candidates.txt`（静态预扫描）
> 完整 ground truth 待运行流水线后由 `.tmp/unresolved-syms.txt` 给出（已在 `Link-Pass2` 注入 dump 逻辑）

---

## 总览

| 项 | 值 |
|---|---:|
| 已扫描源文件 | 504 |
| 已定义函数 (`fn`) | 6,113 |
| 调用站点 distinct 名 | 6,483 |
| Kernel symbols | 3 |
| Stdlib builtins | 104 |
| **候选未解析（distinct）** | **350** |
| 已知 unresolved 重定位站点（流水线报告） | 1,871 |

candidate 350 ≠ 1,871 —— 后者是**站点数**（同一 target 多次调用计多次）。预扫描从静态 call site 推导，是上界。

---

## 分类（按频率倒序，前 60）

### A 类 · Builtin 别名（高 ROI，stub trampoline 即可修复）

| 调用次数 | 符号 | 应映射到（builtin） |
|---:|---|---|
| 1,034 | `array` | array 字面量构造（已是语法） |
| 300 | `to_int` | `int(x)` |
| 284 | `str_char_code` | `str_to_code(s)` |
| 169 | `parse_int` | `int(x)` |
| 121 | `_starts_with` | `str_starts_with(s, p)` |
| 96 | `array_new` | array 字面量 / `[]` |
| 76 | `str_slice` | `str_sub(s, a, b)` |
| 73 | `substr` | `str_sub(s, a, b)` |
| 29 | `str_index_of` | `str_find(s, n)` |
| 27 | `char_code` | `ord(s)` 或 `str_to_code` |
| 9 | `str_to_bytes` | （新 builtin？或 stdlib） |
| 9 | `str_from_byte` | `str_from_code` |
| 8 | `to_char` | `chr(n)` |
| 4 | `str_byte` | `str_char_at(s, i)` |
| 3 | `strlen` | `str_len(s)` |

**A 类合计 ~2,142 次调用**（约站点占比 50%+）。建议在 stdlib 或 link-stub 中添加这些别名 trampoline：一行映射 = 一类消化。

### B 类 · Kernel 内核符号（需补 `kernel-symbols.json`）

| 调用次数 | 符号 | 类别 |
|---:|---|---|
| 186 | `serial_print` | 串口（与 `serial_puts` 同源，需统一） |
| 9 | `_ke_pci_read` | PCI 配置空间读 |
| 6 | `mem_set32` | 32-bit 填充（VESA 路径） |
| 4 | `wrmsr` | x86 MSR 写 |
| 4 | `random_get` | 随机数源 |

**B 类合计 ~209 次**。需要在 `bare-kernel/kernel.entry` 暴露符号 + 在 `kernel-symbols.json` 注册。

### C 类 · 真前向声明 / 业务函数（需 H-L 实现或确认链接）

| 调用次数 | 符号 | 推测模块 |
|---:|---|---|
| 50 | `_find_space` | 字符串解析工具 |
| 33 | `cstr_from_addr` | C 字符串读取 |
| 7 | `udp_recv` | `udp.hl` |
| 6 | `tcp_recv` | `tcp.hl` |
| 6 | `file_read` | `vfs.hl` |
| 6 | `insert` | 通用容器 |
| 5 | `search` | 通用容器 |
| 4 | `ui_fill_rect` | `gfx.hl` |
| 4 | `font_draw_string` | `font_atlas.hl` |
| 4 | `fib` | 测试 / 例子 |
| 4 | `partition` | 排序 / 分区 |
| 4 | `encode` / `close` | 通用 |
| 3 | `socket_send` / `socket_close` | `socket.hl` |
| 3 | `send` | 通用 |

**C 类合计 ~150 次**。需逐项在对应模块实现并在 manifest 暴露。

### D 类 · 误识候选（regex 把 `if Foo()` 中的 ident 当函数，实际是变量/类名）

| 调用次数 | 符号 | 真相 |
|---:|---|---|
| 43 | `loaded` | `if loaded(...)` 风格的状态变量？ |
| 16 | `initialized` | 同上 |
| 16 | `q` | 单字母变量 |
| 15 | `Set` | 类构造 |
| 14 | `created` | 状态 |
| 13 | `get` `failed` | 通用名 |
| 11 | `F` | 单字母 |
| 10 | `short` `O` `kth` `sectors` | 短名 |
| 8 | `mismatch` `fail` | 状态 |
| 6+ | `est` `bytes` `par` `same` `Find` `LCA` | 名词/缩写 |

**D 类**约占 30+ 个 distinct，大多 ≤ 16 次。无需修复，需在 probe 工具中改进 regex（排除大写首字母 + 已知白名单）。

---

## 修复策略（按 ROI 排序）

### 阶段 1（快速，预计消化 ≥1,500 站点）

1. **A 类别名 trampoline**：在 `Link-GenerateStubs` 或 stdlib 中添加 ~15 条别名 → 已知 builtin 的映射
2. **B 类 kernel 符号补全**：`kernel-symbols.json` 增 5 项 + `kernel.entry` 暴露 `serial_print`/`_ke_pci_read`/`mem_set32`/`wrmsr`/`random_get`

### 阶段 2（中速，预计消化 ~150 站点）

3. **C 类前向声明落实**：逐模块查实，要么补实现，要么删调用；优先级按调用次数

### 阶段 3（工具改进）

4. **probe 工具改进**：D 类误识应排除（首字母大写 → 类构造、单字母 → 变量）；改进后重跑预扫描以缩小白噪声
5. **Pass2 真实 dump**：跑一次完整流水线获取 `.tmp/unresolved-syms.txt`，用真实数据替代静态预扫描

---

## 验收门槛（健壮性大纲 §14.1）

| 状态 | 阶段 | 期望 |
|---|---|---:|
| 当前 | 起点 | 1,871 |
| 阶段 1 完成 | 别名 + kernel 符号 | < 300 |
| 阶段 2 完成 | C 类落实 | < 50 ✅ |
| 终态 | 全部 | 0 |

---

## 工具产出

| 工具 | 路径 | 用途 |
|---|---|---|
| `scripts/probe-unresolved.ps1` | 静态预扫描 | 不跑流水线即得候选清单（350 distinct） |
| `Link-Pass2` 内嵌 dump | `hl-compile-pipeline.ps1` 第 956 行附近 | 运行流水线后产出 `.tmp/unresolved-syms.txt`（真实 ground truth） |
| 候选清单 | `.tmp/unresolved-candidates.txt` | 当前快照（已生成） |
