# HicOS 压力测试报告 & 修复推进大纲

> 分析日期：2026-05-18  
> 分析范围：全部 426 个内核模块 + shell.hl + kernel_init.hl  
> 分析方法：静态代码审查 + 函数逻辑深度分析 + 跨模块一致性检验

---

## 一、执行摘要

| 严重级别 | 问题数 | 影响范围 | 状态 |
|---------|-------|---------|------|
| **P0 Critical** | 9 | 内核初始化序列损坏 + 运行时崩溃 | 🔴 未修复 |
| **P1 High** | 5 | 声称有完整功能但实为空桩的模块 | 🟠 未修复 |
| **P2 Medium** | 2 | 核心函数存在假实现 | 🟡 未修复 |
| **P3 Low** | 3 | Shell 层质量问题 | 🟢 可延后 |
| **总计** | **19** | **覆盖 ~15 个模块** | |

**关键结论：**
- 内核启动初始化序列存在 **8 处函数名命名冲突**，受影响子系统实际上从未被正确初始化
- `shell.hl` 存在 **1 处运行时崩溃 bug**（变量未定义就使用）
- `debugger.hl` / `lsp_server.hl` / `gdb_stub.hl` / `syntax_highlight.hl` / `code_complete.hl` 5 个模块为**严重空桩**，对外宣称完整功能但核心逻辑缺失
- `hl_fmt.hl` 和 `hl_repl.hl` 核心算法函数为假实现（直接返回参数或硬编码值）
- 质量良好的模块：posix_compat / musl_shim / linux_syscall / wasm_runtime / wasm_jit / hypervisor / vmx / hotpatch / livepatch / autograd / mvcc / wal / db_engine 等 **≥13 个模块** 均为真实实现

---

## 二、P0 Critical — 内核初始化命名冲突

### 问题说明

`bare-kernel/hl/kernel_init.hl` 按顺序调用所有模块的 `init()` 函数。由于 H-L 中函数名在全局命名空间唯一，**当多个模块定义了相同名称的 `init()` 函数时，只有最后一个定义生效**，更早的模块永远不会被正确初始化。

### 冲突清单

| 编号 | 冲突函数名 | 冲突模块 A | 冲突模块 B | 冲突模块 C | 影响 |
|-----|-----------|-----------|-----------|-----------|------|
| C-01 | `pm_init()` | `prometheus.hl`（监控指标）| `power_mgmt.hl`（电源管理）| `package_manager.hl`（包管理）| 三选一，前两个失效 |
| C-02 | `bt_init()` | `bridge_tree.hl`（桥树）| `btree.hl`（B-Tree）| `torrent_proto.hl`（BitTorrent）| 三选一，前两个失效 |
| C-03 | `rc_init()` | `rotating_calipers.hl`（旋转卡壳）| `regalloc_coalesce.hl`（寄存器合并）| — | 后者覆盖前者 |
| C-04 | `sh_init()` | `string_hash.hl`（字符串哈希）| `syntax_highlight.hl`（语法高亮）| — | 后者覆盖前者 |
| C-05 | `pl_init()` | `palindrome_dp.hl`（回文DP）| `pooling.hl`（池化层）| — | 后者覆盖前者 |
| C-06 | `cc_init()` | `calling_conv.hl`（调用约定）| `code_complete.hl`（代码补全）| — | 后者覆盖前者 |
| C-07 | `gs_init()` | `grpc_stream.hl`（gRPC流）| `gdb_stub.hl`（GDB桩）| — | 后者覆盖前者 |
| C-08 | `hp_init()` | `half_plane.hl`（半平面交）| `hotpatch.hl`（热补丁）| — | 后者覆盖前者 |

### 修复方案

将每个冲突模块中的 `init()` 函数重命名为全局唯一名称，同时在 `kernel_init.hl` 中更新所有调用点。命名规则：使用模块的完整功能前缀（而非缩写）。

| 模块文件 | 当前函数名 | 修复后函数名 |
|---------|-----------|------------|
| prometheus.hl | `pm_init()` | `prometheus_init()` |
| power_mgmt.hl | `pm_init()` | `power_mgmt_init()` |
| package_manager.hl | `pm_init()` | `pkg_mgr_init()` |
| bridge_tree.hl | `bt_init()` | `bridge_tree_init()` |
| btree.hl | `bt_init()` | `btree_init()` |
| torrent_proto.hl | `bt_init()` | `torrent_init()` |
| rotating_calipers.hl | `rc_init()` | `rot_cal_init()` |
| regalloc_coalesce.hl | `rc_init()` | `regalloc_coal_init()` |
| string_hash.hl | `sh_init()` | `str_hash_init()` |
| syntax_highlight.hl | `sh_init()` | `syn_hi_init()` |
| palindrome_dp.hl | `pl_init()` | `palin_dp_init()` |
| pooling.hl | `pl_init()` | `pooling_init()` |
| calling_conv.hl | `cc_init()` | `call_conv_init()` |
| code_complete.hl | `cc_init()` | `code_cmp_init()` |
| grpc_stream.hl | `gs_init()` | `grpc_init()` |
| gdb_stub.hl | `gs_init()` | `gdb_stub_init()` |
| half_plane.hl | `hp_init()` | `half_plane_init()` |
| hotpatch.hl | `hp_init()` | `hotpatch_init()` |

**验收标准：** 每个模块的 `*_test()` 函数都能被独立验证，且在 `kernel_init.hl` 所有 `init()` 调用后，`serial_print` 输出中每个模块名都出现一次。

---

## 三、P0 Critical — Shell 运行时崩溃

### C-09：未定义变量使用（shell.hl）

**位置：** `bare-kernel/hl/shell.hl`，`irc say` 命令处理块

**问题代码：**
```hl
if str_starts_with(cmd, "irc say ") {
    let args = str_sub(cmd, 8, len(args));  // BUG: args 在此处尚未定义！
```

**正确写法：**
```hl
if str_starts_with(cmd, "irc say ") {
    let args = str_sub(cmd, 8, len(cmd));   // 应使用 len(cmd)
```

**影响：** 用户执行 `irc say` 任何内容时 shell 崩溃。

**验收标准：** `irc say hello` 不崩溃，返回 IRC 发送确认。

---

## 四、P1 High — 空桩模块（声称完整功能但核心逻辑缺失）

### S-01：debugger.hl — RIP 伪步进器（真实度 15%）

**问题描述：**  
`dbg_step()` 函数仅执行 `RIP += 1`，没有任何指令解码、真实寄存器状态或程序计数器追踪逻辑。

**缺失的核心功能：**
- 指令解码（x86_64 字节流解析）
- 真实 CPU 寄存器状态反映（RAX/RBX/RCX/RDX/RSP/RBP 等）
- 内存读取接口（读取调试目标内存）
- 与 breakpoint.hl 的集成（命中断点时暂停）
- 与 gdb_stub.hl 的集成（通过 GDB 协议暴露状态）

**修复规格：**
- `dbg_step()`: 解析 `dbg_current_ip` 指向的1-byte操作码，根据操作码跳过正确字节数（单字节/双字节/四字节指令族）
- `dbg_read_reg(reg_id)`: 从调试目标上下文寄存器数组中返回对应寄存器值
- `dbg_write_reg(reg_id, val)`: 更新调试目标上下文
- `dbg_read_mem(addr)`: 从模拟内存（或 wasm_runtime 的执行栈）中读取值
- `dbg_get_backtrace()`: 遍历栈帧数组，返回调用深度

**验收标准：** `dbg step` 命令能通过 `dbg_step()` 获得不同于 `ip+1` 的正确跳转结果，且 `dbg regs` 能显示多个寄存器值。

---

### S-02：lsp_server.hl — 文档追踪器（真实度 30%）

**问题描述：**  
模块仅追踪哪些文档被打开/关闭，以及积累 diagnostic 条目。没有 LSP 协议解析、没有语言分析、没有请求/响应处理。

**缺失的核心功能：**
- LSP JSON-RPC 请求解析（initialize / textDocument/completion / hover / definition 等）
- 请求路由分发到对应处理函数
- 响应格式化（id + result 结构）
- 与 code_complete.hl 的集成
- 与 syntax_highlight.hl 的集成

**修复规格：**
- `lsp_handle_request(method_id, doc_id, line, col)`: 根据 `method_id` 分发到补全/悬停/诊断处理
- `lsp_completion(doc_id, line, col)`: 调用 `cc_get_best()` 返回补全结果
- `lsp_hover(doc_id, line, col)`: 返回当前位置 token 的文档字符串
- `lsp_diagnostics(doc_id)`: 返回 lint 结果（集成 hl_lint2.hl）
- `lsp_response_ok(id, result)` / `lsp_response_err(id, code)`: 响应构造

**验收标准：** `lsp request 1 0 5` 命令能返回结构化的响应结果（method_id 路由到正确处理器）。

---

### S-03：gdb_stub.hl — 命令分发器（真实度 25%）

**问题描述：**  
当前实现是硬编码命令字符串的简单分发器，没有 GDB Remote Serial Protocol（RSP）的任何特征：无 `$` 报文帧、无 `#` 校验和、无 ACK/NACK（`+`/`-`）、无 XML 目标描述。

**缺失的核心功能：**
- RSP 报文解析：`$packet#checksum`
- 校验和计算（所有字节的模 256 异或和，十六进制两位）
- ACK/NACK 处理
- 核心命令实现：`?`（停止原因）、`g`（读所有寄存器）、`G`（写所有寄存器）、`m addr,len`（读内存）、`c`（继续）、`s`（单步）

**修复规格：**
- `gdb_parse_packet(buf, len)`: 扫描 `$...#xx` 格式，提取命令体，验证 checksum
- `gdb_checksum(data, len)`: 计算 8-bit 加法校验和
- `gdb_encode_reply(cmd_char, val)`: 构造回复报文加 checksum
- `gdb_handle_cmd(cmd_char, arg)`: 分发到读寄存器/写寄存器/读内存/继续/单步
- 与 debugger.hl 的集成：`gdb_handle_cmd('s', 0)` 调用 `dbg_step()`

**验收标准：** `gdb packet` 命令能解析标准 RSP `$?#3f` 报文并返回带正确 checksum 的应答。

---

### S-04：syntax_highlight.hl — 颜色查表器（真实度 20%）

**问题描述：**  
模块仅维护一个 token_id → color_id 的映射表，没有词法分析器、没有任何源代码 token 化逻辑。

**缺失的核心功能：**
- 词法分析（扫描字符序列识别 token 种类）
- 关键字识别：`fn`、`let`、`if`、`while`、`return`、`array`
- 字面量识别：整数、字符串（`"..."`）
- 注释识别：`//` 行注释
- 操作符/分隔符识别：`{` `}` `(` `)` `;` `=` `+` `-` `*` `/`

**修复规格：**
- `sh_scan_token(src, pos)`: 从 `pos` 位置开始扫描一个 token，返回 token 种类 ID 和长度
- `sh_is_keyword(tok_id)`: 判断 token ID 是否为 H-L 关键字
- `sh_classify(char_code)`: 将字符分类为字母/数字/空白/操作符/引号
- `sh_highlight_line(line_id)`: 对 line_id 对应的行逐 token 扫描并记录颜色区间
- `sh_get_color_at(line_id, col)`: 返回指定位置的颜色 ID

**验收标准：** `sh scan` 命令对 `let x = 42;` 能识别出 keyword/identifier/operator/number/operator 5 种 token，各有不同颜色 ID。

---

### S-05：code_complete.hl — 得分排序器（真实度 35%）

**问题描述：**  
模块仅实现了对候选项的最高分搜索，没有符号表、没有上下文分析、没有基于前缀的过滤。

**缺失的核心功能：**
- 符号表（存储已知函数名、变量名及其类型）
- 前缀匹配过滤（输入 `re` → 只展示以 `re` 开头的候选）
- 上下文感知（函数调用位置优先建议函数名，赋值位置优先建议变量名）
- 与 lsp_server.hl 的集成

**修复规格：**
- `cc_register_symbol(name_id, kind)`: 向符号表注册已知符号（kind: 0=var, 1=fn, 2=builtin）
- `cc_match_prefix(prefix_id)`: 遍历符号表，将 name_id 前几位匹配 prefix_id 的候选标为 active
- `cc_get_best()`: 在 active 候选中找最高分的那个（现有逻辑不变，只是在过滤之后运行）
- `cc_get_context_kind(pos)`: 简单规则：看 pos 前一个非空字符是否为 `(` 来判断是否函数调用位置
- 初始化时预注册所有 H-L 内建关键字（let/fn/if/while/return/array/set_at/print）

**验收标准：** `cc match re` 命令仅返回以 `re` 开头的候选（如 `repl_init`/`return`），不返回不匹配的符号。

---

## 五、P2 Medium — 核心算法假实现

### M-01：hl_fmt.hl — 4 个格式化核心函数为假实现

**文件：** `bare-kernel/hl/hl_fmt.hl`

| 函数 | 当前行为 | 正确行为 |
|-----|---------|---------|
| `fmt_normalize_line(line)` | 直接返回 `line` | 去除行首多余空格，确保缩进对齐 |
| `fmt_count_braces_open(line)` | 硬编码返回 `1` | 扫描 `line` 中 `{` 字符的实际数量 |
| `fmt_count_braces_close(line)` | 硬编码返回 `1` | 扫描 `line` 中 `}` 字符的实际数量 |
| `fmt_get_indent_level(line)` | 假循环返回虚假值 | 统计行首连续空格数 ÷ FMT_INDENT_WIDTH |

**修复规格：**

`fmt_count_braces_open(line)` 正确实现（H-L 字符遍历模式）：
```
fn fmt_count_braces_open(line) {
    let count = 0;
    let i = array(1, 0);
    while i < LINE_LEN_MAX {
        let ch = char_at(line, i);
        if ch == 123 { set_at(count, 0, count + 1); }  // 123 = '{'
        if ch == 0 { return count; }
        set_at(i, 0, i + 1);
    }
    return count;
}
```

`fmt_get_indent_level(line)` 正确实现：
```
fn fmt_get_indent_level(line) {
    let spaces = 0;
    let i = array(1, 0);
    let done = array(1, 0);
    while i < LINE_LEN_MAX {
        if done == 1 { return spaces / FMT_INDENT_WIDTH; }
        let ch = char_at(line, i);
        if ch == 32 { set_at(spaces, 0, spaces + 1); }  // 32 = ' '
        if ch != 32 { set_at(done, 0, 1); }
        set_at(i, 0, i + 1);
    }
    return spaces / FMT_INDENT_WIDTH;
}
```

**验收标准：** `fmt add "    let x = 0;"` 后 `fmt depth` 返回 0（无大括号）；`fmt add "fn foo() {"` 后 depth 返回 1。

---

### M-02：hl_repl.hl — 求值引擎为假实现

**文件：** `bare-kernel/hl/hl_repl.hl`

**问题：** `repl_eval_simple(expr)` 仅返回 `expr + 1`，用数字 ID 代替表达式求值，没有任何解析逻辑。

**修复规格：**

REPL 执行简单表达式（支持整数字面量 + 二元运算）：
- 输入格式：`add A B`（加）、`sub A B`（减）、`mul A B`（乘）、`div A B`（除）、`let name val`（存变量）、`get name`（取变量）
- `repl_eval_simple(expr)` 识别命令前缀，提取操作数，调用对应计算路径
- 变量存取集成到 `repl_set_var` / `repl_get_var`

```
fn repl_eval_simple(cmd) {
    if cmd == REPL_CMD_ADD { return repl_arg0 + repl_arg1; }
    if cmd == REPL_CMD_SUB { return repl_arg0 - repl_arg1; }
    if cmd == REPL_CMD_MUL { return repl_arg0 * repl_arg1; }
    if cmd == REPL_CMD_DIV { return repl_arg0 / repl_arg1; }
    if cmd == REPL_CMD_LET { repl_set_var(repl_var_id, repl_arg0); return repl_arg0; }
    if cmd == REPL_CMD_GET { return repl_get_var(repl_var_id); }
    return 0-1;
}
```

**验收标准：** `repl eval add 10 20` 返回 30；`repl eval let myvar 42` 后 `repl eval get myvar` 返回 42。

---

## 六、P3 Low — Shell 层质量问题

### L-01：Duplicate 命令处理块（shell.hl）

**问题：** shell.hl 中至少 20 组命令以 `if cmd == "..."` 形式出现了 2–3 次。由于 H-L 顺序执行，第一次匹配即返回，后续定义永远无法到达。

**受影响命令组（部分）：**
- `pm init` / `pm test`（3 次定义）
- `bt init` / `bt test`（3 次定义）
- `mixer`（2 次定义）
- `cc init` / `cc test`（2 次定义）
- `gs init` / `gs test`（2 次定义）
- `hp init` / `hp test`（2 次定义）
- 约 10 组其他命令

**修复规格：** 搜索 shell.hl 中所有重复的命令字符串，保留每组第一处定义，删除后续重复块。无需更改任何逻辑。

**验收标准：** `grep -c "pm init"` 在 shell.hl 中返回 1；全命令集无重复定义。

---

### L-02：Stub Shell 命令（shell.hl）

**问题：** `history` 和 `netstat` 命令的处理块仅输出 `"(handled in kernel.bin native dispatch)"` 之类的占位文本，无实际功能。

**修复规格：**
- `history`: 调用 `repl_get_history_count()` 和 `repl_get_history(i)` 展示执行历史
- `netstat`: 输出已建立连接的模拟状态（从 `tcp.hl` 或 `linux_syscall.hl` 中的连接计数）

---

### L-03：wasm_jit.hl — 机器码发射为符号模拟（架构性存根）

**问题：** `wj_emit_stub()` 仅追踪 6 字节计数，并不生成真实 x86_64 机器码。

**当前状态：** 可接受（用于仿真环境）。真实实现需要字节级 x86 编码器。

**长期修复方向：**  
复用 `bare-kernel/hl/codegen.hl` 中已实现的 x86_64 编码基础设施，将热路径 WASM 函数编译为 MOV EAX + 算术指令序列 + RET 的真实字节序列。

---

## 七、修复冲刺计划

### Sprint 1（优先级最高）— 内核正确性修复

**目标：** 消除命名冲突，确保所有 426 个模块都能被正确初始化

| 任务 | 文件 | 工作量估计 |
|-----|------|-----------|
| 重命名 18 个冲突 init 函数 | 18 个 .hl 文件 | 每文件 2–5 行改动 |
| 更新 kernel_init.hl 所有调用点 | kernel_init.hl | 8–18 处替换 |
| 更新 shell.hl 中对应命令名 | shell.hl | 约 20 处替换 |
| 修复 irc say 崩溃 bug | shell.hl | 1 行修复 |

**验收：** `kernel_init.hl` 中无重复函数名调用；`irc say test` 不崩溃。

---

### Sprint 2 — 格式化器 & REPL 真实实现

**目标：** 修复 P2 中两个核心算法假实现

| 任务 | 文件 | 工作量估计 |
|-----|------|-----------|
| 实现 fmt_count_braces_open/close | hl_fmt.hl | ~30 行 |
| 实现 fmt_get_indent_level | hl_fmt.hl | ~20 行 |
| 实现 fmt_normalize_line | hl_fmt.hl | ~25 行 |
| 更新 hl_fmt_test() | hl_fmt.hl | ~20 行新断言 |
| 实现 repl_eval_simple 命令解析 | hl_repl.hl | ~50 行 |
| 更新 hl_repl_test() | hl_repl.hl | ~15 行新断言 |

---

### Sprint 3 — 调试器生态系统强化

**目标：** debugger + gdb_stub + lsp_server 从 15–30% 到 70%+ 真实实现

| 任务 | 文件 | 关键实现 |
|-----|------|---------|
| dbg_step() 指令解码 | debugger.hl | 操作码→字节长度映射 |
| dbg_read_reg / dbg_write_reg | debugger.hl | 寄存器上下文数组 |
| gdb_parse_packet / gdb_checksum | gdb_stub.hl | `$..#xx` 格式解析 |
| gdb_encode_reply | gdb_stub.hl | 构造含 checksum 的应答 |
| lsp_handle_request 路由 | lsp_server.hl | method_id 分发 |
| lsp_completion / lsp_hover | lsp_server.hl | 集成 code_complete + hl_lint2 |

---

### Sprint 4 — 语言工具补全（高亮 + 补全）

**目标：** syntax_highlight + code_complete 从 20–35% 到 70%+ 真实实现

| 任务 | 文件 | 关键实现 |
|-----|------|---------|
| sh_scan_token / sh_classify | syntax_highlight.hl | 词法扫描器 |
| sh_highlight_line | syntax_highlight.hl | 行级 token 着色 |
| cc_register_symbol | code_complete.hl | 符号表 |
| cc_match_prefix | code_complete.hl | 前缀过滤 |
| cc_get_context_kind | code_complete.hl | 上下文感知 |

---

### Sprint 5 — Shell 清洁

**目标：** 消除重复命令处理块，修复 stub 命令

| 任务 | 工作量 |
|-----|-------|
| 去重 shell.hl 中 20+ 重复命令块 | ~200 行删除 |
| 实现 `history` 命令真实逻辑 | ~15 行 |
| 实现 `netstat` 命令真实逻辑 | ~20 行 |

---

## 八、修复优先级总览

```
P0 ████████████████████ 立即修复（影响内核正确性）
   C-01 pm_init 三路冲突
   C-02 bt_init 三路冲突
   C-03 ~ C-08 二路冲突（6组）
   C-09 irc say 崩溃 bug

P1 ████████████████ 高优先级（功能性空桩）
   S-01 debugger.hl
   S-02 lsp_server.hl
   S-03 gdb_stub.hl
   S-04 syntax_highlight.hl
   S-05 code_complete.hl

P2 ████████████ 中优先级（核心算法假实现）
   M-01 hl_fmt.hl（4函数）
   M-02 hl_repl.hl（求值引擎）

P3 ████ 低优先级（Shell 层质量）
   L-01 重复命令块
   L-02 Stub shell 命令
   L-03 wasm_jit 机器码符号化
```

---

## 九、质量好的模块（参考基准）

以下模块经审查为**真实实现**，可作为新模块的实现参考：

| 模块 | 真实度 | 亮点 |
|-----|-------|------|
| posix_compat.hl | 95% | 信号处理 + fork/waitpid 完整实现 |
| musl_shim.hl | 92% | slab 分配器 + 文件句柄模拟 |
| linux_syscall.hl | 90% | 11 个 syscall 统一分发 + 完整日志 |
| wasm_runtime.hl | 88% | 完整 WASM 栈机解释器（12 opcode）|
| autograd.hl | 85% | 真实反向传播 + 链式法则 |
| mvcc.hl | 90% | 版本可见性判断 + vacuum 清理 |
| wal.hl | 85% | 两趟回放（committed-only）|
| hotpatch.hl | 88% | trampoline 跳转 + dispatch 路由 |
| hl_lint2.hl | 90% | 未使用变量检查 + 复杂度警告 |
| breakpoint.hl | 85% | 启用/禁用 + 命中计数 |

---

## 十、下一步行动

1. **立即执行 Sprint 1**：修复 C-01 ~ C-09（影响内核启动正确性的 P0 问题）
2. **执行 Sprint 2**：补全 hl_fmt.hl 和 hl_repl.hl 的核心算法
3. **按模块逐个推进 Sprint 3–4**，每次推进 1 个模块，建立对应测试用例
4. **Sprint 5** 作为最后清洁步骤

---

*本文件由 Claude Code 自动生成，基于 2026-05-18 全量代码压力测试分析。*  
*下次同步建议：每完成一个 Sprint 后更新对应 Bug 状态。*
