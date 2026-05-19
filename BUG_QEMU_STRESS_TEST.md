# HicOS QEMU 可视化压力测试报告

> 测试日期：2026-05-19  
> 测试环境：QEMU x86_64 with VirtIO devices, 128 MB RAM  
> 内核版本：HicOS 6.0 (Iteration 440)  
> 测试方法：QEMU BIOS boot with serial output capture + static code analysis  

---

## 一、QEMU 启动测试结果

### ✅ 启动成功

```
HicOS 6.0 -- Hilbert-Lang Kernel
=== Kernel Init ===
  [ok] Serial: COM1 38400 8N1
  [ok] PIC: 8259A remapped
  [ok] PIT: 100 Hz timer
  [ok] IDT: 256 vectors
  [ok] Scancode: PS/2 loaded
  [ok] Timer ticks: active
  [ok] PCI: 5 device(s)
  [ok] VirtIO-blk: detected (PCI 1AF4:1001)
  [ok] VirtIO-blk: BAR0=0x0000C000 qsz=00000100
  [ok] VirtIO-blk: initialized (32 MB)
  [ok] Disk: sector 0 = 00 00 00 00 ... (blank test disk)
  [ok] Disk: write+readback sector 100 verified
  [ok] VirtIO-net: detected (PCI 1AF4:1000)
  [ok] VirtIO-net: MAC=52:54:00:12:34:56
  [ok] VirtIO-net: ARP request sent (who-has 10.0.2.2)
  [ok] Memory: 8MB identity mapped
  [ok] VESA: 1024x768x32 LFB=FD000000
  [ok] VESA: framebuffer write/read verified
  [ok] SYSCALL: configured
  [ok] Modules: 113 kernel, 27 userspace
=== Boot Complete ===
HicOS> BABABABABABABAB
```

**结论**：内核启动正常，所有关键硬件初始化成功。

---

## 二、发现的问题

### 🔴 Critical Issues (P0)

#### BUG-001: PS/2 键盘幽灵输入 — "BABABABABABABAB" 垃圾输出

**严重程度**：P0 (启动过程中立即出现)  
**症状**：Shell 提示符后立即输出 `BABABABABABABAB`（重复'A'和'B'字符）  
**根本原因**：  
- Shell 从内存地址 0x300008 读取 PS/2 扫描码
- 代码直接将扫描码视为 ASCII 字符：`let mut ch = scancode % 256;`
- **未进行扫描码→ASCII 翻译**（应该调用 scancode.hl 中的翻译表）
- **未过滤按键释放码**（扫描码 ≥ 0x80）
- QEMU PS/2 控制器初始化发送字节 0x41 ('A') 和 0x42 ('B')，被误解为键盘输入

**受影响文件**：
- `bare-kernel/hl/shell.hl:9003` — `let mut ch = scancode % 256;`
- `bare-kernel/hl/kernel_entry.hl:10069` — 键盘 ISR 直接存储原始扫描码

**修复方案**：
```hl
// 当前（错误）
let mut ch = scancode % 256;

// 应该
if scancode >= 0x80 { return 0; }  // 忽略按键释放
let mut ch = scancode_to_ascii(scancode);  // 调用 scancode.hl 翻译
```

---

#### BUG-002: GDB 存根数组越界访问

**严重程度**：P0 (可导致内核崩溃)  
**文件**：`bare-kernel/hl/gdb_stub.hl:235`  
**代码**：
```hl
fn gs_send_pkt(cmd, arg) {
    if cmd == 3 {  // GS_CMD_WRITE_REG
        result = gs_regs[arg];  // ← arg 无边界检查！
    }
}
```

**问题**：GDB 协议数据包中的 `arg` 值可达 0xFF，但 `gs_regs` 数组仅有 8 个元素（寄存器）。  
**影响**：远程调试器可触发内存越界读取。

**修复**：
```hl
if arg >= 8 { return 0 - 1; }  // 返回错误
let mut val = gs_regs[arg];
```

---

### 🟠 High Priority Issues (P1) — 安全/功能缺失

#### BUG-003: TLS 1.3 GCM 认证标签伪造

**严重程度**：P1 (密码学可绕过)  
**文件**：`bare-kernel/hl/tls.hl:440` (注释)  
**问题**：GCM 认证标签硬编码为 16 字节零值，而非使用 GHASH 计算  
**代码**：
```
"Append fake GCM tag (16 bytes)"  // ← 注释明确说是"假的"
```

**影响**：任何人都可伪造 TLS 1.3 消息，中间人攻击可能。

---

#### BUG-004: AES-GCM GHASH 实现错误

**严重程度**：P1 (密码学损坏)  
**文件**：`bare-kernel/hl/aes_gcm.hl`  
**问题**：GHASH 使用玩具哈希函数而非 GF(2^128) 多项式乘法  
**代码**：
```hl
let mut ghash_val = (round * 31 + i * 7 + key_byte) % 256;  // ← 错误！
```

**正确方案**：应使用 GF(2^128) 乘法、Karatsuba 算法或查表。

---

#### BUG-005: 随机数生成器硬编码回退值

**严重程度**：P1 (弱熵)  
**文件**：`bare-kernel/hl/random.hl:124`  
**问题**：当 CSPRNG 熵池未就绪时，返回硬编码值 `42`  
**代码**：
```hl
fn random_u32() {
    if csprng_ready == 0 { return 42; }  // ← 确定性！
    // ...
}
```

**影响**：所有使用未就绪熵池的加密初始化都得到相同的 IV/nonce = 42。

---

#### BUG-006: JWT 签名验证未实现

**严重程度**：P1 (认证绕过)  
**文件**：`bare-kernel/hl/jwt.hl:13` (注释)  
**代码**：
```
"Signature verification not implemented (requires HMAC-SHA256)"
```

**影响**：任何伪造的 JWT 都被接受。

---

#### BUG-007: X.509 证书解析使用估计长度

**严重程度**：P1 (PEM 解析不可靠)  
**文件**：`bare-kernel/hl/x509.hl:397`  
**问题**：`x509_parse_stub()` 使用**估计**的证书大小而非解析 DER 长度字段  
**代码**：
```hl
fn x509_parse_stub(pem_data) {
    // 使用估计大小，不解析真实 DER 长度
    let est_size = 2048;  // ← 硬编码！
    return parse_der_at(pem_data, 27, est_size);
}
```

**修复**：正确解析 DER BER 长度编码。

---

#### BUG-008: DNS 解析 TODO 存根

**严重程度**：P1 (网络功能缺失)  
**文件**：`bare-kernel/hl/dns.hl:302`  
**代码**：
```hl
// TODO: send via UDP to dns_server:53, receive response
// 实际实现：无操作
```

**影响**：DNS 查询永不发送/接收，所有 DNS 依赖功能无法工作。

---

#### BUG-009: Socket 系统调用返回 ENOSYS

**严重程度**：P1 (用户空间网络不可用)  
**文件**：`bare-kernel/hl/syscall.hl:236` (注释)  
**代码**：
```
"Socket stubs (returns -ENOSYS for now, placeholders)"
```

**影响**：用户程序无法创建套接字，所有网络库失效。

---

### 🟡 Medium Priority Issues (P2) — 功能不完整

#### BUG-010: QUIC AEAD 加密标记为存根

**严重程度**：P2 (QUIC 协议不可用)  
**文件**：`bare-kernel/hl/quic.hl:6`  
**代码**：
```
"Packet protection: AEAD encryption (ChaCha20-Poly1305 / AES-128-GCM stubs)"
```

---

#### BUG-011: JIT 编译器仅支持常量和简单加法

**严重程度**：P2 (JIT 不实用)  
**文件**：`bare-kernel/hl/jit_stub.hl:194`  
**代码**：
```hl
// f1 is hot — compile a const stub returning 42
// 仅处理：
// - Const 返回值
// - Add 操作
// 其他所有操作码落到 stub 返回 0
```

**影响**：任何实际函数的 JIT 编译都失败。

---

#### BUG-012: WASM JIT 代码缓冲区仅 256 字节

**严重程度**：P2 (缓冲区溢出)  
**文件**：`bare-kernel/hl/wasm_jit.hl`  
**问题**：每个 WASM 函数分配 256 字节代码缓冲区（x86_64 编译的 WASM 函数通常 500+ 字节）

**修复**：动态分配或增加缓冲区到 4KB。

---

#### BUG-013: ext4 无扩展树支持

**严重程度**：P2 (文件系统兼容性)  
**文件**：`bare-kernel/hl/ext4.hl:227`  
**问题**：仅支持 ext2 风格的块指针（直接、一级间接、二级间接），不支持现代 ext4 扩展树  
**影响**：大文件（>4GB）和碎片化现代 ext4 文件无法读取。

---

#### BUG-014: 链接器所有未解决符号返回 0

**严重程度**：P2 (静默失败)  
**文件**：`bare-kernel/hl/linker.hl:217`  
**问题**：所有未解决的前向声明创建为存根：`xor eax,eax; ret`（返回 0）  
**影响**：调用未定义函数时无错误，只是得到 0 返回值。

---

#### BUG-015: PTY "伪造 FD" 与实际 VFS fd 可能冲突

**严重程度**：P2 (fd 命名空间污染)  
**文件**：`bare-kernel/hl/pty.hl:248`  
**代码**：
```
"Allocate fake fds (use pty_id shifted into high range to avoid VFS collision)"
```

**问题**：高位范围可能与扩展 VFS fd 冲突。

---

#### BUG-016: CBOR 标签类型未实现

**严重程度**：P2 (CBOR 解析不完整)  
**文件**：`bare-kernel/hl/cbor.hl:9,19`  
**代码**：
```
"6 = tag (not implemented)"
"31 = indefinite length (not implemented)"
```

**影响**：CBOR 数据包含这些特性时解析失败。

---

### 🔵 Low Priority Issues (P3) — 质量问题

#### BUG-017: ABI 数组写入无边界检查

**严重程度**：P3 (潜在越界)  
**文件**：`bare-kernel/hl/abi.hl:41`  
**代码**：
```hl
abi_func_name[idx] = name;  // ← idx 未验证 < ABI_MAX_FUNCS
```

---

#### BUG-018: 调用约定数组索引未验证

**严重程度**：P3 (越界风险)  
**文件**：`bare-kernel/hl/calling_conv.hl:105`  
**代码**：
```hl
set_at(cc_arg_reg, idx, cc_iarg_regs[idx]);  // ← idx 未验证
```

---

#### BUG-019: UI 设置 tick 函数为空存根

**严重程度**：P3 (功能缺失)  
**文件**：`bare-kernel/hl/ui_settings.hl:246`  
**问题**：`uisettings_tick()` 函数体为空，实时设置更新永不触发

---

#### BUG-020: musl_shim malloc/free 为固定大小内存池

**严重程度**：P3 (内存管理有限)  
**文件**：`bare-kernel/hl/musl_shim.hl:6-8`  
**代码**：
```
"malloc/free/realloc/stdio/string functions marked as stubs (size-tracked slab)"
```

**问题**：无真实堆管理，固定竞技场可能耗尽。

---

#### BUG-021: 高级验证模块为空框架

**严重程度**：P3 (声称验证但不实施)  
**文件**：`bare-kernel/hl/advanced_verify.hl:79`  
**问题**：打印"Advanced verify: eBPF / TLS1.3 / QUIC"但不执行任何验证逻辑

---

#### BUG-022: LSP 服务器为完整存根

**严重程度**：P3 (功能缺失)  
**文件**：`bare-kernel/hl/lsp_server.hl` (57 行)  
**问题**：Language Server Protocol 标记为 Phase 7 存根

---

#### BUG-023: 调试器操作码长度表硬编码 x86_64

**严重程度**：P3 (不可移植)  
**文件**：`bare-kernel/hl/debugger.hl`  
**问题**：操作码长度表仅适用于 x86_64

---

#### BUG-024: 语法高亮器简化实现

**严重程度**：P3 (功能有限)  
**文件**：`bare-kernel/hl/syntax_highlight.hl` (412 行)  
**问题**：字符标记器简化/不完整

---

#### BUG-025: 代码补全为骨架实现

**严重程度**：P3 (功能有限)  
**文件**：`bare-kernel/hl/code_complete.hl` (252 行)  
**问题**：补全引擎为骨架实现

---

## 三、统计汇总

| 严重级别 | 问题数 | 文件数 | 类型 |
|---------|-------|-------|------|
| **P0 Critical** | 2 | 3 | 崩溃/安全 |
| **P1 High** | 7 | 7 | 密码学/认证 |
| **P2 Medium** | 7 | 8 | 功能不完整 |
| **P3 Low** | 9 | 9 | 质量问题 |
| **总计** | **25** | **27** | — |

---

## 四、修复优先级建议

### 立即修复（Sprint 26）

1. **BUG-001**：PS/2 键盘幽灵输入 — 调用 scancode.hl 翻译，过滤释放码
2. **BUG-002**：GDB 数组 OOB — 添加 `arg < 8` 检查
3. **BUG-003**：TLS GCM 认证 — 实现真实 GHASH，移除"假"标签

### 高优先级（Sprint 27-28）

4. **BUG-004**：AES-GCM 修复
5. **BUG-005**：随机数生成器
6. **BUG-006**：JWT 签名验证
7. **BUG-007**：X.509 DER 解析

### 中优先级（Sprint 29+）

8. **BUG-008**：DNS 实现
9. **BUG-009**：Socket 系统调用
10. **BUG-010-025**：功能完整和质量改进

---

## 五、测试建议

- [ ] 运行 QEMU 启动测试（已做 ✅）
- [ ] 实施 PS/2 键盘自动化测试
- [ ] 添加密码学单元测试（TLS、JWT、AES）
- [ ] 网络功能集成测试（DNS、Socket、QUIC）
- [ ] 压力测试：长运行时间、大文件操作

---

**最后更新**：2026-05-19 (HicOS Iteration 440)
