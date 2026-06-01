# Hilbert-Lang (H-L) 健壮性大纲

> 主题：H-L 语言为达成**生产级健壮性**所需的全部机制与工程纪律
> 版本基线：H-L 1.0（HicOS Sprint 33）｜ 生成日期：2026-06-01
> 关联：`HILBERT_LANG_BNF.md`（语法）、`HILBERT_LANG_OUTLINE.md`（语言概览）

---

## 第 0 章 · 健壮性总框架

H-L 的健壮性沿四条主线推进：

```
        ┌──────────────────────────────────────────┐
        │  L4  形式与验证   Coq/Lean / 模型检测      │
        ├──────────────────────────────────────────┤
        │  L3  运行时纪律   不变式 / 资源 / 容错     │
        ├──────────────────────────────────────────┤
        │  L2  编译期保障   类型 / 借用 / 越界检查   │
        ├──────────────────────────────────────────┤
        │  L1  语法与词法   平衡 / 解析恢复 / 严格   │
        └──────────────────────────────────────────┘
```

每一层失败都必须**对上一层透明**，且**对下一层提供安全网**。

---

## 第一章 · 词法与语法层（L1）

### 1.1 当前缺口

| 缺陷 | 数量 | 优先级 |
|---|---:|---|
| Token balance error（字符串内 `{}` 误识别） | 17 | P1 |
| Parse warnings（已 recovery） | 5 | P2 |
| `Mismatched ]`（`neural.hl` 真实错误） | 1 | P1 |

### 1.2 健壮性目标

| 目标 | 机制 |
|---|---|
| 字符串字面量内括号不污染 token 流 | 改造 lexer 状态机：`InString` 时 `{}()[]` 视为字符 |
| f-string 表达式段独立平衡 | 双层栈：外层串、内层 `{ expr }` 各自计数 |
| 反斜杠转义完整覆盖 `\n \t \r \" \\ \xNN \uNNNN` | 单元测试矩阵 |
| 错误带行/列/上下文 3 行 | `LexError { line, col, near, hint }` |
| 解析恢复后**绝不静默吞错** | 必须打印 warning，且生成 `_PARSE_RECOVERED` AST 标记 |

### 1.3 验收门槛

- `scripts/diag-balance.ps1` → **balance errors = 0**
- `scripts/hl-compile-pipeline.ps1` → **parse warnings ≤ 5**，且全部带文件名+行号
- 单元测试：`test_lexer_strings.hl` 覆盖 30+ 边界字符串

---

## 第二章 · 类型与契约层（L2）

### 2.1 当前类型系统的健壮性短板

H-L 1.0 的类型注解是**文档级**，运行时不强制 → 编译期发现不了类型错配。

### 2.2 渐进强化路径

| 阶段 | 强化 |
|---|---|
| v1.1 | 注解 → 由 linter 检查（`hl-lint.hl`），类型不匹配 = warning |
| v1.2 | 关键 builtin 边界处插运行时 type check（`assert isinstance(x, "int")`） |
| v2.0 | 真正的静态类型推导：HM 风格 + 局部 |
| v2.1 | 泛型：`fn map<T,U>(a: array[T], f: fn(T)->U) -> array[U]` |
| v2.2 | 联合类型 `int | str` 编译期收敛检查（穷尽 match 所有 variant） |

### 2.3 契约式编程（DBC）

```hl
@require(n >= 0)
@ensure(result >= n)
fn factorial(n: int) -> int {
    if n <= 1 { return 1; }
    return n * factorial(n - 1);
}
```

- `@require`：入口前置条件 → 失败 raise `PreconditionError`
- `@ensure`：退出后置条件 → 失败 raise `PostconditionError`
- `@invariant`：循环不变式 → 每次迭代后检查
- 发布编译时可关闭（`--no-contracts`），调试时强制开启

---

## 第三章 · 内存与生命周期（L2/L3）

### 3.1 内存安全保证矩阵

| 风险 | 当前状态 | 目标机制 |
|---|---|---|
| 悬空指针 | 无原生指针，靠引用计数 | 维持引用计数；裸机内核例外路径需审计 |
| Use-after-free | 引用计数兜底 | 编译期借用检查（v2.0） |
| 缓冲区溢出 | 数组带长度，越界 raise | 强制 `IndexError`，禁用 unchecked 索引 |
| 整数溢出 | 当前 wrap | 提供 `add_checked` / `mul_checked`，关键路径必须使用 |
| 未初始化读 | `let x;` 不允许，必须 `let x = ...` | 编译期硬性约束 |
| 资源泄漏 | 手动 `try/finally` | 引入 `using` 块 + `__exit__` |

### 3.2 引用计数边界

裸机内核运行时无 GC。引用计数必须：

1. **增减成对**：每个 `incref` 对应一个 `decref`，由编译器在作用域出口自动插入
2. **环检测**：弱引用（`weak`）打破环；编译器对自指 class 字段警告
3. **释放有序**：先释放孩子，再释放容器（避免悬空）
4. **裸机内核例外**：`HicOS_Kernel.hl` 等模块**禁用堆**，仅栈分配 + 静态池

### 3.3 `using` 资源管理（计划 v1.2）

```hl
using f = open("a.txt") {
    f.write("hello");
}   // 块退出自动调 f.__exit__()，即使 raise 也保证关闭
```

---

## 第四章 · 异常与错误模型（L3）

### 4.1 异常分级

| 级别 | 类型 | 示例 | 处理纪律 |
|---|---|---|---|
| **Recoverable** | `IOError` `ParseError` `Timeout` | 文件不存在 | 必须 catch 或显式 propagate |
| **Logic** | `AssertionError` `PreconditionError` | 调用方违约 | 不应 catch；fail-fast |
| **Fatal** | `OutOfMemory` `StackOverflow` `KernelPanic` | 内核级 | 进入 panic handler，不返回 |

### 4.2 错误传播规范

```hl
// ❌ 反模式：吞异常
try { risky(); } catch e { /* 空 */ }

// ❌ 反模式：catch-all 后继续
try { risky(); } catch e { print(e); }   // 然后什么也不做

// ✅ 模式：要么处理，要么转换，要么传播
try {
    risky();
} catch e : IOError {
    log_error(e);
    return Result.err("io failed: " + e.msg);
} catch e {
    raise;   // 不认识的异常必须传播
}
```

### 4.3 强制纪律

- Linter 检测**空 catch 块** → error
- Linter 检测 **catch-all 不重抛** → warning，需 `// suppressed: <reason>` 注释豁免
- `raise;` 必须在 `catch` 内（编译期检查）
- `finally` 中 `return` 会吞当前异常 → linter 警告

### 4.4 panic 与 abort

裸机内核：`KernelPanic` → `serial_puts` 输出栈帧 → halt。开发期保留 trace；发布期可选 minified panic。

---

## 第五章 · 并发安全（L3）

### 5.1 Sector 模型的健壮性保证

H-L 通过空间分区天然消除多数共享状态：

| 保证 | 机制 |
|---|---|
| **无 false sharing** | 不同 sector 的变量 Hilbert 距离 → 不同 cache line |
| **无数据竞争** | sector 之间内存不交叉 |
| **无锁** | sector 内单线程，sector 间通过 `emit` 消息 |

### 5.2 跨 sector 通信纪律

```hl
// ✅ 通过 emit 广播（不可变值复制）
emit progress 0.5;

// ❌ 反模式：跨 sector 修改共享数组
spawn worker_a();
spawn worker_b();
shared_arr.push(x);   // 编译期警告：shared_arr 跨 sector 写
```

### 5.3 死锁与饿死防御

- 不引入互斥锁 → 设计上无死锁
- `emit` 通道有界（默认容量 1024），满则 drop oldest + warning
- `spawn` 任务带优先级与 deadline；超时 → 自动取消并 raise `TaskTimeout`

### 5.4 中断与抢占

裸机内核中断处理：

- 中断处理函数禁用 `near`、`emit`、动态分配
- 必须 `pragma kernel_interrupt`，linter 强制扫描
- 关中断窗口 ≤ 100 cycles（perf gate）

---

## 第六章 · 不变式与断言（L3）

### 6.1 三类断言

| 类型 | 关键字 | 用途 |
|---|---|---|
| 调试断言 | `assert expr;` | 开发期检查；`--release` 可移除 |
| 安全断言 | `assert! expr;` | 永远开启；失败 panic |
| 静态断言 | `static_assert expr;` | 编译期检查（v2.0） |

### 6.2 关键不变式样例

```hl
fn binary_search(arr: array[int], key: int) -> int {
    let mut lo = 0; let mut hi = arr.len();
    while lo < hi {
        assert! lo <= hi && hi <= arr.len();      // 区间不变式
        let mid = (lo + hi) / 2;
        assert! lo <= mid && mid < hi;            // 中点合法
        if arr[mid] < key { lo = mid + 1; }
        elif arr[mid] > key { hi = mid; }
        else { return mid; }
    }
    return -1;
}
```

### 6.3 不变式覆盖率指标

每个核心数据结构（`linked_list` `btree` `ringbuf` `lru_cache`）必须有：

- 构造后不变式（`invariant_after_init`）
- 操作后不变式（每个 mutator 后检查）
- 析构前不变式

---

## 第七章 · 测试金字塔（L3）

### 7.1 七层测试

| 层 | 工具 | 覆盖 |
|---|---|---|
| 1. Lex/Parse 单测 | `test_lex_*.hl` | 100% 边界 token |
| 2. AST/IR 单测 | `test_ast_*.hl` `test_ir_*.hl` | 每条产生式 |
| 3. 语义单测 | `test_*.hl`（230+） | builtin/算子/作用域 |
| 4. 模块联调 | `test_build_chain.hl` | 自举链路 |
| 5. 内核 smoke | `scripts/qemu-smoke.ps1` | 启动到 `HicOS>` |
| 6. UI/GUI 视觉 | `scripts/qemu-visual-test.ps1` | 像素 diff |
| 7. 压力 | QEMU Round 1–5 | 长时间稳定 |

### 7.2 测试基线（必须随每个 Sprint 更新）

| 指标 | 当前 | 目标 |
|---|---:|---:|
| 单测通过率 | ~95% | 100% |
| Smoke 启动 | ✅ | 必须 ≤ 30s |
| Round 5 压测 | ✅ Sprint 32 | 每月一轮 |
| 覆盖率（行） | 未测量 | ≥ 80%（v1.3 引入） |

### 7.3 模糊测试（fuzzing，计划 v1.3）

- Lexer fuzzer：随机字节流，绝不允许 panic（必须返回 `LexError`）
- Parser fuzzer：随机 token 流，绝不允许进入无限循环
- VM fuzzer：随机字节码，必须在有限步内 halt 或 raise

---

## 第八章 · 静态分析（L2/L3）

### 8.1 `hl-lint.hl` 现状与扩展

| 规则 | 状态 |
|---|---|
| 未使用变量 | ✅ 已检测 |
| 变量遮蔽（shadow） | ✅ Sprint 1–16 已统一 `let mut` |
| 死代码 | ✅ IR 阶段消除 |
| 空 catch | 🟡 计划 v1.2 |
| 整数溢出风险 | 🟡 v1.3 |
| 未捕获异常路径 | 🟡 v1.3 |
| 跨 sector 共享写 | 🟡 v2.0 |

### 8.2 必须开启的告警等级

```
release: warning = error
develop: warning = warning, hint = info
ci:      warning = error, hint = warning
```

### 8.3 `pragma` 编辑纪律

```hl
@pragma kernel_interrupt        // 禁用 near/emit/heap
@pragma no_recursion            // 禁止递归（栈受限路径）
@pragma const_only              // 仅允许常量参数
@pragma must_use                // 返回值必须被消费
```

---

## 第九章 · 资源与配额（L3）

### 9.1 显式上限

| 资源 | 默认上限 | 超出处理 |
|---|---:|---|
| 调用栈深度 | 256 | `StackOverflow` panic |
| 单数组元素 | 1 << 24 | `IndexError` |
| 字符串长度 | 1 << 20 | `SizeError` |
| `emit` 通道容量 | 1024 | 丢最老 + warning |
| 单 sector 任务数 | 64 | `spawn` raise `SectorFull` |
| 编译期 IR 节点 | 1 << 18 | 编译失败，提示拆模块 |

### 9.2 时间预算（perf 健壮性）

| 操作 | 预算 |
|---|---|
| 中断处理 | ≤ 100 cycles |
| Compositor 帧 | ≤ 16 ms（60 FPS） |
| Sched tick | ≤ 50 µs |
| 系统调用 | ≤ 5 µs |

由 `scripts/perf-baseline.ps1` 持续测量，超出 → CI fail。

---

## 第十章 · 自举与编译器健壮性（L1–L3）

### 10.1 自举不变式

> **任何 H-L 1.x 编译器必须能编译 H-L 1.0 源码并产生**字节级一致**的输出。**

- 双自举验证：`compiler_v(N)` 编译 `compiler_v(N+1)` 源码 → 二进制 = `compiler_v(N+1)` 自编译产物
- 流水线指纹：每阶段对其输出做 SHA-256，写入 `.tmp/pipeline-hash.txt`，与基线比较
- 当前差异：1,871 unresolved relocs（Sprint 35 处理）

### 10.2 编译器自身健壮性

- Lexer/Parser/IR/Codegen 每模块独立测试
- 任何 panic 必须带源位置（`file:line:col`）
- Internal compiler error（ICE）必须导出 reproducer 到 `.tmp/ice-<ts>.hl`

### 10.3 镜像构建健壮性

- `rebuild-image.ps1` 强制 `-Encoding UTF8`（已修一次 GB2312 根因）
- 构建产物必须签校验和
- `scripts/release-validate.ps1` 闸门：镜像启动到 shell 才能发布

---

## 第十一章 · 形式方法（L4，远期）

### 11.1 计划证明对象

| 对象 | 工具 | 何时 |
|---|---|---|
| 内存分配器 | Coq/Lean | v3.0 |
| 调度器（FIFO/优先级正确性） | TLA+ | v2.5 |
| Hilbert 编码/解码可逆性 | Lean | v2.0 |
| Sector 互不重叠 | Lean | v2.0 |
| 锁字典（如有引入） | TLA+ | 仅在引入时 |

### 11.2 模型检测

- `mc-spawn-emit.tla`：`spawn` + `emit` 不出现死锁
- `mc-quadrant-near.tla`：`near` 解析永远收敛

---

## 第十二章 · 错误注入与混沌测试（L3）

### 12.1 注入点

| 位置 | 注入 |
|---|---|
| 文件读 | 提前 EOF / 损坏字节 |
| 网络 | 丢包 / 乱序 / 延迟 |
| 内存分配 | 周期性 fail |
| 时钟 | 跳变 / 倒退 |
| 中断 | 风暴 / 抑制 |

### 12.2 混沌脚本（计划）

`scripts/chaos-suite.ps1`：QEMU + monitor，按概率注入故障，运行 1h，要求**不崩溃**或**优雅降级**。

---

## 第十三章 · 可观测性（L3）

健壮的前提是看得见。

### 13.1 三条线

| 线 | 机制 | 用途 |
|---|---|---|
| **日志** | `log_info/warn/error` + 串口 | 事后取证 |
| **指标** | 计数器、直方图、`/proc` 类导出 | 趋势 |
| **追踪** | spawn 链路 ID + 时间戳 | 关键路径 |

### 13.2 强制要求

- 每个 panic 必须带 stack trace + 寄存器 dump
- 每个 `catch` 必须 log（除显式 `// silent: <reason>`）
- 每个 `spawn` 必须有 task name 与 sector 标识
- 关键模块导出健康端点（`heap_health()` `sched_health()` `gfx_health()`）

---

## 第十四章 · 健壮性 KPI 与门禁

### 14.1 KPI 表（每 Sprint 必更新）

| KPI | 当前 | 阶段目标 | 终态目标 |
|---|---:|---:|---:|
| Balance errors | **0** ✅ | 0（Sprint 34 完成） | 0 |
| Unresolved relocs | 1,871（dump 工具已就位） | < 50（Sprint 35） | 0 |
| Parse warnings | 5 | ≤ 5 | 0 |
| 单测通过率 | ~95% | 100% | 100% |
| Smoke 启动时间 | < 30s | < 30s | < 10s |
| 中断处理 cycles | 待测 | ≤ 100 | ≤ 80 |
| Compositor 帧时间 | 待测 | ≤ 16ms | ≤ 10ms |
| 覆盖率 | — | ≥ 80% | ≥ 90% |
| Round 压测 | Round 5 ✅ | 每月一次 | CI 每日 |

### 14.2 闸门（gate）

| 闸门 | 脚本 | 阻断条件 |
|---|---|---|
| Pre-commit | `scripts/diag-balance.ps1` | balance errors > 0 |
| Pre-merge | `scripts/full-gate.ps1` | 任一 KPI 倒退 |
| Pre-release | `scripts/release-validate.ps1` | 镜像无法启动 / 单测 < 100% |
| Pre-tag | 手工 + 双自举验证 | 字节差异 ≠ 0 |

---

## 第十五章 · 路线图（健壮性专题）

### 15.1 短期（Sprint 34–40）

1. **Sprint 34**：tokenizer 字符串括号修复 → balance errors = 0
2. **Sprint 35**：unresolved relocs 枚举 + 分类 + 收敛
3. **Sprint 36**：linter 扩展（空 catch / 整数溢出 / pragma 检查）
4. **Sprint 37**：契约 `@require`/`@ensure` 落地
5. **Sprint 38**：`using` 资源管理块
6. **Sprint 39**：模糊测试三件套（lex/parse/vm fuzzer）
7. **Sprint 40**：覆盖率工具 + KPI 仪表板

### 15.2 中期（v2.0）

- 静态类型推导 + 借用检查
- 泛型 + 模式匹配
- `static_assert` + 编译期常量求值
- 双自举字节级一致

### 15.3 远期（v3.0）

- WASM/ARM64/RISC-V 后端 + 跨架构差分测试
- 核心子集 Coq/Lean 证明
- 完全自举（无 PowerShell）

---

## 第十六章 · 工程纪律手册（速查）

### 16.1 代码评审 checklist

- [ ] 是否有空 catch？
- [ ] 是否每个 raise 有对应文档？
- [ ] 是否有未初始化的 `let mut`？
- [ ] 是否有跨 sector 写共享数据？
- [ ] 是否有循环不变式（关键算法）？
- [ ] 是否有资源泄漏路径（无 finally / using）？
- [ ] 是否有整数溢出风险（未用 `_checked`）？
- [ ] 单测是否覆盖三类输入：正常 / 边界 / 错误？
- [ ] 注释是否说明 *why*（不是 *what*）？

### 16.2 紧急回滚流程

1. `git revert <sha>`（创建反向提交，不 reset）
2. 运行 `scripts/diag-balance.ps1` + smoke
3. 通过则推；不通过则 hold + 通告

### 16.3 故障复盘要素

每次重大故障必须产出 `incidents/INC-<id>.md`，含：

- 时间线
- 触发条件
- 根因（必须到根因，不止症状）
- 修复
- 防止再发的机制（不是"以后注意"）

---

## 附录 · 健壮性反模式黑名单

| # | 反模式 | 后果 | 替代 |
|---|---|---|---|
| 1 | `try { ... } catch e { }` | 静默吞错 | 至少 log；最好转换为 Result |
| 2 | `let mut x = 0; ... if rare { x = compute(); }` | 未初始化语义 | 直接初始化为合理默认 |
| 3 | `arr[i]` 不检查 `i` | 越界 panic | `if i < arr.len() { ... }` |
| 4 | `a + b` 已知可能溢出 | wrap 错误 | `add_checked(a, b)` |
| 5 | `near x` 名字含糊 | 解析到错的同名 | 用具名 `quadrant.x` |
| 6 | `spawn` 无 deadline | 任务挂死 | 永远带超时 |
| 7 | `assert` 用于业务校验 | release 被剥光 | 用 `assert!` 或 `raise` |
| 8 | `finally { return ... }` | 吞当前异常 | 在 finally 内仅做清理 |
| 9 | "以后再加测试" | 永远不会加 | 与功能 PR 同包 |
| 10 | "暂时静默 warning" | 永远不会修 | warning = error 到底 |

---

> *本大纲是 H-L 健壮性的纲领。任何降级都需在 PR 描述里写明 *为什么必须降级*、*降级期限*、*恢复条件* 三项，并由维护者签批。*
