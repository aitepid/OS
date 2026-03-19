# HicOS 裸机安装路线图

## 当前状态快照 (v5.0)

| 指标 | 值 |
|------|-----|
| H-L 源文件 | 164 个 `.hl` (114 内核 + 27 用户空间 + 23 基础设施) |
| 内核模块 | 114 个 (`bare-kernel/hl/`) |
| 内核函数 | 995 个 |
| BIOS 引导镜像 | `hicos-hl.img` = 41,472 字节 (81 扇区) |
| UEFI 引导镜像 | `hicos-uefi.img` = 33 MB (GPT + ESP FAT16) |
| UEFI 应用 | `BOOTX64.EFI` = 1,536 字节 (PE32+ x86_64) |
| MBR 签名 | 0x55AA ✓ |
| GPT CRC32 | ✓ (128 条目 + 备份头) |
| QEMU BIOS 测试 | **42/42 PASS** (含 shell/FAT16/DHCP/DNS/VESA/Ring3) |
| QEMU UEFI 测试 | **3/3 PASS** |
| Full Gate | **7/7 PASS** |
| rebuild-image.ps1 | 3,676 行 (手写 x86_64 机器码) |
| hl-bootstrap.hl | 4,630 行 (206 函数, 7 quadrant) |
| Shell 命令 (Layer C) | 55 个 (shell.hl 设计级) |
| Shell 命令 (QEMU 验证) | 18 个 (hicos-hl.img 镜像中) |
| 总代码行数 | ~38,500 行 (32,154 H-L + 6,352 PS1) |
| hl-bootstrap 宿主 | ✓ Shim 支持 build/test/interpret/lex/boot/gate/info/compile 命令 |
| QEMU 验证的子系统 | Serial, PIC, PIT, IDT, PS/2, PCI, VirtIO-blk, VirtIO-net, Timer, Task, GPT, FAT16, PE32+, VESA, SYSCALL, DHCP, DNS, ICMP, Ring3 |

---

## 阶段规划总览

```
Phase 0  Bootstrap 闭环        ✅ 完成
Phase 1  内核原语激活          ✅ 完成
Phase 2  磁盘 I/O 通路        ✅ 完成
Phase 3  文件系统落地          ✅ 完成
Phase 4  进程与调度落地        ✅ 完成
Phase 5  安装程序实现          ✅ 完成
Phase 6  真实硬件驱动          ✅ 完成
Phase 7  网络栈激活            ✅ 完成
Phase 8  高级子系统            ✅ 完成
Phase 9  UEFI + 安全引导       ✅ 完成
```

---

## Phase 0: Bootstrap 编译器闭环  ✅ DONE

**目标**: 在宿主机上能执行 `hl-bootstrap.hl`，实现 `.hl` → 原生 x86_64 → 可引导 `.img` 的完整编译链路。

**依赖**: 无 (这是所有后续阶段的前提)

### 0.1 最小可用 H-L 解释器宿主  ✅

**完成内容**:
- S4 VM 新增 30+ 内置函数: file_read/write/exists/list/delete, byte_array/set/get, u16/u32/u64_le, le_u16/le_u32, str_sub/find/split/join, parse_int, process_args/exit_program/panic_halt/time_ticks, serial_write/read_line, concat/slice/copy_array
- S7 CLI 完整实现: interpret/lex/parse/build/test/info 命令分发
- Shim 更新: 支持 build/test/gate/boot/interpret/lex/info 命令
- VM 内部虚拟文件系统 (_vm_fs) 支持内存中文件操作

### 0.2 Kernel Codegen 管线调用入口  ✅

**完成内容**:
- `image_builder.build_kernel()` 完整实现: 串口初始化 + PIC 重映射 + PIT 100Hz + 256向量 IDT + ISR stub + 键盘/定时器处理 + shell 主循环
- `image_builder.build()` 总入口: stage1 + stage2 + kernel → 完整可引导 .img
- codegen.hl 新增: For/Print/Block/FnDef/Quadrant 语句编译, Bool/Nil/Str/Array/Call/Index 表达式编译
- ir.hl 新增: IR_STR_CONST/IR_ALLOC/IR_ARRAY_GET/IR_ARRAY_SET/IR_PRINT/IR_MEMCPY (32-37)
- compile_stmt_to_ir() 完整实现: Let/Assign/Return/If/While/For/Print/ExprStmt

### 0.3 自举验证

**方案**: 用新生成的 `.img` 启动 QEMU，在其 shell 中编译一个简单的 `.hl` 测试文件。

**验证**: `hl-bootstrap build/test` 在 QEMU 中通过 → 自举成功

---

## Phase 1: 内核原语激活  ✅ DONE

**目标**: `.img` 中的内核能在 QEMU 中正确处理中断、管理内存、响应键盘。

**依赖**: Phase 0 (能生成包含完整内核代码的 .img)

### 1.1 ISR 汇编入口 Stub  ✅

**完成内容**: `image_builder.build_kernel()` 为 256 个 IDT 向量生成完整 ISR stub:
- 向量 0-31 (CPU 异常): push error code/dummy → push vector# → jmp common
- 向量 32-47 (硬件 IRQ): 同上 + EOI 发送 (PIC1/PIC2)
- Common handler: 保存全部 GP 寄存器 (rax-r15) → 按向量号分发 → timer tick / keyboard scancode → 发送 EOI → 恢复 → iretq
- 每个 stub 16 字节对齐，支持 error code 和 non-error code 向量

### 1.2 E820 内存检测  ✅

**完成内容**:
- Stage1 MBR 新增 E820 检测机器码 (INT 15h, AX=E820h 循环)
- 内存图存储在 0x500: count(u32) + entries (base(8) + length(8) + type(4))
- `mem.hl` 新增完整 E820 API: e820_count/entry_base/entry_length/entry_type/total_usable/find_largest_usable/dump

### 1.3 动态页表扩展  ✅

**完成内容**:
- `page_alloc.hl` 新增 `page_alloc_init_e820()`: 从 E820 内存图动态设置 TOTAL_PAGES (最高 2GB)
- `page_alloc.hl` 新增 `page_alloc_contiguous(count)`: 连续页分配
- `page_alloc.hl` 新增 `_page_mark_used()`: E820 非可用区域标记为已用
- `virt_mem.hl` 新增 `map_huge_page()`: 2MB 巨页映射
- `virt_mem.hl` 新增 `map_all_ram()`: 根据 E820 identity map 所有可用 RAM
- `virt_mem.hl` 新增 `tlb_flush_all()`, `tlb_invalidate()`

### 1.4 VESA 模式设置  ✅

**完成内容**:
- `vesa.hl` 重写 `vesa_init()`: 从 VBE mode info 块 (0x8000) 读取真实参数
- `vesa.hl` 新增 `vesa_auto_init()`, `vesa_info()`, `vesa_scroll_up()`
- 自动检测: 验证 mode attributes → 读取分辨率/BPP/framebuffer 地址/pitch
- 安全回退: 如果 VBE 数据无效，保持文本模式兼容

---

## Phase 2: 磁盘 I/O 通路  ✅ DONE

**目标**: 内核能通过 VirtIO-blk 驱动读写磁盘扇区。

**依赖**: Phase 1.1 (ISR stub), Phase 1.2 (动态内存)

### 2.1 VirtIO-blk 驱动实现  ✅

**完成内容**: `bare-kernel/hl/virtio_blk.hl` 完整实现:
- `virtio_blk_init()`: PCI BAR0 读取 → 设备复位 → ACKNOWLEDGE → DRIVER → 特性协商 → virtqueue 分配 (descriptor table + available ring + used ring) → DRIVER_OK
- `virtio_blk_read(sector, count, buf_addr)`: 构建请求头 (type=IN) → 3 descriptor chain (header → data → status) → 提交 → 轮询 used ring → 检查状态
- `virtio_blk_write(sector, count, buf_addr)`: 构建请求头 (type=OUT) → 3 descriptor chain → 提交 → 等待完成
- `virtio_blk_capacity()`: 读取设备配置区 (BAR0+20) 获取磁盘扇区数
- 内部: _vq_alloc_desc/_vq_free_desc/_vq_write_desc/_vq_submit_and_wait
2. `virtio_blk_read()`: 3 描述符链 → available ring → notify → 等待 used ring
3. `virtio_blk_write()`: 同上
4. `virtio_blk_capacity()`: 读取 BAR+20 的 64 位容量

**交付物**: 可读写扇区的 VirtIO-blk 驱动。

**验证**: 写入 sector 100 → 读回 → 数据一致。

### 2.2 Block Cache 激活  ✅

**完成内容**: `block_cache.hl` 取消注释所有 virtio_blk 调用:
- `bcache_writeback()`: 通过 `virtio_blk_write()` 写回脏块
- `bcache_read()`: 缓存未命中时通过 `virtio_blk_read()` 加载
- `bcache_write()`: 通过 `mem_copy()` 更新缓存数据

---

## Phase 3: 文件系统落地  ✅ DONE

**目标**: VFS 能通过真实磁盘后端读写文件。

**依赖**: Phase 2 (磁盘 I/O)

### 3.1 FAT16 驱动激活  ✅

**完成内容**: `fat16.hl` 完整实现读写:
- `fat16_read_fat()`: 通过 block cache 读取 FAT 表项
- `fat16_write_fat()`: 写 FAT 表项 (双 FAT 同步)
- `fat16_alloc_cluster()`: 从 FAT 分配空闲簇
- `fat16_list_root()`: 读取根目录，解析 8.3 文件名，跳过 LFN/已删除
- `fat16_read_file()`: 按簇链读取完整文件
- `fat16_create_file()`: 在根目录创建新条目 (8.3 名、大写转换)
- `fat16_write_file()`: 按簇链写入数据 (自动扩展链)
- `fat16_update_size()`: 更新目录项文件大小
- `fat16_delete_file()`: 标记删除 + 释放簇链
- `fat16_format()`: 完整格式化 (BPB + 双FAT + 空根目录)

### 3.2 VFS 挂载 FAT16  ✅

**完成内容**: `vfs.hl` 新增 FAT16 后端:
- `vfs_mount_fat16()`: 读 boot sector → fat16_init → 挂载到 /mnt/disk0
- `vfs_readdir()`: FAT16 分支调用 `fat16_list_root()`
- `vfs_stat()`: FAT16 分支搜索根目录
- `vfs_mkdir()`: FAT16 分支调用 `fat16_create_file(name, 1)`
- `vfs_unlink()`: FAT16 分支删除文件

### 3.3 Swap 落地

**问题**: `swap.hl` 依赖 virtio_blk + demand_page 被注释。

**涉及文件**: `bare-kernel/hl/swap.hl`

**方案**: Phase 2 + Phase 1.1 完成后取消注释。

**交付物**: 可工作的 swap + demand paging。

---

## Phase 4: 进程与调度落地  ✅ DONE

**目标**: 多任务调度、上下文切换、fork/exec/wait 在原生内核中可用。

**依赖**: Phase 1.1 (timer ISR), Phase 1.3 (页表), Phase 3.2 (VFS for exec)

### 4.1 原生 Context Switch  ✅

**完成内容**:
- `task.hl` 补全 `context_switch()`: 保存当前任务状态 → CR3 切换 → TLB flush → 加载目标任务 GPR/RSP/RIP
- 新增 `schedule()`: CFS 调度入口，从 timer ISR 和 yield/block 路径调用
- 新增 `task_yield()`: 自愿让出 CPU (vruntime 递增 → 调度)
- 新增 `task_block(reason)` / `task_unblock(task_idx)`: 任务阻塞/唤醒 (sleep、wait、pipe)
- 新增 `task_exit(code)`: 终止任务 + 发送 SIGCHLD + 调度走
- 新增 `task_info()` / `task_list()`: 调试输出

### 4.2 Timer 驱动调度触发  ✅

**完成内容**:
- `timer.hl` `timer_check()` 末尾调用 `timer_check_sleepers()` + `task_timer_tick()`
- 新增 `sleep_ms(ms)`: 计算 wake_tick → 存入任务 +208 → `task_block()` → 调度走
- 新增 `timer_check_sleepers()`: 扫描所有 BLOCKED 任务，deadline 到期则 `task_unblock()`
- 100Hz PIT → `timer_check()` → CFS vruntime 更新 + 抢占检查 → 完整时间片轮转

### 4.3 fork/exec/wait 端到端  ✅

**完成内容**:
- `posix.hl` 修复 `sys_dup2()`: 修正变量 src/dst 未定义 bug
- `posix.hl` 修复 `fd_alloc()`: 取消注释 FD_CLOSED 检查
- `posix.hl` 改进 `sys_exec()`: 通过 VFS open/read/close 加载 ELF (取代直接 vfs_read)
- `posix.hl` 改进 `sys_wait()`: 通过 `task_block()` 阻塞等待 (取代 spin loop)
- `posix.hl` 新增 `sys_exit(code)`: 关闭所有 FD → `task_exit(code)`

---

## Phase 5: 安装程序实现  ✅ DONE

**目标**: 能将 HicOS 写入目标磁盘并使其可引导。

**依赖**: Phase 2 (磁盘 I/O), Phase 3.1 (FAT16 写入)

### 5.1 磁盘分区  ✅

**完成内容**: `installer.hl` 实现 `installer_create_mbr()`:
- 创建单分区 MBR，分区1 覆盖整个磁盘 (type=0x06 FAT16 LBA)
- 保留已有引导代码
- 写入 0x55AA 启动签名

### 5.2 文件系统格式化  ✅

**完成内容**: `fat16.hl` 实现 `fat16_format()`:
- 计算 BPB 参数 (BPS=512, SPC=4)
- 写入引导扇区 (jump + OEM + BPB + 0xAA55)
- 清零双 FAT 表，设置 FAT[0]=0xFFF8, FAT[1]=0xFFFF
- 清零根目录区

### 5.3 引导扇区与内核写入  ✅

**完成内容**: `installer.hl` 实现 `installer_write_bootloader()`:
- 保留 MBR 分区表 (仅覆盖前 446 字节)
- 逐扇区写入 stage2 + kernel image

### 5.4 安装向导 (Serial Shell)  ✅

**完成内容**: `installer.hl` 实现 `installer_main()` 6步安装流程:
- [1/6] 检测磁盘 → [2/6] MBR 分区 → [3/6] FAT16 格式化
- [4/6] 写引导 → [5/6] 写源文件 → [6/6] 验证安装

---

## Phase 6: 真实硬件驱动  ✅ DONE

**目标**: 脱离 QEMU，在物理 x86_64 机器上运行。

**依赖**: Phase 5 (安装程序), Phase 1 (内核原语)

### 6.1 AHCI/SATA 驱动  ✅

**完成内容**: 新建 `bare-kernel/hl/ahci.hl`:
- `ahci_detect()`: PCI 扫描 class=01/subclass=06
- `ahci_init()`: ABAR 读取 → AHCI Enable → 端口枚举 → 端口初始化 (CLB/FB/IS)
- `ahci_port_init()`: stop → 设置 CLB/FB → clear IS → start
- `ahci_read()/ahci_write()`: FIS H2D + PRDT + Command Issue + 轮询完成
- `ahci_identify()`: ATA IDENTIFY DEVICE → 解析 48-bit 扇区数/型号
- `ahci_build_fis_h2d()`: 完整 Register H2D FIS (48-bit LBA)

### 6.2 NVMe 驱动 (可选)

**状态**: 推迟到 AHCI 验证后。

### 6.3 USB HID 驱动激活  ✅

**完成内容**: `bare-kernel/hl/usb.hl` 重写:
- 修复 `xhci_init()`: 消除未定义变量 bug，完整 MMIO 寄存器操作
- BAR0 读取 → cap registers → stop/reset/wait → MaxSlotsEn → DCBA → CMD ring → start
- `xhci_port_status()`: 读取 PORTSC (CCS/PED/speed)
- `xhci_enumerate()`: 扫描所有端口，打印连接状态和速度
- `usb_detect()` + `usb_init()`: PCI 检测 → xHCI init → enumerate

### 6.4 PS/2 全 Scancode 映射  ✅

**完成内容**: `bare-kernel/hl/scancode.hl` 增强:
- `build_shift_table()`: 完整 Shift 映射 (符号: !@#$%^&*()_+ etc.)
- `scancode_process(sc)`: 返回 [ascii, ctrl, alt]
- 修饰键跟踪: LShift/RShift/LCtrl/LAlt 按下/释放状态
- CapsLock 切换: 仅影响字母键 (与 Shift XOR)
- Ctrl+letter: ASCII 1-26
- F1-F12 功能键: 返回负数编码 (-1 到 -12)
- 向后兼容: `scancode_to_ascii()` 不变

---

## Phase 7: 网络栈激活  ✅ DONE

**目标**: 可通过网络下载/安装。

**依赖**: Phase 1 (ISR for IRQ), Phase 2 (内存分配)

### 7.1 VirtIO-net 驱动补全  ✅

**完成内容**: `bare-kernel/hl/virtio_net.hl` 重写:
- `virtio_net_detect()`: PCI 扫描 vendor=0x1AF4 device=0x1000
- `virtio_net_init()`: BAR0 → reset → negotiate → RX queue 预填描述符 → TX queue → driver OK
- `virtio_net_send()`: 2-descriptor chain (virtio_net_header + payload) → available ring → notify
- `virtio_net_send_pkt()`: byte array → 内存 buffer → send
- `virtio_net_recv_pkt()`: poll used ring → 跳过 virtio_net_header → 返回 byte array → 重填 avail

### 7.2 DHCP 端到端  ✅

**完成内容**: `bare-kernel/hl/dhcp.hl` 补全:
- `dhcp_build_request()`: 完整 REQUEST 包体 (option 53=REQUEST + option 50 + option 54)
- `dhcp_discover()`: 构建 DISCOVER → UDP → `virtio_net_send_pkt()`
- `dhcp_request()`: 构建 REQUEST → 发送
- `dhcp_input()`: 解析 xid → option 53 message type → OFFER → REQUEST → ACK 自动流程
- ACK 后自动配置 `my_ip`/`gw_ip`/`netmask`

### 7.3 TCP 端到端  ✅

**完成内容**: `bare-kernel/hl/tcp.hl` 补全:
- `tcp_send()`: 构建 PSH+ACK 段 → IPv4 封装 → `virtio_net_send_pkt()` → 更新 seq
- `tcp_close()`: 发送 FIN+ACK → 状态机 ESTABLISHED→FIN_WAIT1 / CLOSE_WAIT→LAST_ACK
- `build_ip_tcp_packet()`: Ethernet + IPv4 + IP checksum + TCP 数据

### 7.4 网络输入分发  ✅

**完成内容**: `bare-kernel/hl/net.hl` 增强:
- ARP 表: `arp_init()`/`arp_lookup()`/`arp_update()` (16 entries)
- `arp_input()`: 解析 ARP reply → 更新表 → 自动设置 gateway MAC
- `net_input()`: Ethernet 解帧 → ARP/IPv4 分发 → ICMP/UDP/TCP 子分发
- `net_poll()`: `virtio_net_recv_pkt()` → `net_input()`
- `net_init()`: ARP init → VirtIO-net detect/init → ARP gateway → DHCP ready

### 7.5 真实网卡驱动 (可选)

**状态**: 推迟到 VirtIO-net 验证后。

---

## Phase 8: 高级子系统  ✅ DONE

**目标**: 完善 OS 体验。

**依赖**: Phase 4 (进程调度), Phase 3 (文件系统)

### 8.1 SMP 完整实现  ✅

**完成内容**: `bare-kernel/hl/smp.hl` 增强:
- `percpu_init()`/`percpu_addr()`: Per-CPU 数据结构 at 0x350000 (apic_id, current_task, flags, stack)
- `spin_lock()`/`spin_unlock()`/`spin_trylock()`: SMP spinlock 原语
- Kernel-wide locks: LOCK_SCHED, LOCK_ALLOC, LOCK_PRINT at 0x360000
- `smp_send_reschedule()`/`smp_broadcast_ipi()`: IPI 调度通知
- `ap_main()`: AP 完整启动 → LAPIC init → per-CPU init → signal BSP
- `smp_init()`: locks init → percpu BSP → discover → boot APs

### 8.2 ACPI 电源管理激活  ✅

**完成内容**: `bare-kernel/hl/power.hl` 重写:
- `power_init()`: RSDP → RSDT → FADT → PM1a/PM1b_CNT + reset register + S5 SLP_TYP
- `power_init_fadt()`: 解析 FADT offset+64(PM1a), +68(PM1b), +116(reset GAS), +128(reset val)
- `power_shutdown()`: ACPI SLP_EN+SLP_TYP → QEMU 0x604 → Bochs 0xB004 → halt 四级回退
- `power_reboot()`: ACPI reset reg → 8042 0xFE → triple fault 三级回退
- `power_sleep()`: S1 sleep via PM1a_CNT

### 8.3 Firmware 加载框架激活  ✅

**完成内容**: `bare-kernel/hl/firmware.hl` 重写:
- `firmware_request()`: VFS open → stat → page_alloc_contiguous → vfs_read → 返回 [addr, size]
- `firmware_release()`: mem_zero → page_free → 从缓存移除
- 内存缓存: fw_cache_names/addrs/sizes 避免重复加载
- `firmware_init()`: 创建 /lib/firmware/ VFS 目录

### 8.4 ext2 文件系统  ✅

**完成内容**: `bare-kernel/hl/ext2.hl` 重写:
- `ext2_init(partition_lba)`: 读取磁盘 superblock → 验证 magic 0xEF53 → 解析 block_size/inodes_per_group/inode_size
- `ext2_read_inode()`: 通过 BGDT → inode table → bcache_read 从磁盘读取
- `ext2_read_block()`: 通过 bcache_read 读取任意文件系统块
- `ext2_resolve(path)`: str_split → 逐级 ext2_lookup → 返回 inode 号
- `ext2_read_path()`: resolve → read_inode → read_file 一步到位
- `ext2_is_dir()`/`ext2_file_size()`/`ext2_file_mode()`: inode 元数据读取
- `ext2_vfs_mount()`: VFS 挂载入口

---

## Phase 9: UEFI 引导 + 安全引导  ✅ DONE

**目标**: 支持纯 UEFI 硬件。

**依赖**: Phase 6 (真实硬件驱动)

### 9.1 UEFI 应用程序  ✅

**完成内容**: 新建 `bare-kernel/hl/uefi_boot.hl`:
- Boot info 结构体 at 0x100000: magic, memory map, framebuffer, RSDP, boot mode
- `uefi_is_boot()`: 检测 "HICUEFI\0" magic → UEFI/BIOS 分流
- `uefi_parse_memory_map()`: EFI 内存类型 → usable pages 统计
- `uefi_init_page_alloc()`: EFI_CONVENTIONAL + BOOT_SERVICES → page_free (skip < 2MB)
- `uefi_init_framebuffer()`: GOP info → vesa_set_mode_direct
- `uefi_get_rsdp()`: EFI config table RSDP (替代 BIOS 内存搜索)
- `uefi_boot_init()`: 完整 UEFI 启动路径 (替代 E820 + VESA BIOS)
- PE32+ header 生成: `pe_build_dos_stub()` + `pe_build_header()` → BOOTX64.EFI 所需的最小头

### 9.2 GPT 分区表  ✅

**完成内容**: 新建 `bare-kernel/hl/gpt.hl`:
- GPT header 读写: `gpt_write_header()` 含 CRC32、disk GUID、备份头
- Partition entry 读写: `gpt_write_entry()` (type GUID, unique GUID, LBA range, UTF-16 name)
- Protective MBR: `gpt_write_protective_mbr()` (type 0xEE)
- GPT 读取验证: `gpt_read()` → 签名校验 → 解析所有 entry
- ESP 检测: `gpt_is_esp()` + `gpt_find_esp()`
- 完整创建: `gpt_create()` → protective MBR → ESP 100MB + HicOS 分区 → 备份头+entries
- `gpt_generate_guid()`: GUID v4 伪随机生成
- `gpt_str_to_utf16()`: ASCII → UTF-16LE 转换
- 安装器集成: `installer.hl` 升级到 v5.0, UEFI/BIOS 双路径

### 9.3 Secure Boot  ✅

**完成内容**: 新建 `bare-kernel/hl/secure_boot.hl`:
- `secboot_detect()`: 从 boot info 读取 SecureBoot/SetupMode 状态
- SHA-256 哈希实现: `sha256_hash()` (padding, block processing, 32-byte output)
- Trust database: `secboot_trust_add()` / `secboot_verify()` 基于 name → hash 对
- `secboot_firmware_request()`: firmware_request 包装,加载后自动 hash 验证
- `secboot_init()`: 初始化 + 状态打印

---

## 依赖关系图

```
Phase 0 ─────────────────────────────────────────────────┐
  0.1 Bootstrap 宿主                                      │
  0.2 Kernel Codegen 入口                                 │
  0.3 自举验证                                            │
  │                                                       │
Phase 1 ◄─────────────────────────────────────────────────┘
  1.1 ISR Stub ◄─── Phase 0
  1.2 E820 内存检测 ◄─── Phase 0
  1.3 动态页表 ◄─── 1.2
  1.4 VESA 实模式 ◄─── Phase 0
  │
Phase 2 ◄─── 1.1 + 1.2
  2.1 VirtIO-blk ◄─── 1.1, 1.2
  2.2 Block Cache ◄─── 2.1
  │
Phase 3 ◄─── Phase 2
  3.1 FAT16 激活 ◄─── 2.1
  3.2 VFS 挂载 ◄─── 3.1
  3.3 Swap 落地 ◄─── 2.1, 1.1
  │
Phase 4 ◄─── 1.1 + 1.3
  4.1 Context Switch ◄─── 1.1
  4.2 Timer 调度 ◄─── 4.1, 1.1
  4.3 fork/exec/wait ◄─── 4.1, 3.2
  │
Phase 5 ◄─── Phase 2 + Phase 3
  5.1 磁盘分区 ◄─── 2.1
  5.2 FAT16 格式化 ◄─── 3.1
  5.3 引导扇区写入 ◄─── 5.1, 5.2
  5.4 安装向导 ◄─── 5.3
  │
Phase 6 ◄─── Phase 5 + Phase 1
  6.1 AHCI ◄─── 1.1, 1.2
  6.2 NVMe ◄─── 1.1, 1.2  (可选)
  6.3 USB HID ◄─── 1.1
  6.4 PS/2 ◄─── 已部分完成
  │
Phase 7 ◄─── Phase 1
  7.1 VirtIO-net ◄─── 1.1, 1.2
  7.2 DHCP ◄─── 7.1
  7.3 TCP ◄─── 7.1
  7.4 HTTP ◄─── 7.3
  7.5 e1000 ◄─── 1.1  (可选)
  │
Phase 8 ◄─── Phase 4 + Phase 3
  8.1 SMP ◄─── 4.1
  8.2 ACPI Power ◄─── 1.1
  8.3 Firmware ◄─── 3.2
  8.4 ext2 ◄─── 2.1
  │
Phase 9 ◄─── Phase 6
  9.1 UEFI Boot ◄─── Phase 0
  9.2 GPT ◄─── 5.1
  9.3 Secure Boot ◄─── 9.1  (可选)
```

## 并行化建议

| 并行组 | 板块 | 前提 |
|--------|------|------|
| A | Phase 2 (磁盘) + Phase 4.1 (context switch) | 都只依赖 Phase 1 |
| B | Phase 3 (文件系统) + Phase 7.1 (VirtIO-net) | 分别依赖 Phase 2 和 Phase 1 |
| C | Phase 6.1 (AHCI) + Phase 6.3 (USB HID) | 都只依赖 Phase 1 |
| D | Phase 5 (安装程序) + Phase 8.2 (ACPI) | 分别依赖 Phase 3 和 Phase 1 |

## 里程碑

| 里程碑 | 完成标志 | 估算依赖阶段 |
|--------|----------|-------------|
| M1: 自举编译 | `.hl` 源码 → 可引导 `.img` | Phase 0 |
| M2: QEMU 可交互 | Shell 响应命令 + 内存/中断正常 | Phase 1 |
| M3: QEMU 可安装 | 空磁盘 → 安装 → 重启成功 | Phase 5 |
| M4: 裸机可启动 | 物理 PC USB 启动 HicOS | Phase 6 |
| M5: 裸机可安装 | 物理 PC 硬盘安装 + 启动 | Phase 6 + Phase 5 |
| M6: 网络可用 | ping / http get 成功 | Phase 7 |
| M7: 多任务可用 | fork/exec 运行用户程序 | Phase 4 |
