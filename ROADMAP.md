## Update: HL-Bootstrap Transition

As of v4.2, we prioritize hl-bootstrap-build-test.ps1 for the entry of build and test processes. It guarantees Hilbert-Lang purity. Phase 1 compilation pipeline (lexer) has been implemented and is running smoothly. This sets up the project to discard all javascript or other non-Hilbert-Lang compilation dependencies.

# HicOS 瑁告満瀹夎璺嚎鍥?

## 褰撳墠鐘舵€佸揩鐓?(v6.0)

| 鎸囨爣 | 鍊?|
|------|-----|
| H-L 婧愭枃浠?| 176 涓??`.hl` (114 鍐呮牳 + 27 鐢ㄦ埛绌洪棿 + 35 鍩虹璁炬柦) |
| 鍐呮牳妯″潡 | 114 涓?(`bare-kernel/hl/`) |
| 鍐呮牳鍑芥暟 | 1121 涓??|
| BIOS 寮曞闀滃儚 | `hicos-hl.img` = 152,064 瀛楄妭 (297 鎵囧尯) |
| UEFI 寮曞闀滃儚 | `hicos-uefi.img` = 33 MB (GPT + ESP FAT16) |
| UEFI 搴旂敤 | `BOOTX64.EFI` = 1,536 瀛楄妭 (PE32+ x86_64) |
| MBR 绛惧悕 | 0x55AA 鉁?|
| GPT CRC32 | 鉁?(128 鏉＄洰 + 澶囦唤澶? |
| QEMU BIOS 娴嬭瘯 | **65/65 PASS** (鍚?shell/FAT16/DHCP/DNS/VESA/Ring3/HW/Disk/Install/Run/Mem) |
| QEMU UEFI 娴嬭瘯 | **3/3 PASS** |
| Full Gate | **10/10 PASS** |
| rebuild-image.ps1 | 3,798 行 (手写 x86_64 机器码) |
| hl-bootstrap.hl | 4,630 琛?(206 鍑芥暟, 7 quadrant) |
| Shell 鍛戒护 (Layer C) | 60 涓?(shell.hl 璁捐绾? |
| Shell 命令 (QEMU 验证) | 20 个 (层级A) + 30 个 (kernel.bin) |
| 鎬讳唬鐮佽鏁?| ~45,900 琛?(38,082 H-L + 7,773 PS1) |
| hl-bootstrap 瀹夸富 | 鉁?Shim 鏀寔 build/test/interpret/lex/boot/gate/info/compile 鍛戒护 |
| QEMU 楠岃瘉鐨勫瓙绯荤粺 | Serial, PIC, PIT, IDT, PS/2, PCI, VirtIO-blk, VirtIO-net, Timer, Task, GPT, FAT16, PE32+, VESA, SYSCALL, DHCP, DNS, ICMP, Ring3 |

---

## 闃舵瑙勫垝鎬昏

```
Phase 0  Bootstrap 闂幆        鉁?瀹屾垚
Phase 1  鍐呮牳鍘熻婵€娲?         鉁?瀹屾垚
Phase 2  纾佺洏 I/O 閫氳矾        鉁?瀹屾垚
Phase 3  鏂囦欢绯荤粺钀藉湴          鉁?瀹屾垚
Phase 4  杩涚▼涓庤皟搴﹁惤鍦?       鉁?瀹屾垚
Phase 5  瀹夎绋嬪簭瀹炵幇          鉁?瀹屾垚
Phase 6  鐪熷疄纭欢椹卞姩          鉁?瀹屾垚
Phase 7  缃戠粶鏍堟縺娲?           鉁?瀹屾垚
Phase 8  楂樼骇瀛愮郴缁?           鉁?瀹屾垚
Phase 9  UEFI + 瀹夊叏寮曞       鉁?瀹屾垚
```

---

## Phase 0: Bootstrap 缂栬瘧鍣ㄩ棴鐜? 鉁?DONE

**鐩爣**: 鍦ㄥ涓绘満涓婅兘鎵ц `hl-bootstrap.hl`锛屽疄鐜?`.hl` 鈫?鍘熺敓 x86_64 鈫?鍙紩瀵?`.img` 鐨勫畬鏁寸紪璇戦摼璺€?

**渚濊禆**: 鏃?(杩欐槸鎵€鏈夊悗缁樁娈电殑鍓嶆彁)

### 0.1 鏈€灏忓彲鐢?H-L 瑙ｉ噴鍣ㄥ涓? 鉁?

**瀹屾垚鍐呭**:
- S4 VM 鏂板 30+ 鍐呯疆鍑芥暟: file_read/write/exists/list/delete, byte_array/set/get, u16/u32/u64_le, le_u16/le_u32, str_sub/find/split/join, parse_int, process_args/exit_program/panic_halt/time_ticks, serial_write/read_line, concat/slice/copy_array
- S7 CLI 瀹屾暣瀹炵幇: interpret/lex/parse/build/test/info 鍛戒护鍒嗗彂
- Shim 鏇存柊: 鏀寔 build/test/gate/boot/interpret/lex/info 鍛戒护
- VM 鍐呴儴铏氭嫙鏂囦欢绯荤粺 (_vm_fs) 鏀寔鍐呭瓨涓枃浠舵搷浣?

### 0.2 Kernel Codegen 绠＄嚎璋冪敤鍏ュ彛  鉁?

**瀹屾垚鍐呭**:
- `image_builder.build_kernel()` 瀹屾暣瀹炵幇: 涓插彛鍒濆鍖?+ PIC 閲嶆槧灏?+ PIT 100Hz + 256鍚戦噺 IDT + ISR stub + 閿洏/瀹氭椂鍣ㄥ鐞?+ shell 涓诲惊鐜?
- `image_builder.build()` 鎬诲叆鍙? stage1 + stage2 + kernel 鈫?瀹屾暣鍙紩瀵?.img
- codegen.hl 鏂板: For/Print/Block/FnDef/Quadrant 璇彞缂栬瘧, Bool/Nil/Str/Array/Call/Index 琛ㄨ揪寮忕紪璇?
- ir.hl 鏂板: IR_STR_CONST/IR_ALLOC/IR_ARRAY_GET/IR_ARRAY_SET/IR_PRINT/IR_MEMCPY (32-37)
- compile_stmt_to_ir() 瀹屾暣瀹炵幇: Let/Assign/Return/If/While/For/Print/ExprStmt

### 0.3 鑷妇楠岃瘉

**鏂规**: 鐢ㄦ柊鐢熸垚鐨?`.img` 鍚姩 QEMU锛屽湪鍏?shell 涓紪璇戜竴涓畝鍗曠殑 `.hl` 娴嬭瘯鏂囦欢銆?

**楠岃瘉**: `hl-bootstrap build/test` 鍦?QEMU 涓€氳繃 鈫?鑷妇鎴愬姛

---

## Phase 1: 鍐呮牳鍘熻婵€娲? 鉁?DONE

**鐩爣**: `.img` 涓殑鍐呮牳鑳藉湪 QEMU 涓纭鐞嗕腑鏂€佺鐞嗗唴瀛樸€佸搷搴旈敭鐩樸€?

**渚濊禆**: Phase 0 (鑳界敓鎴愬寘鍚畬鏁村唴鏍镐唬鐮佺殑 .img)

### 1.1 ISR 姹囩紪鍏ュ彛 Stub  鉁?

**瀹屾垚鍐呭**: `image_builder.build_kernel()` 涓?256 涓?IDT 鍚戦噺鐢熸垚瀹屾暣 ISR stub:
- 鍚戦噺 0-31 (CPU 寮傚父): push error code/dummy 鈫?push vector# 鈫?jmp common
- 鍚戦噺 32-47 (纭欢 IRQ): 鍚屼笂 + EOI 鍙戦€?(PIC1/PIC2)
- Common handler: 淇濆瓨鍏ㄩ儴 GP 瀵勫瓨鍣?(rax-r15) 鈫?鎸夊悜閲忓彿鍒嗗彂 鈫?timer tick / keyboard scancode 鈫?鍙戦€?EOI 鈫?鎭㈠ 鈫?iretq
- 姣忎釜 stub 16 瀛楄妭瀵归綈锛屾敮鎸?error code 鍜?non-error code 鍚戦噺

### 1.2 E820 鍐呭瓨妫€娴? 鉁?

**瀹屾垚鍐呭**:
- Stage1 MBR 鏂板 E820 妫€娴嬫満鍣ㄧ爜 (INT 15h, AX=E820h 寰幆)
- 鍐呭瓨鍥惧瓨鍌ㄥ湪 0x500: count(u32) + entries (base(8) + length(8) + type(4))
- `mem.hl` 鏂板瀹屾暣 E820 API: e820_count/entry_base/entry_length/entry_type/total_usable/find_largest_usable/dump

### 1.3 鍔ㄦ€侀〉琛ㄦ墿灞? 鉁?

**瀹屾垚鍐呭**:
- `page_alloc.hl` 鏂板 `page_alloc_init_e820()`: 浠?E820 鍐呭瓨鍥惧姩鎬佽缃?TOTAL_PAGES (鏈€楂?2GB)
- `page_alloc.hl` 鏂板 `page_alloc_contiguous(count)`: 杩炵画椤靛垎閰?
- `page_alloc.hl` 鏂板 `_page_mark_used()`: E820 闈炲彲鐢ㄥ尯鍩熸爣璁颁负宸茬敤
- `virt_mem.hl` 鏂板 `map_huge_page()`: 2MB 宸ㄩ〉鏄犲皠
- `virt_mem.hl` 鏂板 `map_all_ram()`: 鏍规嵁 E820 identity map 鎵€鏈夊彲鐢?RAM
- `virt_mem.hl` 鏂板 `tlb_flush_all()`, `tlb_invalidate()`

### 1.4 VESA 妯″紡璁剧疆  鉁?

**瀹屾垚鍐呭**:
- `vesa.hl` 閲嶅啓 `vesa_init()`: 浠?VBE mode info 鍧?(0x8000) 璇诲彇鐪熷疄鍙傛暟
- `vesa.hl` 鏂板 `vesa_auto_init()`, `vesa_info()`, `vesa_scroll_up()`
- 鑷姩妫€娴? 楠岃瘉 mode attributes 鈫?璇诲彇鍒嗚鲸鐜?BPP/framebuffer 鍦板潃/pitch
- 瀹夊叏鍥為€€: 濡傛灉 VBE 鏁版嵁鏃犳晥锛屼繚鎸佹枃鏈ā寮忓吋瀹?

---

## Phase 2: 纾佺洏 I/O 閫氳矾  鉁?DONE

**鐩爣**: 鍐呮牳鑳介€氳繃 VirtIO-blk 椹卞姩璇诲啓纾佺洏鎵囧尯銆?

**渚濊禆**: Phase 1.1 (ISR stub), Phase 1.2 (鍔ㄦ€佸唴瀛?

### 2.1 VirtIO-blk 椹卞姩瀹炵幇  鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/virtio_blk.hl` 瀹屾暣瀹炵幇:
- `virtio_blk_init()`: PCI BAR0 璇诲彇 鈫?璁惧澶嶄綅 鈫?ACKNOWLEDGE 鈫?DRIVER 鈫?鐗规€у崗鍟?鈫?virtqueue 鍒嗛厤 (descriptor table + available ring + used ring) 鈫?DRIVER_OK
- `virtio_blk_read(sector, count, buf_addr)`: 鏋勫缓璇锋眰澶?(type=IN) 鈫?3 descriptor chain (header 鈫?data 鈫?status) 鈫?鎻愪氦 鈫?杞 used ring 鈫?妫€鏌ョ姸鎬?
- `virtio_blk_write(sector, count, buf_addr)`: 鏋勫缓璇锋眰澶?(type=OUT) 鈫?3 descriptor chain 鈫?鎻愪氦 鈫?绛夊緟瀹屾垚
- `virtio_blk_capacity()`: 璇诲彇璁惧閰嶇疆鍖?(BAR0+20) 鑾峰彇纾佺洏鎵囧尯鏁?
- 鍐呴儴: _vq_alloc_desc/_vq_free_desc/_vq_write_desc/_vq_submit_and_wait
2. `virtio_blk_read()`: 3 鎻忚堪绗﹂摼 鈫?available ring 鈫?notify 鈫?绛夊緟 used ring
3. `virtio_blk_write()`: 鍚屼笂
4. `virtio_blk_capacity()`: 璇诲彇 BAR+20 鐨?64 浣嶅閲?

**浜や粯鐗?*: 鍙鍐欐墖鍖虹殑 VirtIO-blk 椹卞姩銆?

**楠岃瘉**: 鍐欏叆 sector 100 鈫?璇诲洖 鈫?鏁版嵁涓€鑷淬€?

### 2.2 Block Cache 婵€娲? 鉁?

**瀹屾垚鍐呭**: `block_cache.hl` 鍙栨秷娉ㄩ噴鎵€鏈?virtio_blk 璋冪敤:
- `bcache_writeback()`: 閫氳繃 `virtio_blk_write()` 鍐欏洖鑴忓潡
- `bcache_read()`: 缂撳瓨鏈懡涓椂閫氳繃 `virtio_blk_read()` 鍔犺浇
- `bcache_write()`: 閫氳繃 `mem_copy()` 鏇存柊缂撳瓨鏁版嵁

---

## Phase 3: 鏂囦欢绯荤粺钀藉湴  鉁?DONE

**鐩爣**: VFS 鑳介€氳繃鐪熷疄纾佺洏鍚庣璇诲啓鏂囦欢銆?

**渚濊禆**: Phase 2 (纾佺洏 I/O)

### 3.1 FAT16 椹卞姩婵€娲? 鉁?

**瀹屾垚鍐呭**: `fat16.hl` 瀹屾暣瀹炵幇璇诲啓:
- `fat16_read_fat()`: 閫氳繃 block cache 璇诲彇 FAT 琛ㄩ」
- `fat16_write_fat()`: 鍐?FAT 琛ㄩ」 (鍙?FAT 鍚屾)
- `fat16_alloc_cluster()`: 浠?FAT 鍒嗛厤绌洪棽绨?
- `fat16_list_root()`: 璇诲彇鏍圭洰褰曪紝瑙ｆ瀽 8.3 鏂囦欢鍚嶏紝璺宠繃 LFN/宸插垹闄?
- `fat16_read_file()`: 鎸夌皣閾捐鍙栧畬鏁存枃浠?
- `fat16_create_file()`: 鍦ㄦ牴鐩綍鍒涘缓鏂版潯鐩?(8.3 鍚嶃€佸ぇ鍐欒浆鎹?
- `fat16_write_file()`: 鎸夌皣閾惧啓鍏ユ暟鎹?(鑷姩鎵╁睍閾?
- `fat16_update_size()`: 鏇存柊鐩綍椤规枃浠跺ぇ灏?
- `fat16_delete_file()`: 鏍囪鍒犻櫎 + 閲婃斁绨囬摼
- `fat16_format()`: 瀹屾暣鏍煎紡鍖?(BPB + 鍙孎AT + 绌烘牴鐩綍)

### 3.2 VFS 鎸傝浇 FAT16  鉁?

**瀹屾垚鍐呭**: `vfs.hl` 鏂板 FAT16 鍚庣:
- `vfs_mount_fat16()`: 璇?boot sector 鈫?fat16_init 鈫?鎸傝浇鍒?/mnt/disk0
- `vfs_readdir()`: FAT16 鍒嗘敮璋冪敤 `fat16_list_root()`
- `vfs_stat()`: FAT16 鍒嗘敮鎼滅储鏍圭洰褰?
- `vfs_mkdir()`: FAT16 鍒嗘敮璋冪敤 `fat16_create_file(name, 1)`
- `vfs_unlink()`: FAT16 鍒嗘敮鍒犻櫎鏂囦欢

### 3.3 Swap 钀藉湴

**闂**: `swap.hl` 渚濊禆 virtio_blk + demand_page 琚敞閲娿€?

**娑夊強鏂囦欢**: `bare-kernel/hl/swap.hl`

**鏂规**: Phase 2 + Phase 1.1 瀹屾垚鍚庡彇娑堟敞閲娿€?

**浜や粯鐗?*: 鍙伐浣滅殑 swap + demand paging銆?

---

## Phase 4: 杩涚▼涓庤皟搴﹁惤鍦? 鉁?DONE

**鐩爣**: 澶氫换鍔¤皟搴︺€佷笂涓嬫枃鍒囨崲銆乫ork/exec/wait 鍦ㄥ師鐢熷唴鏍镐腑鍙敤銆?

**渚濊禆**: Phase 1.1 (timer ISR), Phase 1.3 (椤佃〃), Phase 3.2 (VFS for exec)

### 4.1 鍘熺敓 Context Switch  鉁?

**瀹屾垚鍐呭**:
- `task.hl` 琛ュ叏 `context_switch()`: 淇濆瓨褰撳墠浠诲姟鐘舵€?鈫?CR3 鍒囨崲 鈫?TLB flush 鈫?鍔犺浇鐩爣浠诲姟 GPR/RSP/RIP
- 鏂板 `schedule()`: CFS 璋冨害鍏ュ彛锛屼粠 timer ISR 鍜?yield/block 璺緞璋冪敤
- 鏂板 `task_yield()`: 鑷効璁╁嚭 CPU (vruntime 閫掑 鈫?璋冨害)
- 鏂板 `task_block(reason)` / `task_unblock(task_idx)`: 浠诲姟闃诲/鍞ら啋 (sleep銆亀ait銆乸ipe)
- 鏂板 `task_exit(code)`: 缁堟浠诲姟 + 鍙戦€?SIGCHLD + 璋冨害璧?
- 鏂板 `task_info()` / `task_list()`: 璋冭瘯杈撳嚭

### 4.2 Timer 椹卞姩璋冨害瑙﹀彂  鉁?

**瀹屾垚鍐呭**:
- `timer.hl` `timer_check()` 鏈熬璋冪敤 `timer_check_sleepers()` + `task_timer_tick()`
- 鏂板 `sleep_ms(ms)`: 璁＄畻 wake_tick 鈫?瀛樺叆浠诲姟 +208 鈫?`task_block()` 鈫?璋冨害璧?
- 鏂板 `timer_check_sleepers()`: 鎵弿鎵€鏈?BLOCKED 浠诲姟锛宒eadline 鍒版湡鍒?`task_unblock()`
- 100Hz PIT 鈫?`timer_check()` 鈫?CFS vruntime 鏇存柊 + 鎶㈠崰妫€鏌?鈫?瀹屾暣鏃堕棿鐗囪疆杞?

### 4.3 fork/exec/wait 绔埌绔? 鉁?

**瀹屾垚鍐呭**:
- `posix.hl` 淇 `sys_dup2()`: 淇鍙橀噺 src/dst 鏈畾涔?bug
- `posix.hl` 淇 `fd_alloc()`: 鍙栨秷娉ㄩ噴 FD_CLOSED 妫€鏌?
- `posix.hl` 鏀硅繘 `sys_exec()`: 閫氳繃 VFS open/read/close 鍔犺浇 ELF (鍙栦唬鐩存帴 vfs_read)
- `posix.hl` 鏀硅繘 `sys_wait()`: 閫氳繃 `task_block()` 闃诲绛夊緟 (鍙栦唬 spin loop)
- `posix.hl` 鏂板 `sys_exit(code)`: 鍏抽棴鎵€鏈?FD 鈫?`task_exit(code)`

---

## Phase 5: 瀹夎绋嬪簭瀹炵幇  鉁?DONE

**鐩爣**: 鑳藉皢 HicOS 鍐欏叆鐩爣纾佺洏骞朵娇鍏跺彲寮曞銆?

**渚濊禆**: Phase 2 (纾佺洏 I/O), Phase 3.1 (FAT16 鍐欏叆)

### 5.1 纾佺洏鍒嗗尯  鉁?

**瀹屾垚鍐呭**: `installer.hl` 瀹炵幇 `installer_create_mbr()`:
- 鍒涘缓鍗曞垎鍖?MBR锛屽垎鍖? 瑕嗙洊鏁翠釜纾佺洏 (type=0x06 FAT16 LBA)
- 淇濈暀宸叉湁寮曞浠ｇ爜
- 鍐欏叆 0x55AA 鍚姩绛惧悕

### 5.2 鏂囦欢绯荤粺鏍煎紡鍖? 鉁?

**瀹屾垚鍐呭**: `fat16.hl` 瀹炵幇 `fat16_format()`:
- 璁＄畻 BPB 鍙傛暟 (BPS=512, SPC=4)
- 鍐欏叆寮曞鎵囧尯 (jump + OEM + BPB + 0xAA55)
- 娓呴浂鍙?FAT 琛紝璁剧疆 FAT[0]=0xFFF8, FAT[1]=0xFFFF
- 娓呴浂鏍圭洰褰曞尯

### 5.3 寮曞鎵囧尯涓庡唴鏍稿啓鍏? 鉁?

**瀹屾垚鍐呭**: `installer.hl` 瀹炵幇 `installer_write_bootloader()`:
- 淇濈暀 MBR 鍒嗗尯琛?(浠呰鐩栧墠 446 瀛楄妭)
- 閫愭墖鍖哄啓鍏?stage2 + kernel image

### 5.4 瀹夎鍚戝 (Serial Shell)  鉁?

**瀹屾垚鍐呭**: `installer.hl` 瀹炵幇 `installer_main()` 6姝ュ畨瑁呮祦绋?
- [1/6] 妫€娴嬬鐩?鈫?[2/6] MBR 鍒嗗尯 鈫?[3/6] FAT16 鏍煎紡鍖?
- [4/6] 鍐欏紩瀵?鈫?[5/6] 鍐欐簮鏂囦欢 鈫?[6/6] 楠岃瘉瀹夎

---

## Phase 6: 鐪熷疄纭欢椹卞姩  鉁?DONE

**鐩爣**: 鑴辩 QEMU锛屽湪鐗╃悊 x86_64 鏈哄櫒涓婅繍琛屻€?

**渚濊禆**: Phase 5 (瀹夎绋嬪簭), Phase 1 (鍐呮牳鍘熻)

### 6.1 AHCI/SATA 椹卞姩  鉁?

**瀹屾垚鍐呭**: 鏂板缓 `bare-kernel/hl/ahci.hl`:
- `ahci_detect()`: PCI 鎵弿 class=01/subclass=06
- `ahci_init()`: ABAR 璇诲彇 鈫?AHCI Enable 鈫?绔彛鏋氫妇 鈫?绔彛鍒濆鍖?(CLB/FB/IS)
- `ahci_port_init()`: stop 鈫?璁剧疆 CLB/FB 鈫?clear IS 鈫?start
- `ahci_read()/ahci_write()`: FIS H2D + PRDT + Command Issue + 杞瀹屾垚
- `ahci_identify()`: ATA IDENTIFY DEVICE 鈫?瑙ｆ瀽 48-bit 鎵囧尯鏁?鍨嬪彿
- `ahci_build_fis_h2d()`: 瀹屾暣 Register H2D FIS (48-bit LBA)

### 6.2 NVMe 椹卞姩 (鍙€?

**鐘舵€?*: 鎺ㄨ繜鍒?AHCI 楠岃瘉鍚庛€?

### 6.3 USB HID 椹卞姩婵€娲? 鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/usb.hl` 閲嶅啓:
- 淇 `xhci_init()`: 娑堥櫎鏈畾涔夊彉閲?bug锛屽畬鏁?MMIO 瀵勫瓨鍣ㄦ搷浣?
- BAR0 璇诲彇 鈫?cap registers 鈫?stop/reset/wait 鈫?MaxSlotsEn 鈫?DCBA 鈫?CMD ring 鈫?start
- `xhci_port_status()`: 璇诲彇 PORTSC (CCS/PED/speed)
- `xhci_enumerate()`: 鎵弿鎵€鏈夌鍙ｏ紝鎵撳嵃杩炴帴鐘舵€佸拰閫熷害
- `usb_detect()` + `usb_init()`: PCI 妫€娴?鈫?xHCI init 鈫?enumerate

### 6.4 PS/2 鍏?Scancode 鏄犲皠  鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/scancode.hl` 澧炲己:
- `build_shift_table()`: 瀹屾暣 Shift 鏄犲皠 (绗﹀彿: !@#$%^&*()_+ etc.)
- `scancode_process(sc)`: 杩斿洖 [ascii, ctrl, alt]
- 淇グ閿窡韪? LShift/RShift/LCtrl/LAlt 鎸変笅/閲婃斁鐘舵€?
- CapsLock 鍒囨崲: 浠呭奖鍝嶅瓧姣嶉敭 (涓?Shift XOR)
- Ctrl+letter: ASCII 1-26
- F1-F12 鍔熻兘閿? 杩斿洖璐熸暟缂栫爜 (-1 鍒?-12)
- 鍚戝悗鍏煎: `scancode_to_ascii()` 涓嶅彉

---

## Phase 7: 缃戠粶鏍堟縺娲? 鉁?DONE

**鐩爣**: 鍙€氳繃缃戠粶涓嬭浇/瀹夎銆?

**渚濊禆**: Phase 1 (ISR for IRQ), Phase 2 (鍐呭瓨鍒嗛厤)

### 7.1 VirtIO-net 椹卞姩琛ュ叏  鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/virtio_net.hl` 閲嶅啓:
- `virtio_net_detect()`: PCI 鎵弿 vendor=0x1AF4 device=0x1000
- `virtio_net_init()`: BAR0 鈫?reset 鈫?negotiate 鈫?RX queue 棰勫～鎻忚堪绗?鈫?TX queue 鈫?driver OK
- `virtio_net_send()`: 2-descriptor chain (virtio_net_header + payload) 鈫?available ring 鈫?notify
- `virtio_net_send_pkt()`: byte array 鈫?鍐呭瓨 buffer 鈫?send
- `virtio_net_recv_pkt()`: poll used ring 鈫?璺宠繃 virtio_net_header 鈫?杩斿洖 byte array 鈫?閲嶅～ avail

### 7.2 DHCP 绔埌绔? 鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/dhcp.hl` 琛ュ叏:
- `dhcp_build_request()`: 瀹屾暣 REQUEST 鍖呬綋 (option 53=REQUEST + option 50 + option 54)
- `dhcp_discover()`: 鏋勫缓 DISCOVER 鈫?UDP 鈫?`virtio_net_send_pkt()`
- `dhcp_request()`: 鏋勫缓 REQUEST 鈫?鍙戦€?
- `dhcp_input()`: 瑙ｆ瀽 xid 鈫?option 53 message type 鈫?OFFER 鈫?REQUEST 鈫?ACK 鑷姩娴佺▼
- ACK 鍚庤嚜鍔ㄩ厤缃?`my_ip`/`gw_ip`/`netmask`

### 7.3 TCP 绔埌绔? 鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/tcp.hl` 琛ュ叏:
- `tcp_send()`: 鏋勫缓 PSH+ACK 娈?鈫?IPv4 灏佽 鈫?`virtio_net_send_pkt()` 鈫?鏇存柊 seq
- `tcp_close()`: 鍙戦€?FIN+ACK 鈫?鐘舵€佹満 ESTABLISHED鈫扚IN_WAIT1 / CLOSE_WAIT鈫扡AST_ACK
- `build_ip_tcp_packet()`: Ethernet + IPv4 + IP checksum + TCP 鏁版嵁

### 7.4 缃戠粶杈撳叆鍒嗗彂  鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/net.hl` 澧炲己:
- ARP 琛? `arp_init()`/`arp_lookup()`/`arp_update()` (16 entries)
- `arp_input()`: 瑙ｆ瀽 ARP reply 鈫?鏇存柊琛?鈫?鑷姩璁剧疆 gateway MAC
- `net_input()`: Ethernet 瑙ｅ抚 鈫?ARP/IPv4 鍒嗗彂 鈫?ICMP/UDP/TCP 瀛愬垎鍙?
- `net_poll()`: `virtio_net_recv_pkt()` 鈫?`net_input()`
- `net_init()`: ARP init 鈫?VirtIO-net detect/init 鈫?ARP gateway 鈫?DHCP ready

### 7.5 鐪熷疄缃戝崱椹卞姩 (鍙€?

**鐘舵€?*: 鎺ㄨ繜鍒?VirtIO-net 楠岃瘉鍚庛€?

---

## Phase 8: 楂樼骇瀛愮郴缁? 鉁?DONE

**鐩爣**: 瀹屽杽 OS 浣撻獙銆?

**渚濊禆**: Phase 4 (杩涚▼璋冨害), Phase 3 (鏂囦欢绯荤粺)

### 8.1 SMP 瀹屾暣瀹炵幇  鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/smp.hl` 澧炲己:
- `percpu_init()`/`percpu_addr()`: Per-CPU 鏁版嵁缁撴瀯 at 0x350000 (apic_id, current_task, flags, stack)
- `spin_lock()`/`spin_unlock()`/`spin_trylock()`: SMP spinlock 鍘熻
- Kernel-wide locks: LOCK_SCHED, LOCK_ALLOC, LOCK_PRINT at 0x360000
- `smp_send_reschedule()`/`smp_broadcast_ipi()`: IPI 璋冨害閫氱煡
- `ap_main()`: AP 瀹屾暣鍚姩 鈫?LAPIC init 鈫?per-CPU init 鈫?signal BSP
- `smp_init()`: locks init 鈫?percpu BSP 鈫?discover 鈫?boot APs

### 8.2 ACPI 鐢垫簮绠＄悊婵€娲? 鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/power.hl` 閲嶅啓:
- `power_init()`: RSDP 鈫?RSDT 鈫?FADT 鈫?PM1a/PM1b_CNT + reset register + S5 SLP_TYP
- `power_init_fadt()`: 瑙ｆ瀽 FADT offset+64(PM1a), +68(PM1b), +116(reset GAS), +128(reset val)
- `power_shutdown()`: ACPI SLP_EN+SLP_TYP 鈫?QEMU 0x604 鈫?Bochs 0xB004 鈫?halt 鍥涚骇鍥為€€
- `power_reboot()`: ACPI reset reg 鈫?8042 0xFE 鈫?triple fault 涓夌骇鍥為€€
- `power_sleep()`: S1 sleep via PM1a_CNT

### 8.3 Firmware 鍔犺浇妗嗘灦婵€娲? 鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/firmware.hl` 閲嶅啓:
- `firmware_request()`: VFS open 鈫?stat 鈫?page_alloc_contiguous 鈫?vfs_read 鈫?杩斿洖 [addr, size]
- `firmware_release()`: mem_zero 鈫?page_free 鈫?浠庣紦瀛樼Щ闄?
- 鍐呭瓨缂撳瓨: fw_cache_names/addrs/sizes 閬垮厤閲嶅鍔犺浇
- `firmware_init()`: 鍒涘缓 /lib/firmware/ VFS 鐩綍

### 8.4 ext2 鏂囦欢绯荤粺  鉁?

**瀹屾垚鍐呭**: `bare-kernel/hl/ext2.hl` 閲嶅啓:
- `ext2_init(partition_lba)`: 璇诲彇纾佺洏 superblock 鈫?楠岃瘉 magic 0xEF53 鈫?瑙ｆ瀽 block_size/inodes_per_group/inode_size
- `ext2_read_inode()`: 閫氳繃 BGDT 鈫?inode table 鈫?bcache_read 浠庣鐩樿鍙?
- `ext2_read_block()`: 閫氳繃 bcache_read 璇诲彇浠绘剰鏂囦欢绯荤粺鍧?
- `ext2_resolve(path)`: str_split 鈫?閫愮骇 ext2_lookup 鈫?杩斿洖 inode 鍙?
- `ext2_read_path()`: resolve 鈫?read_inode 鈫?read_file 涓€姝ュ埌浣?
- `ext2_is_dir()`/`ext2_file_size()`/`ext2_file_mode()`: inode 鍏冩暟鎹鍙?
- `ext2_vfs_mount()`: VFS 鎸傝浇鍏ュ彛

---

## Phase 9: UEFI 寮曞 + 瀹夊叏寮曞  鉁?DONE

**鐩爣**: 鏀寔绾?UEFI 纭欢銆?

**渚濊禆**: Phase 6 (鐪熷疄纭欢椹卞姩)

### 9.1 UEFI 搴旂敤绋嬪簭  鉁?

**瀹屾垚鍐呭**: 鏂板缓 `bare-kernel/hl/uefi_boot.hl`:
- Boot info 缁撴瀯浣?at 0x100000: magic, memory map, framebuffer, RSDP, boot mode
- `uefi_is_boot()`: 妫€娴?"HICUEFI\0" magic 鈫?UEFI/BIOS 鍒嗘祦
- `uefi_parse_memory_map()`: EFI 鍐呭瓨绫诲瀷 鈫?usable pages 缁熻
- `uefi_init_page_alloc()`: EFI_CONVENTIONAL + BOOT_SERVICES 鈫?page_free (skip < 2MB)
- `uefi_init_framebuffer()`: GOP info 鈫?vesa_set_mode_direct
- `uefi_get_rsdp()`: EFI config table RSDP (鏇夸唬 BIOS 鍐呭瓨鎼滅储)
- `uefi_boot_init()`: 瀹屾暣 UEFI 鍚姩璺緞 (鏇夸唬 E820 + VESA BIOS)
- PE32+ header 鐢熸垚: `pe_build_dos_stub()` + `pe_build_header()` 鈫?BOOTX64.EFI 鎵€闇€鐨勬渶灏忓ご

### 9.2 GPT 鍒嗗尯琛? 鉁?

**瀹屾垚鍐呭**: 鏂板缓 `bare-kernel/hl/gpt.hl`:
- GPT header 璇诲啓: `gpt_write_header()` 鍚?CRC32銆乨isk GUID銆佸浠藉ご
- Partition entry 璇诲啓: `gpt_write_entry()` (type GUID, unique GUID, LBA range, UTF-16 name)
- Protective MBR: `gpt_write_protective_mbr()` (type 0xEE)
- GPT 璇诲彇楠岃瘉: `gpt_read()` 鈫?绛惧悕鏍￠獙 鈫?瑙ｆ瀽鎵€鏈?entry
- ESP 妫€娴? `gpt_is_esp()` + `gpt_find_esp()`
- 瀹屾暣鍒涘缓: `gpt_create()` 鈫?protective MBR 鈫?ESP 100MB + HicOS 鍒嗗尯 鈫?澶囦唤澶?entries
- `gpt_generate_guid()`: GUID v4 浼殢鏈虹敓鎴?
- `gpt_str_to_utf16()`: ASCII 鈫?UTF-16LE 杞崲
- 瀹夎鍣ㄩ泦鎴? `installer.hl` 鍗囩骇鍒?v5.0, UEFI/BIOS 鍙岃矾寰?

### 9.3 Secure Boot  鉁?

**瀹屾垚鍐呭**: 鏂板缓 `bare-kernel/hl/secure_boot.hl`:
- `secboot_detect()`: 浠?boot info 璇诲彇 SecureBoot/SetupMode 鐘舵€?
- SHA-256 鍝堝笇瀹炵幇: `sha256_hash()` (padding, block processing, 32-byte output)
- Trust database: `secboot_trust_add()` / `secboot_verify()` 鍩轰簬 name 鈫?hash 瀵?
- `secboot_firmware_request()`: firmware_request 鍖呰,鍔犺浇鍚庤嚜鍔?hash 楠岃瘉
- `secboot_init()`: 鍒濆鍖?+ 鐘舵€佹墦鍗?

---

## 渚濊禆鍏崇郴鍥?

```
Phase 0 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
  0.1 Bootstrap 瀹夸富                                      鈹?
  0.2 Kernel Codegen 鍏ュ彛                                 鈹?
  0.3 鑷妇楠岃瘉                                            鈹?
  鈹?                                                      鈹?
Phase 1 鈼勨攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
  1.1 ISR Stub 鈼勨攢鈹€鈹€ Phase 0
  1.2 E820 鍐呭瓨妫€娴?鈼勨攢鈹€鈹€ Phase 0
  1.3 鍔ㄦ€侀〉琛?鈼勨攢鈹€鈹€ 1.2
  1.4 VESA 瀹炴ā寮?鈼勨攢鈹€鈹€ Phase 0
  鈹?
Phase 2 鈼勨攢鈹€鈹€ 1.1 + 1.2
  2.1 VirtIO-blk 鈼勨攢鈹€鈹€ 1.1, 1.2
  2.2 Block Cache 鈼勨攢鈹€鈹€ 2.1
  鈹?
Phase 3 鈼勨攢鈹€鈹€ Phase 2
  3.1 FAT16 婵€娲?鈼勨攢鈹€鈹€ 2.1
  3.2 VFS 鎸傝浇 鈼勨攢鈹€鈹€ 3.1
  3.3 Swap 钀藉湴 鈼勨攢鈹€鈹€ 2.1, 1.1
  鈹?
Phase 4 鈼勨攢鈹€鈹€ 1.1 + 1.3
  4.1 Context Switch 鈼勨攢鈹€鈹€ 1.1
  4.2 Timer 璋冨害 鈼勨攢鈹€鈹€ 4.1, 1.1
  4.3 fork/exec/wait 鈼勨攢鈹€鈹€ 4.1, 3.2
  鈹?
Phase 5 鈼勨攢鈹€鈹€ Phase 2 + Phase 3
  5.1 纾佺洏鍒嗗尯 鈼勨攢鈹€鈹€ 2.1
  5.2 FAT16 鏍煎紡鍖?鈼勨攢鈹€鈹€ 3.1
  5.3 寮曞鎵囧尯鍐欏叆 鈼勨攢鈹€鈹€ 5.1, 5.2
  5.4 瀹夎鍚戝 鈼勨攢鈹€鈹€ 5.3
  鈹?
Phase 6 鈼勨攢鈹€鈹€ Phase 5 + Phase 1
  6.1 AHCI 鈼勨攢鈹€鈹€ 1.1, 1.2
  6.2 NVMe 鈼勨攢鈹€鈹€ 1.1, 1.2  (鍙€?
  6.3 USB HID 鈼勨攢鈹€鈹€ 1.1
  6.4 PS/2 鈼勨攢鈹€鈹€ 宸查儴鍒嗗畬鎴?
  鈹?
Phase 7 鈼勨攢鈹€鈹€ Phase 1
  7.1 VirtIO-net 鈼勨攢鈹€鈹€ 1.1, 1.2
  7.2 DHCP 鈼勨攢鈹€鈹€ 7.1
  7.3 TCP 鈼勨攢鈹€鈹€ 7.1
  7.4 HTTP 鈼勨攢鈹€鈹€ 7.3
  7.5 e1000 鈼勨攢鈹€鈹€ 1.1  (鍙€?
  鈹?
Phase 8 鈼勨攢鈹€鈹€ Phase 4 + Phase 3
  8.1 SMP 鈼勨攢鈹€鈹€ 4.1
  8.2 ACPI Power 鈼勨攢鈹€鈹€ 1.1
  8.3 Firmware 鈼勨攢鈹€鈹€ 3.2
  8.4 ext2 鈼勨攢鈹€鈹€ 2.1
  鈹?
Phase 9 鈼勨攢鈹€鈹€ Phase 6
  9.1 UEFI Boot 鈼勨攢鈹€鈹€ Phase 0
  9.2 GPT 鈼勨攢鈹€鈹€ 5.1
  9.3 Secure Boot 鈼勨攢鈹€鈹€ 9.1  (鍙€?
```

## 骞惰鍖栧缓璁?

| 骞惰缁?| 鏉垮潡 | 鍓嶆彁 |
|--------|------|------|
| A | Phase 2 (纾佺洏) + Phase 4.1 (context switch) | 閮藉彧渚濊禆 Phase 1 |
| B | Phase 3 (鏂囦欢绯荤粺) + Phase 7.1 (VirtIO-net) | 鍒嗗埆渚濊禆 Phase 2 鍜?Phase 1 |
| C | Phase 6.1 (AHCI) + Phase 6.3 (USB HID) | 閮藉彧渚濊禆 Phase 1 |
| D | Phase 5 (瀹夎绋嬪簭) + Phase 8.2 (ACPI) | 鍒嗗埆渚濊禆 Phase 3 鍜?Phase 1 |

## 閲岀▼纰?

| 閲岀▼纰?| 瀹屾垚鏍囧織 | 浼扮畻渚濊禆闃舵 |
|--------|----------|-------------|
| M1: 鑷妇缂栬瘧 | `.hl` 婧愮爜 鈫?鍙紩瀵?`.img` | Phase 0 |
| M2: QEMU 鍙氦浜?| Shell 鍝嶅簲鍛戒护 + 鍐呭瓨/涓柇姝ｅ父 | Phase 1 |
| M3: QEMU 鍙畨瑁?| 绌虹鐩?鈫?瀹夎 鈫?閲嶅惎鎴愬姛 | Phase 5 |
| M4: 瑁告満鍙惎鍔?| 鐗╃悊 PC USB 鍚姩 HicOS | Phase 6 |
| M5: 瑁告満鍙畨瑁?| 鐗╃悊 PC 纭洏瀹夎 + 鍚姩 | Phase 6 + Phase 5 |
| M6: 缃戠粶鍙敤 | ping / http get 鎴愬姛 | Phase 7 |
| M7: 澶氫换鍔″彲鐢?| fork/exec 杩愯鐢ㄦ埛绋嬪簭 | Phase 4 |


