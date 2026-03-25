# HicOS Roadmap

## 当前同步基线（迭代 119 全量复核）

- `180` 个 `.hl` 文件（47,950 行）：63 根目录 + 117 内核模块
- `22` 个 PowerShell 脚本（9,866 行）
- `hl-bootstrap.hl`：`4,567` 行 | `stdlib.hl`：`1,545` 行
- 内核函数：`1,499` | Shell + 内核命令（去重）：`112`
- 构建/测试主入口：`scripts/hl-bootstrap-build-test.ps1`
- 最近完成迭代：`119`

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

## 阶段 6 推进（迭代 109-119）

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

## 下一步

### 远期（迭代 120+）
- `kmod.hl` 内核热补丁
- 音频管道 / GPU 2D 加速

## 当前推荐执行顺序

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\hl-bootstrap-build-test.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\full-gate.ps1
```

## 相关文件

- `PROJECT_STATUS.md`
- `CHANGELOG.md`
- `PROJECT_ADVANCEMENT_PLAN.hl`
- `COMPILER_PIPELINE_STRATEGY.hl`
