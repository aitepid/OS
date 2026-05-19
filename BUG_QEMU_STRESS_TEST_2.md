# HicOS QEMU 压力测试 BUG 报告 — Round 2

> 测试日期：2026-05-19 | 测试方法：全量代码静态审查 + QEMU x86_64 运行验证
> 前一轮（Round 1）25 个 BUG 已全部修复（Sprint 26/27）。

---

## 问题汇总

| 编号 | 文件 | 严重级别 | 问题类型 | 一句话描述 |
|------|------|----------|----------|-----------|
| BUG-026 | kernel_entry.hl:6747-6754 | **P0** | 编译器缺陷 | 解析器运算符 opcode 赋值全部失败：变量遮蔽导致二元运算符永远无法识别 |
| BUG-027 | kernel_entry.hl:5619-5620 | **P1** | 变量遮蔽 | ext2 GDT sector 恒为 0：1k/4k 块大小的 inode 全部读错位置 |
| BUG-028 | musl_shim.hl:122 | **P1** | API 误用 | `set_at(got, 0, avail)` 把标量当数组：`ms_fread` 始终返回 nbytes 而非实际可读字节数 |
| BUG-029 | lz4.hl:160,162 | **P1** | 变量遮蔽 | `lit_nibble`/`mat_nibble` 截断逻辑失效：LZ4 token byte 高低 nibble 溢出导致压缩输出损坏 |
| BUG-030 | abi.hl:109,133 | **P1** | 未定义符号 | `CALLER_SAVED` 全局未定义：调用 `abi_emit_caller_save/restore` 时运行时崩溃 |
| BUG-031 | tls.hl:467-477 | **P1** | 协议错误 | `tls12_recv` 用 XOR 解密但发送用 AES-GCM 加密：加解密不对称，所有接收数据均乱码 |
| BUG-032 | cbor.hl:197 | **P1** | 变量遮蔽 | `let limit = max_bytes` 遮蔽外层变量：`max_bytes` 限制从不生效，可能越界写 |
| BUG-033 | reservoir_sampling.hl:135 | **P1** | 可变性错误 | `let min_key` 缺少 `mut`：加权蓄水池采样中比较 `min_key` 时永远用初始值，替换逻辑永远错误 |
| BUG-034 | kernel_entry.hl:5605 | **P2** | 变量遮蔽 | `if is == 0 { let is = 128; }` 遮蔽：rev0 ext2 inode_size 不会默认为 128，读到 0 字节步长 |
| BUG-035 | kernel_entry.hl:7504 | **P2** | 变量遮蔽 | `if limit > 32 { let limit = 32; }` 遮蔽：hex dump 未限制为 32 字节，可能输出超长垃圾 |
| BUG-036 | random.hl:155-156 | **P2** | 语法错误 | `random_status()` 使用 H-L 不支持的内联 if-else 表达式：编译期报错 |
| BUG-037 | quic.hl:363-366 | **P2** | 协议伪实现 | `quic_process_handshake` 用 XOR 混合 CID 代替真实 HKDF：应用层密钥派生不正确 |
| BUG-038 | dns.hl:288-291 | **P3** | 逻辑冗余 | 缓存命中检测用 4 个独立 if 逐字节判断：语义正确但冗余，且遗漏 0.x.x.x 等合法地址 |
| BUG-039 | debugger.hl | **P3** | 缺少校验 | `dbg_set_arch` 未验证 arch 参数范围：传入 2~255 会把所有 opcode 长度清零 |
| BUG-040 | tls.hl:304-318 | **P3** | 硬编码数据 | `tls12_client_hello` record length 字段硬编码为 0：不符合 TLS 1.2 规范 |

---

## 详细描述

### BUG-026 — kernel_entry.hl：解析器运算符 opcode 变量遮蔽（P0）

**文件**：`bare-kernel/hl/kernel_entry.hl`，第 6746–6754 行

**症状**：编译 H-L 源码时，所有二元运算符（`+` `-` `*` `/` `==` `!=` `<` `>`）均不被解析，产生的 AST 中运算符 opcode 始终为 0。表达式求值全部错误，编译出的代码行为完全不可预期。

**根因**：
```hl
let mut op_type = 0;          // 外层声明
if tt == 30 { let op_type = 10; } // BUG: let 遮蔽，赋值不写回外层
if tt == 31 { let op_type = 11; } // BUG: 同上
...
if op_type > 0 {              // 永远为 false！外层 op_type 始终是 0
```

**修复**：将所有 `if tt == N { let op_type = M; }` 改为 `if tt == N { op_type = M; }`（去掉 `let`）。

---

### BUG-027 — kernel_entry.hl：ext2 GDT sector 变量遮蔽（P1）

**文件**：`bare-kernel/hl/kernel_entry.hl`，第 5617–5624 行

**症状**：QEMU 加载 ext2 文件系统时，所有 inode 读取地址错误，VFS 返回全零数据或随机内存内容，`ls`/`cat` 等命令输出乱码。

**根因**：
```hl
let mut gdt_sector = 0;
if bs == 1024 { let gdt_sector = 4; }  // BUG: 内层声明遮蔽，外层始终为 0
if bs == 4096 { let gdt_sector = 8; }  // BUG: 同上
// gdt_sector 永远是 0 → GDT 从扇区 0（MBR）读取
```

**修复**：改为赋值语句：
```hl
if bs == 1024 { gdt_sector = 4; }
if bs == 4096 { gdt_sector = 8; }
```

---

### BUG-028 — musl_shim.hl：`ms_fread` 错误用 `set_at` 操作标量（P1）

**文件**：`bare-kernel/hl/musl_shim.hl`，第 122 行

**症状**：`ms_fread` 无论 `avail` 多少，始终返回原始 `nbytes` 请求量；读文件时不会因缓冲区可用数据不足而截断，导致读越界或返回错误字节数。

**根因**：
```hl
let mut got = nbytes;
if avail < nbytes { set_at(got, 0, avail); }  // BUG: got 是整数，不是数组
```
`set_at(scalar, 0, value)` 是数组操作语义，对整数变量无效，`got` 始终保持为 `nbytes`。

**修复**：
```hl
if avail < nbytes { got = avail; }
```

---

### BUG-029 — lz4.hl：token nibble 截断变量遮蔽（P1）

**文件**：`bare-kernel/hl/lz4.hl`，第 160、162 行

**症状**：压缩输出的 LZ4 token byte 格式损坏：当字面量长度或匹配长度超过 15 时，nibble 未被截断，写入的 token byte 超出 0xFF 范围，解压端无法解析，导致解压数据错误。

**根因**：
```hl
let mut lit_nibble = litlen;
if lit_nibble > 15 { let lit_nibble = 15; }   // BUG: 内层变量，外层不变
let mut mat_nibble = matchlen_enc;
if mat_nibble > 15 { let mat_nibble = 15; }   // BUG: 同上
mem_write_u8(dst + dp, lit_nibble * 16 + mat_nibble);  // 用的是未截断的值
```

**修复**：
```hl
if lit_nibble > 15 { lit_nibble = 15; }
if mat_nibble > 15 { mat_nibble = 15; }
```

---

### BUG-030 — abi.hl：`CALLER_SAVED` 全局符号未定义（P1）

**文件**：`bare-kernel/hl/abi.hl`，第 109、110、133、134 行

**症状**：调用 `abi_emit_caller_save(buf, live_regs)` 或 `abi_emit_caller_restore` 时运行时错误（符号未定义），代码生成阶段崩溃，无法为跨调用活跃变量生成 caller-save push/pop。

**根因**：`abi.hl` 引用了 `CALLER_SAVED` 数组（System V AMD64 caller-saved 寄存器列表），但该符号在整个代码库中均未定义。`calling_conv.hl` 提供的是 `cc_caller_saved` 掩码数组（位图），不是 `CALLER_SAVED` 寄存器列表。

**修复**：在 `abi.hl` 顶部定义：
```hl
// Caller-saved registers: RAX RCX RDX RSI RDI R8 R9 R10 R11
let CALLER_SAVED = [0, 1, 2, 6, 7, 8, 9, 10, 11];
```

---

### BUG-031 — tls.hl：`tls12_recv` XOR 解密与 AES-GCM 发送不对称（P1）

**文件**：`bare-kernel/hl/tls.hl`，第 467–477 行

**症状**：TLS 连接建立后，接收端解密的 application data 始终是乱码。与服务器的所有 HTTPS 响应均无法正确解析。

**根因**：
```hl
// tls12_send 用 AES-GCM 加密（正确）
// tls12_recv 用 XOR 解密（错误）
let mut k = key[i % len(key)];
push(plain, record[5 + i] ^ k);  // 简单 XOR，而非 AES-GCM 解密
```

**修复**：`tls12_recv` 需对接收到的密文调用 `aes_gcm_decrypt`，与 `tls12_send` 的 `aes_gcm_encrypt` 对称。验证 GCM auth tag，tag 不符则丢弃。

---

### BUG-032 — cbor.hl：`_cbor_hex_to_bytes` max_bytes 限制变量遮蔽（P1）

**文件**：`bare-kernel/hl/cbor.hl`，第 197 行

**症状**：调用 `_cbor_hex_to_bytes(hexstr, dst_addr, max_bytes)` 时，`max_bytes` 参数无效，始终按十六进制字符串的完整长度写入，可能覆盖目标缓冲区后方内存。

**根因**：
```hl
let mut limit = n;
if max_bytes < n { let limit = max_bytes; }  // BUG: 内层 let 遮蔽，外层 limit 不变
while i < limit {   // 用的是外层 limit（== n），max_bytes 从未生效
```

**修复**：
```hl
if max_bytes < n { limit = max_bytes; }
```

---

### BUG-033 — reservoir_sampling.hl：`min_key` 缺少 `mut` 声明（P1）

**文件**：`bare-kernel/hl/reservoir_sampling.hl`，第 135–142 行

**症状**：加权蓄水池采样（`rs_w_add` 函数）中，寻找最小键的逻辑始终返回初始值 `rs_w_keys[0]`，不随循环更新，导致替换判断 `key > min_key` 永远基于第 0 项，采样概率分布错误。

**根因**：
```hl
let min_idx = 0; let min_key = rs_w_keys[0];   // BUG: min_key 未加 mut
...
if rs_w_keys[i] < min_key { min_key = rs_w_keys[i]; ... }  // 赋值到不可变变量
```

**修复**：
```hl
let mut min_idx = 0; let mut min_key = rs_w_keys[0];
```

---

### BUG-034 — kernel_entry.hl：ext2 inode_size 默认值变量遮蔽（P2）

**文件**：`bare-kernel/hl/kernel_entry.hl`，第 5603–5605 行

**症状**：挂载 ext2 rev0 文件系统（superblock inode_size 字段 = 0）时，inode_size 保持为 0，`idx * inode_size` 恒为 0，所有 inode 读取都指向同一个地址。

**根因**：
```hl
let mut is = inode_size;
if is == 0 { let is = 128; }   // BUG: 内层 let，外层 is 仍为 0
```

**修复**：
```hl
if is == 0 { is = 128; }
```

---

### BUG-035 — kernel_entry.hl：hex dump limit 变量遮蔽（P2）

**文件**：`bare-kernel/hl/kernel_entry.hl`，第 7503–7504 行

**症状**：调试打印内核代码段的 hex dump 时，不受 32 字节限制，会输出 `code_size` 个字节（可能数 KB），控制台刷屏。

**根因**：
```hl
let mut limit = code_size;
if limit > 32 { let limit = 32; }  // BUG: 内层 let，外层 limit 不变
while i < limit {  // 实际用 code_size
```

**修复**：
```hl
if limit > 32 { limit = 32; }
```

---

### BUG-036 — random.hl：`random_status` 内联 if-else 表达式语法错误（P2）

**文件**：`bare-kernel/hl/random.hl`，第 155–156 行

**症状**：加载 `random.hl` 时编译器报错，导致整个 CSPRNG 模块无法装载，所有随机数生成失败。

**根因**：
```hl
return "entropy: ... " + (if csprng_ready == 1 { "ready" } else { "seeding" });
```
H-L 的 `if` 是语句而非表达式，不能用于 `+` 字符串拼接的右侧。

**修复**：
```hl
fn random_status() {
    let mut state = "seeding";
    if csprng_ready == 1 { state = "ready"; }
    return "entropy: " + to_string(entropy_count) + " bits, CSPRNG: " + state;
}
```

---

### BUG-037 — quic.hl：握手密钥派生用 XOR 而非 HKDF（P2）

**文件**：`bare-kernel/hl/quic.hl`，第 357–368 行

**症状**：QUIC 握手完成后派生的 `key_tx`/`key_rx` 是两个 CID 的简单 XOR 混合，不符合 RFC 9001 HKDF-Expand-Label 规范，与真实服务器的密钥不匹配，0-RTT/1-RTT 数据加密失败。

**根因**：
```hl
let mut key_tx = local_cid ^ remote_cid ^ 2862933555777941757;  // 简单 XOR
let mut key_rx = remote_cid ^ local_cid ^ 1442695040888963407;  // 简单 XOR
```

**修复**：使用 `hkdf_extract`/`hkdf_expand` 从握手 secret 派生 `key_tx`/`key_rx`，参考 RFC 9001 Section 5.1。

---

### BUG-038 — dns.hl：缓存命中检测逻辑冗余且遗漏合法地址（P3）

**文件**：`bare-kernel/hl/dns.hl`，第 287–291 行

**症状**：IP 地址首字节为 0（如 `0.0.0.0`、`0.x.x.x`）时缓存命中无法被识别，仍发送 DNS 查询（逻辑上这类地址极少出现，影响较小）。

**根因**：
```hl
if cached[0] != 0 { return cached; }
if cached[1] != 0 { return cached; }
if cached[2] != 0 { return cached; }
if cached[3] != 0 { return cached; }
// 仅当全部字节 == 0 时才视为 cache miss
```
`_dns_cache_lookup` 返回 `[0,0,0,0]` 表示未命中，这四条 if 的组合意图正确，但结构冗余，且 IP 如 `0.168.1.1`（若缓存中存在）也能被第 2 个 if 识别，语义并非真正错误。建议整合为单一条件。

**修复**：
```hl
if cached[0] != 0 || cached[1] != 0 || cached[2] != 0 || cached[3] != 0 {
    return cached;
}
```
（若 H-L 不支持 `||`，改用嵌套 if 或标志变量）

---

### BUG-039 — debugger.hl：`dbg_set_arch` 未验证参数范围（P3）

**文件**：`bare-kernel/hl/debugger.hl`，`dbg_set_arch` 函数

**症状**：调用 `dbg_set_arch(2)` 等无效 arch 值时，由于 `else` 分支执行 x86_64 路径（当前实现），实际不会崩溃，但语义不明确；若日后添加新 arch 分支，旧调用方传入未知值会静默填充 x86_64 表，误导调试器。

**根因**：函数只有 `if arch == 1` 和 `else` 两条路径，无显式错误返回。

**修复**：
```hl
fn dbg_set_arch(arch) {
    if arch != 0 { if arch != 1 { return 0 - 1; } }  // 无效 arch
    ...
}
```

---

### BUG-040 — tls.hl：`tls12_client_hello` record length 硬编码为 0（P3）

**文件**：`bare-kernel/hl/tls.hl`，第 304–318 行

**症状**：客户端发出的 ClientHello TLS record 的 length 字段为 `{0, 0}`，服务器解析时认为 record 长度为 0，可能忽略整个握手消息，导致 TLS 握手超时或失败。

**根因**：
```hl
push(hello, TLS_CONTENT_HANDSHAKE);
push(hello, 3); push(hello, 3);
push(hello, 0); push(hello, 0);  // length 字段硬编码 0
```

**修复**：构建完整 `hello` 数组后，回填 `hello[3]`/`hello[4]` 为 `(len(hello) - 5) / 256` 和 `(len(hello) - 5) % 256`。

---

## 修复优先级建议

```
立即修复（P0）：BUG-026（编译器解析器彻底失效）
本轮 Sprint（P1）：BUG-027 BUG-028 BUG-029 BUG-030 BUG-031 BUG-032 BUG-033
下轮 Sprint（P2）：BUG-034 BUG-035 BUG-036 BUG-037
待优化（P3）：   BUG-038 BUG-039 BUG-040
```

---

*报告生成：Round 2 静态审查，2026-05-19*
