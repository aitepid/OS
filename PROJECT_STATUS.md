# HicOS Project Status

## 版本定位

当前仓库处于 `v6.0` 发布线之后、迭代 101（阶段 4 收敛）里程碑。

## 本轮已核实状态（迭代 101 重新采集）

### 仓库规模

| 指标 | 当前值 |
|---|---:|
| 活跃 `.hl` 文件 | 290 |
| H-L 总行数 | 70,693 |
| `bare-kernel/hl/` 内核模块 | 114 |
| `kernel_entry.hl` 行数 | 9,410 |
| `kernel_entry.hl` 函数数 | 301 |
| `scripts/*.ps1` | 22 |
| PS1 总行数 | 8,646 |
| `shell.hl` 命令数 | 63 + pipe |

### 迭代 101 门禁结果

| 验证项 | 结果 |
|---|---|
| `hl-bootstrap build` | ✅ 114 模块编译 + 镜像重建 |
| `validate-workspace` | ✅ 290 HL / 114 模块 |
| `boot-readiness` | ✅ 启动链 + 内核初始化 |
| `image-layout-readiness` | ✅ MBR 签名 + 扇区布局 |
| `runtime-path-readiness` | ✅ IDT/PIT/KBD + SYSCALL + 网络 |
| `qemu-smoke` | ✅ BIOS 启动 + 串口输出 |

### 产物尺寸（迭代 101 实测）

| 产物 | 大小 |
|---|---:|
| `hicos-hl.img`（BIOS） | 155,648 字节 |
| `hicos-uefi.img`（UEFI） | 34,603,008 字节 |
| `kernel.bin` | 23,183 字节 |

## 迭代 81-101 算法升级总汇（阶段 1+2+3+4）

| 阶段 | 迭代 | 模块 | 升级 | 复杂度 |
|---|---|---|---|---|
| 1 | 81 | `page_alloc.hl` | 位图 → 伙伴系统 | alloc O(n)→O(1) |
| 1 | 82 | `kmalloc.hl` | 首次适配 → 分级空闲链表 | alloc/free O(n)→O(1) |
| 1 | 83 | `block_cache.hl` | 线性扫描 → 哈希+LRU 双链 | lookup O(n)→O(1) |
| 1 | 84 | `hilbert_alloc.hl` | 插入排序 → 归并排序 | init O(n²)→O(n log n) |
| 2 | 86 | `tcp.hl` | 无流控 → Reno 拥塞控制+RTT | 新增 |
| 2 | 87 | `dns.hl` | 无缓存 → TTL 哈希缓存 | resolve O(query)→O(1) |
| 2 | 88 | `vfs.hl` | 线性匹配 → Trie 前缀树 | resolve O(n)→O(depth) |
| 3 | 91 | `arp.hl`+`net.hl` | 线性扫描 → 哈希表 | lookup O(n)→O(1) |
| 3 | 92 | `ext2.hl` | 每次磁盘读 → inode 哈希缓存 | read O(disk)→O(1) |
| 3 | 93 | `swap.hl` | 基础时钟 → 双链增强时钟 | 单指针→active/inactive |
| 3 | 94 | `smp.hl` | 全局调度锁 → Per-CPU 运行队列 | O(contention)→O(1) |
| 4 | 97 | `sched.hl` | CFS 参数 → MLFQ 4 级调度器 | 新增 |
| 4 | 98 | `mmap.hl` | 立即分配 → 按需分页+COW | 新增 |
| 4 | 99 | `pipe.hl` | 逐字节 → 批量 SPSC 环形缓冲 | 新增 |
| 4 | 100 | `tls.hl` | 空壳 → 8 状态 TLS 1.3 握手 | 新增 |

## 三层架构现状

| 层级 | 载体 | 说明 |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | BIOS 镜像生成链 |
| B | `hl-bootstrap.hl` | 自举编译器/解释器/工具链 |
| C | `bare-kernel/hl/*.hl` | 114 内核模块 → `kernel.bin` |

## 产物增长（四阶段累计）

| 指标 | 阶段 1 前 | 阶段 4 后 | 增长 |
|---|---:|---:|---|
| `kernel.bin` | 18,058 B | 23,183 B | +28% |
| `hicos-hl.img` | 150,528 B | 155,648 B | +3.4% |
| H-L 总行数 | 42,187 | 70,693 | +67.6% |

## 下一阶段建议（阶段 5：迭代 103+）

- `futex.hl` 用户态快速互斥量
- `epoll.hl` 事件驱动 I/O 多路复用
- `cgroup.hl` 资源限制与隔离
- `bpf.hl` 内核可编程过滤
- 第五轮发布收敛
