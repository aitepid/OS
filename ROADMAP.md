# HicOS Roadmap

## 当前同步基线（迭代 246 实测）

- `301` 个 `.hl` 文件（~80,300 行）：69 根目录 + 232 内核模块
- `28` 个 PowerShell 脚本（9,729 行）
- `hl-bootstrap.hl`：`4,306` 行 / `208` 函数 | `stdlib.hl`：`1,385` 行 / `143` 函数
- 编译产出函数：`2,200+` | 链接符号：`2,500+` | Shell 命令：`580`
- 构建/测试主入口：`hl-bootstrap.cmd test`
- 最近完成功能迭代：`246`（Brotli + SM3 + SM4）
- Git 提交数：`114`

## 已完成阶段

### 阶段 0（迭代 73-80）：Shell / 命令迭代
- 环境变量 / 信号 / 历史 / 方向键
- hostname / uname / date / netstat / arp
- Shell pipe + grep（63 个命令）
- 阶段发布整理

### 阶段 1（迭代 81-84）：内存 + 排序算法
| 迭代 | 模块 | 升级 |
|---|---|---|
| 81 | `page_alloc.hl` | 位图 → **伙伴系统** |
| 82 | `kmalloc.hl` | 首次适配 → **分级空闲链表** |
| 83 | `block_cache.hl` | 线性扫描 → **哈希+LRU 双链** |
| 84 | `hilbert_alloc.hl` | 插入排序 → **归并排序** |

### 阶段 2（迭代 86-89）：网络 + 文件系统
| 迭代 | 模块 | 升级 |
|---|---|---|
| 86 | `tcp.hl` | 无流控 → **Reno 拥塞控制+RTT** |
| 87 | `dns.hl` | 无缓存 → **TTL 哈希缓存** |
| 88 | `vfs.hl` | 线性匹配 → **Trie 前缀树** |
| 89 | 文档 | 阶段 2 收敛 |

### 阶段 3（迭代 91-95）：外设 + 多核 + 页面置换
| 迭代 | 模块 | 升级 |
|---|---|---|
| 91 | `arp.hl`+`net.hl` | 线性扫描 → **哈希表** |
| 92 | `ext2.hl` | 每次磁盘读 → **inode 哈希缓存** |
| 93 | `swap.hl` | 基础时钟 → **双链增强时钟** |
| 94 | `smp.hl` | 全局锁 → **Per-CPU 运行队列** |
| 95 | 文档 | 阶段 3 收敛 |

### 阶段 4（迭代 97-101）：调度 + 内存 + 安全
| 迭代 | 模块 | 升级 |
|---|---|---|
| 97 | `sched.hl` | CFS 参数 → **MLFQ 4 级调度器** |
| 98 | `mmap.hl` | 立即分配 → **按需分页 + COW** |
| 99 | `pipe.hl` | 逐字节 → **批量 SPSC 环形缓冲** |
| 100 | `tls.hl` | 空壳 → **8 状态 TLS 1.3 握手** |
| 101 | 文档 | 阶段 4 收敛 |

### 阶段 5（迭代 103-107）：同步 + I/O + 隔离
| 迭代 | 模块 | 升级 |
|---|---|---|
| 103 | `sync.hl` | 空壳 futex → **16 桶哈希等待队列** |
| 104 | `poll.hl` | 水平触发 → **边缘触发 + oneshot + futex 阻塞** |
| 105 | `cgroup.hl` | 被动记账 → **CPU/内存/IO 强制执行 + OOM** |
| 106 | `bpf.hl` | 新建 — **eBPF 寄存器 VM + 5 钩子点** |
| 107 | 文档 | 阶段 5 收敛 |

## 阶段 6 推进（迭代 109-120）

| 迭代 | 模块 | 目标 | 状态 |
|---|---|---|---|
| 109 | `linker.hl` + pipeline | 链接器二次扫描 + stdlib 零警告 | ✅ |
| 110 | `kinterp.hl` | IR 虚拟机执行引擎 | ✅ |
| 111 | `posix.hl` + `usermode.hl` | `execve` + 用户栈 + ring3 跳转 | ✅ |
| 112 | `quic.hl` | QUIC v1 传输协议 | ✅ |
| 113 | `task.hl` + `posix.hl` | `ZOMBIE` 生命周期 + `waitpid(WNOHANG)` | ✅ |
| 114 | `pty.hl` | PTY 真实读写修复 + attach/detach/status | ✅ |
| 115 | 文档 | 阶段 6 文档收敛 | ✅ |
| 116 | `kernel_entry.hl` | 内核自举原型 — `heval` lex→parse→eval | ✅ |
| 117 | `tcp.hl` + `kernel_entry.hl` | TCP 回环自测 — 完整 3-way + data + close | ✅ |
| 118 | `dns.hl` + `kernel_entry.hl` | DNS 回环自测 — 查询→解析→缓存→命中→过期→static | ✅ |
| 119 | `advanced_verify.hl` + commands + gate | eBPF / TLS / QUIC 从源码存在→已验证接入 | ✅ |
| 120 | `kmod.hl` + commands | 内核热补丁 — 64 模块槽 + 256 trampoline + 原子热替换 | ✅ |

## 下一步

### 远期（迭代 131+）
- 文件管理器（`ui_files.hl`）
- 设置中心（`ui_settings.hl`）
- 音频管道（audio→mixer）— AC97 PCM 播放
- GPU 2D 加速 — framebuffer 硬件 blit

## 阶段 7：UI 桌面环境（迭代 125-130）✅

| 迭代 | 模块 | 目标 | 状态 |
|---|---|---|---|
| 125 | `ui_theme.hl` | 统一视觉基线（Slate 配色系统） | ✅ |
| 126 | `wm.hl` | 窗口交互（焦点/提升/拖拽/关闭/最小化） | ✅ |
| 127 | `ui_controls.hl` + `ui_terminal.hl` | 控件系统 + 图形终端 | ✅ |
| 128 | `ui_dialog.hl` + `ui_desktop.hl` | 模态对话框 + 桌面编排层 | ✅ |
| 129 | `wm.hl` + `ui_installer.hl` | 窗口标题文字 + 5 步图形安装器 | ✅ |
| 130 | `ui_sysmon.hl` + `ui_notify.hl` | 系统监控 + Toast 通知 + IPC 完善 | ✅ |

## 阶段 8：模块大扩展（迭代 131-246）✅

通过 116 次持续迭代，系统模块从 130 个扩展到 232 个，每次迭代添加 3 个新模块：

**网络协议扩展**（~30 个迭代）：
- HTTP/HTTPS、WebSocket、Telnet
- SMTP、POP3、IMAP、IRC、FTP
- NTP、MQTT、RADIUS、LDAP
- SIP、RTSP、STUN、RTP、SOCKS
- DHCP Server、QUIC（已有）

**压缩算法全覆盖**（~10 个迭代）：
- LZ4、Huffman、RLE（基础压缩）
- ZLIB、LZMA、Bzip2（经典算法）
- Snappy、Zstd、Brotli（现代算法）

**加密算法完备化**（~20 个迭代）：
- **对称加密**：AES、ChaCha20、SM4（国密）
- **非对称加密**：RSA、Ed25519
- **哈希函数**：MD5、SHA1、SHA256、BLAKE2、SM3（国密）、xxHash（非加密）、SipHash（防 DoS）
- **MAC**：HMAC、Poly1305
- **密码哈希**：Bcrypt、Scrypt、Argon2、PBKDF2

**序列化格式**（~8 个迭代）：
- Protocol Buffers、Apache Avro、CBOR、ASN.1、MessagePack

**编码格式**（~10 个迭代）：
- Base64、Base32、Hex、URL
- Quoted-Printable、UUencode
- PEM、JWT

**文件格式**（~6 个迭代）：
- BMP、GIF、WAV
- CPIO、TAR

**应用功能**（~15 个迭代）：
- SQLite 数据库
- Diff、INI 解析、CSV 解析
- Profiler、Ping、Traceroute
- Semaphore、Cron、Calendar
- RSS 解析

**阶段成果**：
- 模块数：130 → 232（增长 78%）
- Shell 命令：68 → 580（增长 753%）
- 代码行数：46,499 → ~80,300（增长 73%）
- 功能覆盖：从基础 OS 到完整生态系统

## 当前推荐执行顺序

```powershell
.\hl-bootstrap.cmd test
powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1
```

## 相关文件

- `PROJECT_STATUS.md`
- `CHANGELOG.md`
- `PROJECT_ADVANCEMENT_PLAN.hl`
- `COMPILER_PIPELINE_STRATEGY.hl`
