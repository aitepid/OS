# HicOS Roadmap

## 当前同步基线（迭代 95 重新采集）

- `290` 个活跃 `.hl` 文件（69,367 行）
- `114` 个内核模块
- `22` 个 PowerShell 脚本（8,646 行）
- 构建/测试主入口：`scripts/hl-bootstrap-build-test.ps1`
- 最近完成迭代：`91`-`95`

## 已完成阶段

### 阶段 0（迭代 73-80）：Shell / 命令迭代
- 环境变量 / 信号 / 历史 / 方向键
- hostname / uname / date / netstat / arp
- Shell pipe + grep
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
| 95 | 文档 | 阶段 3 收敛（本次） |

## 下一阶段

### 阶段 4（迭代 97-101）：调度 + 内存 + 安全
| 迭代 | 模块 | 目标 |
|---|---|---|
| 97 | `scheduler.hl` | 多级反馈队列 |
| 98 | `mmap.hl` | 按需映射 + COW |
| 99 | `pipe.hl` | 环形缓冲区升级 |
| 100 | `tls.hl` | TLS 1.3 握手状态机 |
| 101 | 文档 | 阶段 4 收敛 |

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
