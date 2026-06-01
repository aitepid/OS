# Hilbert-Lang (H-L) 语言完善大纲

> 版本基线：H-L 1.0（HicOS Project Constellation）
> 生成日期：2026-06-01
> 关联文档：`HILBERT_LANG_BNF.md`（形式文法）、`stdlib.hl`（标准库）、`HicOS_HilbertLang.hl`（编译器与运行时）

---

## 第一章 · 语言定位

Hilbert-Lang（简称 **H-L**）是为 HicOS 项目自研的**空间语义优先**通用编程语言。其核心区别于传统语言之处：**程序的所有实体（变量、函数、字节码指令）都被分配在一条 Hilbert 曲线上的离散单元格中**，而非线性地址。这一设计同时影响了语言的语义、内存模型、并发模型与编译器实现。

### 1.1 设计目标

1. **空间语义为根**：用 Hilbert 曲线代替线性内存，序列邻居 = 内存邻居 = 缓存邻居
2. **零外部依赖**：无 C/Rust/JSON/YAML/npm；编译器、内核、Shell、GUI 均由 H-L 自己写自己
3. **裸机可运行**：no-std，无堆即可运行；可直接编译到 x86_64 启动盘
4. **Python 级表达力**：保留装饰器、列表推导、f-string、生成器、多重赋值等高层特性
5. **并发免锁**：通过空间分区（sector）天然消除 cache line 冲突

### 1.2 一句话定义

> **H-L = Python 表达力 + Rust 系统级控制 + Hilbert 空间语义 + 自举工具链。**

---

## 第二章 · 五大设计支柱

| 支柱 | 含义 | 体现于 |
|---|---|---|
| 1. 非线性指令布局 | 指令存于 Hilbert 单元格，不是数组 | 字节码 `CodeCell { addr, op }` |
| 2. O(1) 位交错地址 | 任何寻址通过位交错变换完成 | `hilbert_encode/decode` 内置 |
| 3. `near` 替代全局变量 | 用空间邻近代替全局可见性 | `near gravity` 解析最近同名 |
| 4. 分形作用域 | 作用域是父曲线的分形象限 | `quadrant physics { ... }` |
| 5. no-std 兼容 | 裸机可运行 | 整个 HicOS 内核 |

---

## 第三章 · 语法速览

### 3.1 程序结构

```
<program> ::= { <statement> }
<statement> ::= let | assign | fn | class | quadrant
              | if | while | for | return | yield
              | raise | break | continue | try
              | import | assert | del | pass
              | warp | emit | spawn | expr_stmt
```

### 3.2 七大类语句

| 类别 | 关键字 | 例子 |
|---|---|---|
| **绑定** | `let`, `mut` | `let mut x = 0;` |
| **流程控制** | `if/elif/else`, `while`, `for ... in`, `break`, `continue` | `for i in range(10) { ... }` |
| **函数/类** | `fn`, `class`, `self`, `super`, `@decorator` | `@cache fn fib(n) { ... }` |
| **作用域** | `quadrant` | `quadrant physics { let g = 9; }` |
| **异常** | `try/catch/finally`, `raise` | `try { ... } catch e : IOError { ... }` |
| **模块** | `import ... as ...` | `import "stdlib" as std;` |
| **空间原语** | `near`, `warp`, `emit`, `spawn`, `fold` | `near config`, `spawn worker()` |

### 3.3 表达式优先级（从低到高）

```
ternary  →  ||  →  &&  →  |  →  ^  →  &
        →  ==/!=/<  →  <</>>  →  +/-  →  *///%
        →  **  →  unary (-, !, ~, near, fold)  →  postfix
```

### 3.4 字面量与数据结构

```hl
let i = 42;                   // int (i64)
let f = 3.14;                 // float (f64)
let s = "hello";              // str (interned)
let fs = f"x = {x + 1}";      // f-string 插值
let b = true;                 // bool
let n = nil;                  // unit
let a = [1, "two", [3, 4]];   // 异构数组
let d = {"k1": 1, "k2": 2};   // 字典
let l = fn (x, y) x + y;      // lambda
let c = [x*x for x in range(10) if x % 2 == 0];  // list comprehension
```

---

## 第四章 · 类型系统

### 4.1 内建类型

| 类型 | 描述 | 字面量 |
|---|---|---|
| `int` | 64-bit 有符号整数 | `42`, `-7` |
| `float` | IEEE 754 双精度 | `3.14`, `1.0` |
| `str` | interned u16 索引串 | `"hello"`, `f"{x}"` |
| `bool` | 布尔 | `true`, `false` |
| `array` | 动态异构数组 | `[1, "a"]` |
| `dict` | 键值映射 | `{"k": v}` |
| `fn` | 一等函数/闭包 | `fn (x) x + 1` |
| `class` | 实例（带 `__class__`） | `Foo()` |
| `generator` | 含 `yield` 的惰性迭代器 | — |
| `nil` | 空/单元 | `nil` |

### 4.2 类型注解（可选）

```hl
let x: int = 42;
fn add(a: int, b: int) -> int { return a + b; }
let m: dict[str, int] = {"a": 1};
let cb: fn(int) -> str = fn (n) to_string(n);
let u: int | str = 42;        // 联合类型
```

> 类型注解仅作文档与 IDE 提示，运行时不强制（与 Python typing 类似）。

### 4.3 解构绑定

```hl
let [a, b, c] = [1, 2, 3];          // 数组解构
let (x, y) = pair;                  // 元组式
let [head, [l, r]] = tree;          // 嵌套
let [_, second, _] = arr;           // 通配丢弃
```

---

## 第五章 · 空间语义（H-L 独有）

### 5.1 SpatialAddr 编址公式

```
SpatialAddr = interleave3(hx, hy, depth)
其中：
  (hx, hy) = d2xy(ORDER, linear_alloc_seq)
  depth    = 当前作用域嵌套层
```

含义：**第 N 个声明的变量被映射到 Hilbert 曲线的第 N 个单元格**。深一层作用域 → Z 平面 +1。

### 5.2 `quadrant` 分形作用域

```hl
quadrant physics {
    let gravity = 9;     // addr(0,0,1)
    let mass    = 42;    // addr(1,0,1)
}
quadrant render {
    let g = near gravity;   // 解析到 physics.gravity（空间最近同名）
    print(g);
}
```

`quadrant` 同时承担**命名空间**与**空间分区**双重身份。

### 5.3 `near` 邻近绑定

`near x` 在所有可见 `x` 中选择 `hilbert_distance(self, x.addr)` 最小者。它是 H-L 里**取代全局变量的标准手段**。

### 5.4 `fold` 沿曲线归约

```hl
let sum = fold arr from 0 with acc, e -> acc + e;
```

迭代顺序严格按 Hilbert 曲线序——**保证 cache line 顺序访问**。

### 5.5 `warp` / `emit` / `spawn`

| 原语 | 语义 | 用例 |
|---|---|---|
| `warp <addr>;` | 跳转到任意 Hilbert 地址（非局部 goto） | 状态机切换 |
| `emit channel value;` | 向半径内全部 cell 广播 | 事件总线 |
| `spawn fn(args);` | 在独立 sector 启动并发任务 | 任务并行 |

---

## 第六章 · 类与对象

### 6.1 类定义

```hl
class Vector : Shape {           // 单继承
    let dim = 3;                  // 类变量

    fn __init__(self, x, y, z) {
        self.x = x; self.y = y; self.z = z;
    }
    fn __str__(self) { return f"({self.x},{self.y},{self.z})"; }
    fn __add__(self, other) { return Vector(self.x+other.x, ...); }
    fn __len__(self)        { return self.dim; }
    fn __getitem__(self, i) { ... }
    fn __call__(self, ...)  { ... }
    fn __iter__(self)       { ... }
}
```

### 6.2 魔术方法清单

`__init__` `__str__` `__repr__` `__eq__` `__lt__` `__add__` `__sub__` `__mul__` `__len__` `__getitem__` `__setitem__` `__call__` `__contains__` `__iter__` `__hash__`

### 6.3 装饰器

```hl
@cache
@trace("hot-path")
fn fib(n) { ... }
// 等价于：fib = cache(trace("hot-path")(fib))
```

---

## 第七章 · 异常处理

```hl
try {
    risky();
} catch e : IOError {        // 类型化
    log(e);
} catch e {                  // catch-all
    raise;                    // 重抛
} finally {
    cleanup();
}
```

`raise expr;` 抛出，`raise;` 重新抛出当前异常。

---

## 第八章 · 生成器与函数式

### 8.1 `yield` 生成器

```hl
fn nats() {
    let mut n = 0;
    while true { yield n; n = n + 1; }
}
for x in nats() { if x > 100 { break; } print(x); }
```

### 8.2 函数式内置

`map` `filter` `sorted` `reversed` `enumerate` `zip` `any` `all` — 与 Python 同名同义。

---

## 第九章 · 标准库总览

### 9.1 五大门类

| 门类 | 代表函数 | 数量 |
|---|---|---:|
| **I/O** | `print`, `input` | 2 |
| **类型转换** | `int`, `float`, `str`, `bool`, `chr`, `ord`, `hex` | 7 |
| **数组** | `len`, `push`, `pop`, `range`, `array_*` (find/sort/slice/...) | 14 |
| **字符串** | `str_len`, `str_find`, `str_split`, `str_replace`, ... | 17 |
| **数学** | `abs`, `min/max`, `floor`, `clamp`, `pow`, `divmod`, `math_*` | 14 |
| **Map/Dict** | `map_new`, `map_set/get/has/delete`, `keys/values/entries` | 10 |
| **空间** | `hilbert_encode`, `hilbert_decode`, `hilbert_dist` | 3 |
| **反射** | `type_of`, `to_string`, `isinstance`, `hasattr`, `getattr`, `setattr` | 6 |
| **集合** | `set_new`, `set_union`, `set_intersection`, `set_difference` | 5 |

### 9.2 方法调用糖衣

```hl
arr.len()      ≡ len(arr)
arr.push(v)    ≡ push(arr, v)
s.split(",")   ≡ str_split(s, ",")
m.get(k)       ≡ map_get(m, k)
```

> 解糖在 AST → IR 阶段完成，运行时无虚分派开销。

---

## 第十章 · 字节码（HilbertCode）

### 10.1 单元格结构

```
struct CodeCell {
    addr: SpatialAddr,   // u32 Hilbert 位置
    op:   Opcode,        // 指令
}
```

### 10.2 操作码分类

| 类别 | 指令 |
|---|---|
| 字面量加载 | `LoadInt`, `LoadFloat`, `LoadStr`, `LoadBool` |
| 变量 | `LoadVar`, `StoreVar` |
| 算术/逻辑 | `Add`, `Sub`, `Mul`, `Div`, `Mod`, `Eq`, `Lt`, `And`, `Or`, `Not`, `Neg` |
| 流程 | `Jump(addr)`, `JumpIfFalse(addr)`, `Call(addr,argc)`, `Return` |
| 空间 | `Near(slot)`, `Emit(channel_id)`, `Spawn(sector,argc)` |
| 系统 | `Print`, `Halt` |

### 10.3 跳转优化

跳转目标是 SpatialAddr → 通过预计算索引表实现 **O(1) 查找**；索引表 cache-line 对齐，减少抓取延迟。

---

## 第十一章 · 并发模型

### 11.1 Spatial Sector Partitioning

Hilbert 空间在指定深度切分为若干 sector，每个 sector 可绑定到独立 CPU core：

- **空间不相交** → 无需锁
- **cache line 不重叠** → 自动避免 false sharing
- `spawn fn() @sector` 把任务钉在指定空间区域
- `emit channel value` 仅向所在 sector + 相邻广播

### 11.2 与传统并发的对比

| 维度 | 线程模型 | H-L Sector 模型 |
|---|---|---|
| 共享内存 | 全部可见 | 空间隔离 |
| 同步开销 | 锁/CAS | 无（设计上不会冲突） |
| Cache 行为 | 易 false sharing | Hilbert 距离保证分离 |
| 调度 | 抢占 | 协作 + sector 亲和 |

---

## 第十二章 · 缓存感知执行

| 机制 | 收益 |
|---|---|
| 变量槽 64 字节对齐 | 顺序声明的变量同 cache line |
| Hilbert 序指令布局 | 顺序执行 ≈ L1 命中 |
| 同 quadrant 跳转 | 留在 L2 |
| `fold` 曲线归约 | 强保证顺序访问 |

---

## 第十三章 · 编译流水线（5 阶段）

| Phase | 名称 | 关键脚本 | 输出 |
|---|---|---|---|
| 1 | Lex | `hl-compile-pipeline.ps1` | tokens（705,588） |
| 2 | Parse + AST | 同上 | AST nodes（419,590） |
| 3 | IR Lower | 同上 | IR instr（391,722，去死后 292,591） |
| 4 | x86_64 Codegen | 同上 | `.text` 字节（601,014） |
| 5 | Link | 同上 | symbols 6,401, relocs 24,223 |

> 当前运行时间 ≈115 min；最终产物 `bare-kernel/kernel.bin`（609 KB）+ `hicos-hl.img`（741 KB）。

---

## 第十四章 · 工具链生态

| 工具 | 路径 | 角色 |
|---|---|---|
| 编译器主体 | `HicOS_HilbertLang.hl` | H-L → x86_64 |
| 标准库 | `stdlib.hl` | 内置函数实现 |
| 自举入口 | `bootstrap.hl` `hl-bootstrap.hl` | 编译器自举 |
| 流水线 | `scripts/hl-compile-pipeline.ps1` | 5 阶段编排 |
| Linter | `hl-lint.hl` | 静态检查 |
| 镜像构建 | `build-hl-image.hl` + `rebuild-image.ps1` | 启动盘发射 |
| 诊断 | `scripts/diag-balance.ps1` | balance error 快诊 |
| 闸门 | `scripts/full-gate.ps1` `release-validate.ps1` | 发布门禁 |
| 测试 | `test-runner.hl` `test-suite.hl` `test_*.hl` | 单元 + 链路 |

---

## 第十五章 · 当前实现状态

| 项 | 数值 / 状态 |
|---|---|
| 总 H-L 源行 | 131,362 |
| 顶层子系统 | 28 个 (`HicOS_*.hl`) |
| 内核模块 | 470 个 (`bare-kernel/hl/*.hl`) |
| 编译产出函数 | 5,598 |
| 自举完整度 | 95%（`rebuild-image.ps1` 仍需 PowerShell） |
| **未解析重定位** ⚠ | 1,871（Sprint 35 处理） |
| **Token balance errors** ⚠ | 17（Sprint 34 处理） |

---

## 第十六章 · 设计权衡与已知边界

### 16.1 取舍

| 选择 | 收益 | 代价 |
|---|---|---|
| Hilbert 空间寻址 | cache 友好 + 无锁并发 | 编译期更复杂、地址计算开销 |
| 类型注解可选 | 表达力高 | 部分错误延后到运行时 |
| 异构 array | 灵活 | 单元素需 tag |
| 一等闭包 + class | 多范式 | 需 GC（HicOS 内为简化引用计数） |
| 自举 100% | 零依赖 | 工具链初次冷启动复杂 |

### 16.2 当前未支持

- 多重继承（仅单继承）
- async/await（用 `spawn` + `emit` 取代）
- 宏系统（用装饰器 + 元编程函数取代）
- 模板/泛型（计划在 H-L 2.0）
- ARM64/RISC-V 后端（计划阶段 D）

---

## 第十七章 · 学习路径

### 17.1 入门（约 2 小时）

1. 读本文档第三、四、九章
2. 阅读 `stdlib.hl` 前 200 行，体会方法 desugar
3. 写 Hello World 与 Fibonacci，跑流水线编译
4. 改造一个 `test_*.hl` 例子

### 17.2 进阶（约 1 天）

1. 通读 `HILBERT_LANG_BNF.md`
2. 阅读 `HicOS_HilbertLang.hl` 主结构（lexer / parser / IR）
3. 写一个 `quadrant` + `near` + `fold` 的微型程序
4. 用 `@decorator` 与生成器实现一个迭代管道

### 17.3 专家（系统/语言开发）

1. 跟踪一次 Phase 1–5 完整流水线，看 `.tmp/pipe.log` 关键事件
2. 修一个 unresolved reloc（参 ROADMAP Sprint 35）
3. 给 `kernel-symbols.json` 增补一个 builtin 符号
4. 在 `bare-kernel/hl/` 写一个新内核模块并加入 manifest

---

## 第十八章 · 路线图（语言层面）

### 18.1 H-L 1.x（当前）

- v1.1：tokenizer 字符串内括号修复（balance errors → 0）
- v1.2：unresolved relocs 收敛到 < 50
- v1.3：完整 GUI 路径符号（framebuffer / heap / input）

### 18.2 H-L 2.0（中期）

- 泛型 / 参数化类型（`fn map<T,U>(a: array[T], f: fn(T)->U) -> array[U]`）
- 模式匹配 `match expr { ... }`
- `async fn` + `await`（基于 `spawn`/`emit` 改写）
- 编译时常量求值（`const fn`）

### 18.3 H-L 3.0（远期）

- WASM 后端（浏览器中运行 H-L）
- ARM64 / RISC-V 后端
- 形式化语义证明（核心子集 Coq/Lean）
- 完全自举（移除 `rebuild-image.ps1` 的 PowerShell 依赖）

---

## 第十九章 · 与其它语言的对照速览

| 维度 | Python | Rust | Go | **H-L** |
|---|---|---|---|---|
| 类型 | 动态 + hint | 静态 | 静态 | 动态 + hint |
| 内存 | GC | 所有权 | GC | 引用计数（裸机化简） |
| 并发 | GIL/asyncio | async + Send/Sync | goroutine | sector partition |
| 表达力 | 极高 | 中 | 中 | 高（接近 Python） |
| 系统级 | 否 | 是 | 部分 | **是（裸机直跑）** |
| 空间语义 | — | — | — | **核心** |
| 自举 | CPython（C） | rustc（OCaml→Rust） | Go（C→Go） | **100% 自举** |

---

## 第二十章 · 参考与索引

| 参考 | 路径 |
|---|---|
| 形式文法 | `HILBERT_LANG_BNF.md` |
| 编译器实现 | `HicOS_HilbertLang.hl` |
| 标准库 | `stdlib.hl` |
| 自举入口 | `bootstrap.hl`, `hl-bootstrap.hl` |
| 流水线 | `scripts/hl-compile-pipeline.ps1` |
| 例程 | `test_*.hl`, `bare-kernel/hl/*.hl` |
| 项目大纲 | `PROJECT_OUTLINE.md` |
| 路线图 | `ROADMAP.md` |
| 状态 | `PROJECT_STATUS.md` |

---

## 附录 A · 关键字总表

```
let mut fn return if elif else while for in not
near quadrant warp emit fold spawn
true false nil
break continue try catch finally raise
import as assert del pass
class self super yield
and or
```

## 附录 B · 经典片段

```hl
// 1. Hello World
print("Hello, Hilbert World!");

// 2. 斐波那契（迭代）
let a = 0; let b = 1; let mut i = 0;
while i < 10 {
    let tmp = a + b; a = b; b = tmp; i = i + 1;
}
print(b);

// 3. 分形作用域 + near
quadrant physics {
    let gravity = 9;
    let mass = 42;
}
quadrant render {
    let g = near gravity;     // 解析到 physics.gravity
    print(g);
}

// 4. 空间并发
fn compute(x) { return x * x; }
spawn compute(42);

// 5. 列表推导 + 折叠
let squares = [x*x for x in range(10)];
let total = fold squares from 0 with acc, e -> acc + e;
print(total);

// 6. 类 + 装饰器 + 生成器
@cache
fn primes_up_to(n) {
    let mut sieve = [true for _ in range(n+1)];
    let mut i = 2;
    while i*i <= n {
        if sieve[i] {
            let mut j = i*i;
            while j <= n { sieve[j] = false; j = j + i; }
        }
        i = i + 1;
    }
    let mut out = [];
    for k in range(2, n+1) {
        if sieve[k] { out.push(k); }
    }
    return out;
}
```

---

> *本大纲是 H-L 1.0 的功能与生态总览。语言细节以 `HILBERT_LANG_BNF.md` 为准；实现细节以 `HicOS_HilbertLang.hl` 为准；运行状态以 `PROJECT_STATUS.md` 为准。*
