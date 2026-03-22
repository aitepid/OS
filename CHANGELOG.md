## v4.2

- **Build System**: Removed JS dependencies entirely. Now strictly using hl-bootstrap entrypoints.
- **Testing**: Integrated hl-bootstrap-build-test.ps1 for end-to-end Phase 1 lexer verification and workspace readines.
- **Project Purity**: Enforced strict Hilbert-Lang purity across all modules and build tests.

# HicOS Changelog

## v6.0 (Current)

176 active .hl files, 114 kernel modules, 63 shell commands (Layer C), 33 kernel.bin commands, 0 external deps.
Dual-boot: BIOS 74/74 PASS + UEFI 3/3 PASS. Full gate 10/10 PASS.
Image: 152,064 bytes (297 sectors). Code: ~46,800 lines (38,800 H-L + 8,000 PS1).

### Iteration 49: HMAC-SHA-256 + HKDF in kernel.bin
- **HMAC-SHA-256 (RFC 2104)**:
  - `_ke_hmac_sha256(key_addr, key_len, msg_addr, msg_len)`: Full HMAC computation
    - Key padding: if key > 64B → SHA-256(key), else pad with zeros to 64B
    - Inner hash: SHA-256((K' ⊕ ipad) || message), ipad = 0x36 × 64
    - Outer hash: SHA-256((K' ⊕ opad) || inner_hash), opad = 0x5c × 64
    - Result: 32 bytes at 0x940440
  - `_ke_xor_byte(a, b)`: 8-bit XOR via arithmetic (for ipad/opad key mixing)
- **HKDF (RFC 5869)**:
  - `_ke_hkdf_extract(salt_addr, salt_len, ikm_addr, ikm_len)`: PRK = HMAC(salt, IKM)
    - Result: 32 bytes at 0x940460
  - `_ke_hkdf_expand(prk_addr, info_addr, info_len, out_len)`: OKM expansion
    - T(i) = HMAC(PRK, T(i-1) || info || i), up to 8 iterations (256B max)
    - Result: up to 64 bytes at 0x940520
- **Shell commands**:
  - `hmac <text>`: HMAC-SHA-256 with test key "key" → "HMAC: " + 64-char hex
  - `hkdf`: HKDF demo (salt="salt", IKM="input", info="info", L=32) → "HKDF: " + 64-char hex
- **Memory layout**: 0x940300-0x94053F (HMAC+HKDF working area)
  - K' key (64B) + inner buf (128B) + outer buf (128B) + HMAC out (32B)
  - PRK (32B) + T buffer (32B) + concat buf (128B) + OKM out (64B)
- **Dispatch**: `hmac` 5-char prefix + `hkdf` 4-char exact match
- 6 new functions, 2 shell commands wired to dispatch + help updated
- **Shell commands (33)**: help tick pci pmem palloc pfree malloc mfree ps mouse tcptest gfxtest wm smp ahci usb acpi beep time disk format ls mkfile cat run wget uptime shutdown install reboot sha256 hmac hkdf
- 🏆 **TLS 1.3 密钥派生就绪**: HMAC-SHA-256 + HKDF, 迭代 50 AES-128 的前置条件完成

### Iteration 48: SHA-256 Cryptographic Hash in kernel.bin
- **SHA-256 full implementation** (64-round compression, FIPS 180-4 compliant):
  - `_ke_sha256_init_k()`: 64 round constants K[0..63] at 0x940000 (256 bytes)
  - `_ke_sha256_hash(data_addr, data_len)`: Full SHA-256 computation
    - Message padding (0x80 + zeros + 64-bit big-endian length)
    - Message schedule W[0..63] expansion (σ0, σ1 functions)
    - 64-round compression (Σ0, Σ1, Ch, Maj functions)
    - Output: 32 bytes at 0x9402A0
  - `_ke_sha256_rotr(val, bits)`: 32-bit right rotation
  - `_ke_sha256_shr(val, bits)`: 32-bit right shift
- **Bitwise operations** (pure arithmetic, no hardware bitwise instructions needed):
  - `_ke_xor2(a, b)`: 32-bit XOR via bit-by-bit div/mod
  - `_ke_xor3(a, b, c)`: Triple XOR
  - `_ke_and32(a, b)`: 32-bit AND
  - `_ke_not32(a)`: 32-bit NOT (XOR with 0xFFFFFFFF)
  - `_ke_ch(e, f, g)`: SHA-256 Ch function
  - `_ke_maj(a, b, c)`: SHA-256 Maj function
- **Helper functions**:
  - `_ke_mem_r32be(addr)`: Read 32-bit big-endian from memory
  - `_ke_mem_w32be(addr, val)`: Write 32-bit big-endian to memory
  - `_ke_mem_r32(addr)`: Read 32-bit little-endian from memory
  - `_ke_put_hex8(val)`: Print 8-bit hex (2 digits)
  - `_ke_put_hex32(val)`: Print 32-bit hex (8 digits)
- **`sha256` shell command**: `sha256 <text>` → "SHA256: " + 64-char hex digest
  - Command dispatch: 7-char prefix match "sha256 " (115 104 97 50 53 54 32)
  - Usage help on empty argument
- **Memory layout**: 0x940000-0x9402BF (SHA-256 working area)
  - K constants (256B) + W schedule (256B) + pad buffer (128B) + state (32B) + output (32B)
- **Boot init**: `_ke_sha256_init_k()` called in `_start()` Phase 7e
- 14 new functions, `sha256` shell command wired to dispatch
- **Shell commands (31)**: help tick pci pmem palloc pfree malloc mfree ps mouse tcptest gfxtest wm smp ahci usb acpi beep time disk format ls mkfile cat run wget uptime shutdown install reboot sha256
- 🏆 **密码学基础就绪**: SHA-256 in kernel.bin, v7.0 TLS 1.3 路线图第一步完成
Image: 152,064 bytes (297 sectors). Code: ~46,100 lines (38,082 H-L + 8,000 PS1).

### Iteration 47: clear + hexdump + v7.0 Plan
- **New Layer A commands** (18→20):
  - `clear`: VT100 ESC[2J + ESC[H serial terminal clear
  - `hexdump`: Read disk sector 0, print 32×16 hex dump + MBR 0x55AA check
- **New callable subroutines**:
  - `serial_hex_byte`: Print AL as 2-digit hex to COM1 (callable function)
  - `serial_space`: Print single space to COM1 (callable function)
- **Version bump**: `ver` command shows "HicOS 6.0 -- 114 modules"
- **v7.0 roadmap**: 10 detailed iterations (47-56) added to PROJECT_ADVANCEMENT_PLAN.hl
  - Phase V: 密码学 (SHA-256, HMAC, AES-128-GCM) → TLS 1.3 → HTTPS → 图形终端 → ext2 → hlpkg
- Layer A shell commands (20): help ver free ps lspci uptime reboot shutdown halt format ls mkfile cat ifconfig dhcp ping nslookup vesa ring3 clear hexdump

### Iteration 46: v6.0 Release Integration
- **QEMU tests expanded**: 42 → 62 checks across 11 phases
  - Phase 7: Hardware detection (ACPI, SMP, AHCI, USB, RTC, uptime)
  - Phase 8: Disk I/O (disk command, ver, tick)
  - Phase 9: Installer (7-step install verification)
  - Phase 10: Interpreter (format → mkfile → run cycle)
  - Phase 11: Memory management (pmem, palloc, malloc)
- **Full gate expanded**: 7 → 10 checks
  - New: QEMU UEFI test, performance baseline, release validation
- **New scripts**:
  - `scripts/perf-baseline.ps1`: Boot time, file I/O cycle, DHCP latency, artifact sizes
  - `scripts/release-validate.ps1`: Artifact existence + MBR/PE validation + language purity
- **README.md updated**: v6.0 highlights, installation guide, expanded QEMU verification list
- **Documentation synced**: PROJECT_STATUS.md, CHANGELOG.md, ROADMAP.md reflect v6.0 state
- 🏆 **v6.0 release milestone**: all 10 phases complete, dual-boot verified, 30 shell commands

### Iteration 45: HicOS Installer in kernel.bin
- **7-step installer**: `_ke_cmd_install()` — interactive disk installation workflow
  - [1/7] Detect disk: read VirtIO-blk capacity from BAR+0x14
  - [2/7] MBR partition table: type=0x06 FAT16 LBA, bootable flag, 0x55AA signature
  - [3/7] FAT16 format: reuse `_ke_cmd_format()` (BPB + dual FAT + root dir)
  - [4/7] HICOS.SYS: system marker file at cluster 2 ("HicOS v6.0 kernel")
  - [5/7] BOOT.CFG: boot config at cluster 3 ("boot=hicos\nmode=text")
  - [6/7] Verify: read sector 0, check MBR 0x55AA
  - [7/7] Completion banner
- **Helper**: `_ke_install_step(n)` — print "[N/7] " prefix
- `install` shell command (7 chars exact match dispatch)
- 🏆 **安装器端到端**: install → MBR+FAT16+文件 → 验证 → 完成

### Iteration 44: Micro H-L Interpreter + run command
- **File loader**: `_ke_load_file(addr, len)` — FAT16 search + cluster read into 0x930000 buffer (4KB max)
- **Variable system**: hash-based table at 0x931000 (32 entries), `_ke_var_set/get/hash()`
- **Expression evaluator**: `_ke_eval_expr()` — integers + variables + operators (+, -, *)
- **Statement interpreter**: `_ke_cmd_run()` — parse and execute:
  - `print("string literal");` → serial output
  - `print(expr);` → evaluate and print number
  - `let [mut] x = expr;` → store variable
  - `// comment` → skip to EOL
- **Helpers**: `_ke_skip_ws()`, `_ke_parse_num()`
- 8 new functions, `run` shell command with prefix dispatch
- 🏆 **端到端流程**: `mkfile hello.hl print("Hello")` → `run hello.hl` → 输出 "Hello"

### Iteration 43: FAT16 mkfile + cat in kernel.bin
- **8.3 name parser**: `_ke_parse_83name(addr, len)` — filename to 8.3 uppercase + space-pad (shared helper)
- **File create**: `_ke_cmd_mkfile(buf_addr, buf_len)` — parse "mkfile name.ext content"
  - FAT cluster allocation (scan FAT1 for first 0x0000 entry)
  - Content write to data cluster (164 + (cluster-2)*4)
  - Dual FAT update (FAT1 + FAT2 = 0xFFFF end-of-chain)
  - Root directory entry creation (8.3 name + attr 0x20 + cluster + size)
- **File read**: `_ke_cmd_cat(buf_addr, buf_len)` — parse "cat name.ext"
  - Root directory search (11-byte 8.3 name comparison)
  - FAT chain traversal (cluster → sector → read → next cluster)
  - Content output via serial (byte-by-byte up to file size)
- `mkfile` + `cat` shell commands wired to prefix dispatch
- 🏆 **FAT16 端到端闭环**: format → mkfile → ls → cat 全流程在 kernel.bin 实现

### Iteration 42: FAT16 Format + ls in kernel.bin
- **VirtIO-blk write**: `_ke_virtio_blk_write(sector)` — 3-descriptor chain (header→data→status), device-readable data
- **FAT16 format**: `_ke_cmd_format()` — Write BPB + dual FAT + root directory (164 sectors total)
  - BPB: 512B/sector, 4 sectors/cluster, 4 reserved, 2×64 FAT, 512 root entries
  - Volume label "HicOS", FS type "FAT16   ", media 0xF8
- **Directory list**: `_ke_cmd_ls()` — Read root directory sectors 132-163, parse 32-byte entries
  - Skip deleted (0xE5), LFN (0x0F), volume label (attr bit 3)
  - Print filename.ext + decimal size + file count
- **Helpers**: `_ke_blk_zero_buf()`, `_ke_mem_r16()` (16-bit LE memory read)
- 4 new functions, `format` + `ls` shell commands wired to dispatch

### Iteration 41: VirtIO-blk Disk I/O + System Commands
- **VirtIO-blk driver**: PCI detect (vendor 0x1AF4, device 0x1001) + queue init + sector read
  - `_ke_virtio_blk_find/init/read()`: Full VirtIO legacy I/O driver
  - Queue at 0x920000, avail 0x920800, used 0x921000, data buffer 0x922100
  - 3-descriptor chain: header(16B) → data(512B) → status(1B)
- **`disk` command**: Show capacity + read sector 0 + hex dump + MBR 55AA check
- **`uptime` command**: Read tick counter → hours/minutes/seconds
- **`shutdown` command**: ACPI RSDP→RSDT→FADT→PM1a S5 shutdown
- Init added to `_start()` Phase 7c

### Iteration 40: AC97 Beep + RTC Time in kernel.bin
- **AC97 Audio (beep command)**:
  - `_ke_ac97_find()`: PCI scan for Intel AC97 (vendor 0x8086, device 0x2415)
  - `_ke_pci_write32/16()`: PCI config space write for bus mastering enable
  - `_ke_mem_w16()`: 16-bit little-endian memory write helper
  - `_ke_cmd_beep()`: Full AC97 init → 440Hz square wave generation → BDL → DMA playback
    - Mixer reset + volume set (master 0, PCM 0x0808)
    - 24000 samples at 48kHz, stereo, 16-bit signed
  - `beep` shell command wired to dispatch
- **RTC Time (time command)**:
  - `_ke_rtc_read(reg)`: CMOS register read via ports 0x70/0x71
  - `_ke_bcd2bin(bcd)`: BCD to binary conversion
  - `_ke_put_dec2(val)`: 2-digit decimal with leading zero
  - `_ke_cmd_time()`: Read CMOS RTC → BCD decode → "YYYY-MM-DD HH:MM:SS" output
    - Wait for update-in-progress clear (Status Register A bit 7)
  - `time` shell command wired to dispatch
- **pci.hl self-test**: Fixed multi-line print for interpreter compatibility
- 18 new functions, kernel.bin: 19,384 bytes (+238B), 1,097 functions, 20 shell commands
- **Shell commands (20)**: help tick pci pmem palloc pfree malloc mfree ps mouse tcptest gfxtest wm smp ahci usb acpi beep time wget reboot

### Iterations 29-31: TCP + HTTP + Mouse in kernel.bin (A/C fusion)
- **Iteration 29: TCP State Machine + VirtIO-net TX**
  - `_ke_virtio_find()`: PCI scan for VirtIO vendor 0x1AF4, device 0x1000
  - `_ke_virtio_bar0()`: Read PCI BAR0 for I/O port base
  - `_ke_virtio_init()`: Reset → ACK → DRIVER → queue setup → DRIVER_OK
  - `_ke_virtio_tx()`: Build VirtIO descriptor chain + avail ring + notify TX queue
  - `_ke_tcp_build_syn()`: Ethernet + IPv4 (checksum) + TCP SYN packet construction
  - `_ke_cmd_tcptest()`: Build SYN → TX via VirtIO → TCB state: SYN_SENT → ESTABLISHED
  - `tcptest` shell command wired to dispatch
- **Iteration 30: HTTP GET (simulated)**
  - `_ke_cmd_wget()`: Build "GET / HTTP/1.0\r\n\r\n" in memory, check TCB state
  - `wget` shell command wired to dispatch
  - Simulated response: "HTTP/1.0 200 OK" + connection close
- **Iteration 31: PS/2 Mouse Driver + ISR Fix**
  - **ISR bug fix**: Timer/Keyboard jne/jmp offsets corrected (keyboard IRQ was unreachable)
    - Timer jne: 14→10, Timer jmp: 26→66, Keyboard jne: 18→28
  - **Mouse IRQ12 handler**: New vector 44 handling in common ISR
    - Reads port 0x60, stores at 0x300018 (mouse_byte), sets 0x300020 (mouse_ready)
  - **PS/2 mouse init**: `_ke_mouse_init()` — enable aux device, set defaults, enable reporting
    - PS/2 controller command byte modification (IRQ12 enable)
    - PIC2 IRQ12 unmask (port 0xA1 bit 4 clear)
  - **Mouse command**: `_ke_cmd_mouse()` — init + read 3-byte packet + decode + display
    - Signed dx/dy decoding, button state, position tracking (0..1023 x 0..767)
  - 7 new functions: `_ke_ps2_wait_in/out`, `_ke_mouse_cmd/ack/init`, `_ke_mouse_read_irq`, `_ke_cmd_mouse`
- **Iteration 32: VESA Bitmap Font Rendering**
  - **Font init**: `_ke_font_init()` — 8x16 VGA bitmap font for ASCII 32-126 (94 glyphs)
    - Font data at 0x310100, 16 bytes per glyph, packed u32 storage via `_ke_fc()` helper
    - Standard VGA 8x16 glyphs: uppercase A-Z, lowercase a-z, digits 0-9, full punctuation
  - **Pixel renderer**: `_ke_vesa_draw_char(px, py, ch, fg, bg)` — 8x16 glyph to LFB
    - Bit-test loop (MSB=left pixel), per-pixel fg/bg color via `_ke_mem_w32`
    - Framebuffer: 0xFD000000, pitch 4096, 32bpp BGRX
  - **gfxtest command**: Draws "HicOS v5.0" at (100,100), white on dark blue
  - 4 new functions: `_ke_fc`, `_ke_font_init`, `_ke_vesa_draw_char`, `_ke_cmd_gfxtest`
  - Font init called from `_start()` Phase 7c
- **Iteration 33: Window Manager + Graphical Desktop**
  - **Rectangle fill**: `_ke_vesa_fill_rect(rx, ry, rw, rh, color)` — full rect fill on LFB
  - **Mouse cursor**: `_ke_wm_draw_cursor(cx, cy)` — 10px triangle cursor (white/black edge)
  - **`wm` command**: Renders complete graphical desktop:
    - Desktop background: dark blue (0x204080) full 1024×768 fill
    - Window 1 (active): "HicOS" title on blue bar (0x3366CC), 400×300 white content, "Welcome" text
    - Window 2 (inactive): "Shell" title on gray bar (0x666666), 350×250 white content, "HicOS>" prompt
    - Mouse cursor at tracked PS/2 position (0x300028/0x300030)
  - 3 new functions: `_ke_vesa_fill_rect`, `_ke_wm_draw_cursor`, `_ke_cmd_wm`
- **Iteration 34: SMP Multi-core Bootstrap**
  - **LAPIC MMIO mapping**: `_ke_smp_map_lapic()` — PD[503] maps 0xFEE00000 (P+RW+PS+PCD)
  - **LAPIC access**: `_ke_lapic_r/w(offset)` — 32-bit MMIO read/write at 0xFEE00000
  - **AP trampoline**: `_ke_smp_trampoline()` — 107 bytes at 0x8000
    - 16-bit real: CLI + LGDT + enable PE + far JMP to PM
    - 32-bit PM: load segments + PAE + PML4(0x1000) + EFER.LME + enable PG + far JMP to LM
    - 64-bit LM: INC [0x300040] (AP online signal) + HLT loop
    - Private GDT: null + code32 + data32 + code64 (at 0x8080)
  - **INIT-SIPI-SIPI**: `_ke_smp_boot()` — all-excluding-self broadcast
    - ICR 0xC4500 (INIT) → 10ms → ICR 0xC4608 (SIPI vector 8) → 200μs → SIPI #2
    - AP counter at 0x300040, returns number of APs that reached long mode
  - **`smp` command**: Read BSP APIC ID (offset 0x20 >> 24), boot APs, show total CPUs online
  - 6 new functions: `_ke_smp_map_lapic`, `_ke_lapic_r/w`, `_ke_smp_trampoline`, `_ke_smp_boot`, `_ke_cmd_smp`
- **Iteration 35: AHCI/SATA Disk Controller Detection**
  - **PCI AHCI detection**: Scan bus 0 for class=0x01, subclass=0x06
  - **BAR5 (ABAR) read**: `_ke_pci_bar5()` — read PCI config register 0x24
  - **ABAR MMIO mapping**: `_ke_ahci_map()` — dynamic PD entry based on ABAR address
    - Computes PD index from 3rd-GB offset, writes 2MB page with P+RW+PS+PCD
  - **HBA register access**: `_ke_ahci_r/pr()` — read HBA global and per-port registers
  - **`ahci` command**: Full controller report:
    - Vendor:Device ID, ABAR address, AHCI version, port count
    - Per-port: DET (link status), SIG (device signature)
  - 5 new functions: `_ke_pci_bar5`, `_ke_ahci_map`, `_ke_ahci_r`, `_ke_ahci_pr`, `_ke_cmd_ahci`
- **Iteration 36: USB xHCI Controller Detection**
  - **PCI prog_if reader**: `_ke_pci_progif()` — distinguish xHCI (0x30) from UHCI/OHCI/EHCI
  - **BAR0 reader**: `_ke_pci_bar0()` — read xHCI MMIO base address
  - **Generic MMIO mapper**: `_ke_mmio_map(addr)` — dynamic PD entry for any 3rd-GB MMIO address
  - **xHCI capability parsing**: CAPLENGTH, HCIVERSION, HCSPARAMS1 (MaxSlots, MaxPorts)
  - **Port status scan**: PORTSC at op_base+0x400+port*0x10, CCS (connected), speed bits[13:10]
    - Speed codes: 1=FS(12M), 2=LS(1.5M), 3=HS(480M), 4=SS(5G)
  - **`usb` command**: Full xHCI report: Vendor:Device, BAR0, version, slots, ports, per-port status
  - 4 new functions: `_ke_pci_progif`, `_ke_pci_bar0`, `_ke_mmio_map`, `_ke_cmd_usb`
- **kernel.bin growth**: 19,146 bytes, 1,063 symbols, 1,079 functions, 18 shell commands
- **Shell commands (18)**: help tick pci pmem palloc pfree malloc mfree ps mouse tcptest gfxtest wm smp ahci usb wget reboot

### Iterations 18-21: Network + Graphics + User Mode (QEMU verified)
- **Iteration 18: DHCP + Ping + DNS + ifconfig**
  - `dhcp`: VirtIO-net TX Discover → RX Offer → yiaddr → IP stored at 0x3002A8
  - `ping`: ARP refresh → ICMP Echo Request (IP checksum) → poll Reply → "reply received"
  - `nslookup`: UDP DNS A-record query for example.com → parse answer → decimal IP
  - `ifconfig`: MAC display + DHCP IP 3-digit-per-octet decimal output
  - VirtIO-net RX: used ring polling + desc_id → buffer → EtherType/Protocol dispatch
- **Iteration 20: VESA 1024×768×32 framebuffer**
  - VBE mode set: Stage2 real mode INT 10h AX=4F01/4F02, mode 0x118 + LFB
  - Page table mapping: PDPT[3]→PD[488-489], 2×2MB large pages at 0xFD000000
  - `vesa` command: blue fill + white banner (624×40 pixels)
- **Iteration 21: Ring3 user mode switch**
  - SYSCALL MSRs: STAR (GDT segments) + LSTAR (entry) + FMASK (clear IF)
  - TSS: 104-byte TSS + GDT descriptor + LTR
  - `ring3`: IRETQ→0x8000 Ring3 → SYSCALL(1,'U') → SYSCALL(1,'3') → SYSCALL(0)→kernel
- **Shell commands expanded**: 12 → 18 (`ifconfig` `dhcp` `ping` `nslookup` `vesa` `ring3`)
- **rebuild-image.ps1**: 1,431 → 3,676 lines
- **hl-bootstrap.hl**: 4,487 → 4,630 lines (206 functions, 7 quadrants)
- **Gate test fix**: net test timeouts adjusted (DHCP 8s, DNS 8s) → 42/42 PASS

### Compilation Pipeline Initiative
- **Phase 1 PASSED**: 114 modules, 101,392 tokens, 995 functions — all tokenized ✓
- **hl-compile-pipeline.ps1**: 宿主侧完整 H-L 词法分析器 (关键字/字符串/注释/运算符)
  - 括号平衡校验 + 函数计数 + per-module 统计
  - `hl-bootstrap compile` 独立入口命令
  - 集成到 build 流程 (build → compile → rebuild)
- **PIPELINE_PLAN.hl**: 六阶段编译管线打通策划案 (Phase 1-6)
- **cmd_build()**: 模块列表从 55 扩展到完整 111 + 3 boot chain = 114 个 (依赖顺序)
- **build_kernel()**: 添加 pipeline 注释和模块计数感知
- **ir.hl**: 新增 AST→IR 降低层 (ir_lower_expr/ir_lower_stmt/ir_lower_module)
  - 支持: Num, Bool, Nil, Str, Var, BinOp (16 ops), Unary, Call
  - 支持: Let, Assign, FnDef, Return, If, While, Print, Quadrant
- **linker.hl**: 新建跨模块链接器 (符号表 + 重定位 + 两遍链接)
  - Pass 1: 收集符号 + 计算模块偏移
  - Pass 2: 解析 rel32/abs64 重定位
  - 字符串常量池 (.rodata 段)
- **Version bump**: banner/CLI/kernel_init 统一为 v5.0 (114 modules)

### QEMU End-to-End Verification (Iterations 11-15)
- **BIOS Boot 21/21**: MBR→Stage2→Long Mode→Kernel→9 subsystems→Shell prompt
- **VirtIO-blk**: PCI detect → BAR0 → virtqueue → sector read/write verify
- **VirtIO-net**: PCI detect → BAR0 → MAC read (52:54:00:12:34:56) → ARP broadcast
- **Multitask**: PIT 100Hz timer → dual-task A/B alternation verified
- **UEFI Boot 3/3**: OVMF → GPT+CRC32 → ESP FAT16 → PE32+ BOOTX64.EFI → serial+ConOut

### UEFI Support
- **build-uefi-image.ps1**: Generates complete UEFI bootable disk image from scratch
  - PE32+ EFI application (DOS header + COFF + Optional Header + .text + .reloc)
  - GPT with CRC32 checksums, 128 partition entries, backup GPT header/entries
  - FAT16 ESP filesystem (BPB + dual FAT + \EFI\BOOT\BOOTX64.EFI + startup.nsh)
- **BOOTX64.EFI**: 1,536 bytes, serial 0x3F8 output + EFI ConOut->OutputString
- **qemu-uefi-test.ps1**: Automated OVMF + QEMU UEFI boot test

### Image Rebuild
- **rebuild-image.ps1**: Correct Stage2 far JMP (0x66 prefix) + INT13h LBA extended read
- **hicos-hl.img**: 29,184 bytes (57 sectors) — fully functional BIOS boot
- **hicos-uefi.img**: 33 MB GPT disk with ESP FAT16

### New Kernel Modules
- **kinterp.hl**: In-kernel H-L interpreter (Lexer→Parser→Tree-walk evaluator, 689 lines)
- **nvme.hl**: NVMe 1.4 driver (Admin + I/O queue framework)
- **errno.hl**: POSIX error codes (35 errno values)
- **font.hl**: 8x16 bitmap font renderer

### Infrastructure
- **full-gate.ps1**: 7-check gate (workspace+boot+runtime+layout+binary+QEMU+bootstrap)
- **boot-binary-analysis.ps1**: 13-check MBR+Stage1+Stage2+Kernel binary validation
- 18 PowerShell build/test scripts total

## v4.5

100 kernel modules, 50 shell commands, 184 .hl files, 0 external deps.

### epoll: Red-Black Tree I/O Multiplexing (Phase 1.1)
- **poll.hl**: Complete rewrite — old O(n) stub replaced with production epoll
- **Red-Black Tree**: Array-backed RB tree for O(log n) fd insert/search/modify
  - Full left/right rotation + 3-case insert fixup (recolor, rotate-parent, rotate-grandparent)
  - Mirror-symmetric handling for left/right parent positions
  - Root-black invariant enforced after every insert
- **Ready List**: O(1) append + O(1) drain via `_ep_mark_ready` / `_ep_drain_ready`
- **Spatial locality**: `hilbert_encode(fd, epfd, 0)` hint for cache-friendly node allocation
- **API**: `sys_epoll_create`, `sys_epoll_ctl` (ADD/DEL/MOD), `sys_epoll_wait`, `sys_epoll_close`
- **Legacy**: `sys_poll` retained with activated `pipe_available` readiness check
- **Self-test**: 32 non-sequential fd inserts + search verify + mod + del + RB root-black check
- **Complexity**: insert O(log n), search O(log n), wait O(k) where k = ready count

## v4.4

100 kernel modules, 50 shell commands, 184 .hl files, 0 external deps.

### CFS Scheduler: O(n) → O(log n) min-heap
- **task.hl**: Replaced linear-scan `task_pick_next` with min-heap run queue
- New functions: `rq_insert`, `rq_pop_min`, `rq_peek_vruntime`, `rq_remove`, `rq_count`
- Internal: `_rq_sift_up`, `_rq_sift_down`, `_rq_swap` (classic binary heap)
- `task_create` → auto-inserts into heap; `task_kill` → removes from heap
- `context_switch` → re-inserts old task into heap with updated vruntime
- `task_pick_next` → O(1) peek + O(log n) pop (vs old O(n) full scan)
- Integrated self-test: insert 5 out-of-order tasks, verify pop order + remove + empty
- **Comparison**: matches Linux CFS O(log n) rbtree; HicOS uses min-heap (simpler, same complexity)

## v4.3

### v4.3 Highlights
- **usermode.hl**: TSS init with mem_zero, STAR MSR encoding resolved (GDT: null/kcode/kdata/udata/ucode64), IRETQ frame built in memory, syscall_entry protocol documented
- **posix.hl**: `sys_fork` fully activated (register copy, FD table copy, page table share), `sys_exec` loads ELF + resets FDs, `sys_wait` polls child state with timeout
- **syscall.hl**: 20+ syscalls dispatched (FORK/EXEC/WAIT/KILL/PIPE/SEND/RECV/OPEN/CLOSE/STAT/READDIR/MKDIR/UNLINK/BRK/IOCTL/VERSION), pointer validation via `syscall_validate_ptr`, ABI version SYS_VERSION=255
- **vfs.hl**: `vfs_init` auto-mounts ramfs+devfs, `vfs_open` searches free slot and dispatches to backend, `vfs_read`/`vfs_write` dispatch to ramfs, `vfs_seek`/`vfs_stat`/`vfs_readdir`/`vfs_mkdir`/`vfs_unlink` activated
- **Security**: SMEP/SMAP CR4 bits, syscall pointer bounds checking (-EFAULT)
- **THREE_SYSTEM_COMPARISON.md**: Full 4-dimension comparison vs Linux/Windows/macOS with atomic improvement plan

## v4.2

100 kernel modules, 50 shell commands, 184 .hl files, 0 external deps.

### Critical compiler bugs fixed in v4.2
- **`char_at` / `is_digit` / `is_alnum`**: These core tokenizer builtins were never registered — **self-hosting bootstrap could not compile itself**
- **`parse_number`**: Used by tokenizer to convert numeric strings but was never defined — all number literals would fail to parse during self-bootstrap
- **`ord`**: Returned raw string char instead of ASCII code when host uses string-indexed chars — broke `char_code_at` and all char→int conversions
- **`range`**: Only supported `range(n)`, now supports `range(start, end)` and `range(start, end, step)`
- **`**` power operator**: Failed on negative exponents (infinite loop) — now correctly computes `x^(-n) = 1/x^n`

### Kernel integration activated in v4.2
- **mem.hl**: Added `mem_read_i16` / `mem_write_i16` (signed 16-bit for audio PCM), `mem_write_string` / `mem_read_string`, `clamp`, `char_code_at`
- **syscall.hl**: Activated all core syscalls (SYS_EXIT/GETPID/WRITE/READ/MMAP/MUNMAP/SLEEP/UPTIME) — previously all returned 0
- **signal.hl**: Activated `signal_deliver` with actual pending/blocked bitmask scanning and SIGKILL/SIGTERM default action

## v4.1

### Bug fixes in v4.1
- **Compiler**: `self.name = value` field assignment was silently ignored (parsed as ExprStmt instead of FieldAssign) — **critical OOP bug**
- **Compiler**: `obj.method(args)` was resolved as global function lookup instead of class method dispatch — added MethodCall AST node with class hierarchy search
- **Compiler**: Fixed variadic `*args` parameter binding (was comparing char as int instead of string)
- **Compiler**: Variadic parameter names now correctly strip `*` prefix when binding to env
- **stdlib.hl**: `obj_call_method` returned the method object instead of calling it
- **stdlib.hl**: Added `array_last`/`array_first` utility functions
- **pipe.hl**: Fixed undefined variable BUG in `pipe_write`/`pipe_read` (wp, rp, count were used before declaration)
- **HicOS_FileSystem.hl**: Replaced JS `.split()/.pop()/.join()/.filter()` with native H-L `str_split`/`array_join`/`pop`
- **HicOS_SecurityManager.hl**: Replaced JS `crypto.subtle.digest` + `.map()/.join()` with native `sha256_hash` + hex encoding
- **icmp.hl**: Removed duplicate ARP functions (arp_lookup/arp_insert/arp_process_reply) that conflicted with arp.hl
- **rtc.hl**: Removed duplicate functions (rtc_read_reg/rtc_read_time/get_ticks) that conflicted with timer.hl
- **build.hl**: Added 5 missing modules (lint, boot, test, test-runner, posix_test)
- **pipe.hl**: Activated `pipe_create`, `pipe_available` (were returning stubs)
- **rtc.hl**: Activated `rtc_wait_ready` with actual timeout loop, `uptime_secs` now calls `get_ticks()`
- **README.md**: Fixed file counts (182→184, 99→100 kernel modules)

### New in v4.1
**H-L language features** (Python-level):
- `class` / single inheritance / magic methods (`__init__`, `__str__`, `__eq__`, `__call__`, etc.)
- `@decorator` syntax + built-in decorators (`@cache`, `@deprecated`, `@staticmethod`)
- `[expr for x in iter if cond]` list comprehensions
- `let [a, [b, c]] = expr` deep destructuring + `_` wildcard
- `yield` statement + generator coroutines
- `raise` statement + typed `catch e : TypeError { }` + multi-catch clauses
- `fn f(a: int, b: int) -> int` optional type hints
- Default parameters `fn f(a, b = 10)` + `*args` variadic
- `super(self)` parent class access

**stdlib.hl** (new): OOP utilities, generator tools, exception classes, decorator helpers, reduce

**Kernel modules activated**:
- 21 modules: all commented-out mem_write/mem_read calls activated
- tls.hl: full SHA-256 (64 rounds) + HMAC-SHA-256 + HKDF
- ext2.hl: inode read / directory listing / indirect blocks
- virt_mem.hl: pte_read/pte_write/alloc_page_table
- mouse.hl: overflow protection + dynamic screen bounds
- kernel_init.hl: activated page_alloc/hilbert_alloc/pci_scan/smp/shell

## v4.0

99 kernel modules, 49 shell commands, 182 .hl files, 0 external deps.

### New in v4.0
**Native compiler pipeline**: ir.hl (H-IR + const-fold/DCE/strength-reduce),
regalloc.hl (linear-scan, 14 GP regs), abi.hl (System V AMD64),
codegen.hl (AST→IR→x86_64 with If/While/Call).
x86 encoder expanded to 126 instructions (LEA, CMOV, BSF/BSR, POPCNT, RDTSC, fences).

sysfs, http, shm, eventfd, trace, hrtimer,
pty, socket, netfilter, random, cgroup, inotify,
mmap, poll, tmpfs, ntp, block_cache, watchdog,
ipv6, udp, mixer, syslog, login,
gpu, ntfs, ext2, ext4, tls, users, usb_storage, usb_hid, usb_hub,
posix, pipe, wm, wifi, bluetooth, rtc, procfs, env, firmware,
terminal, multimon, arp, posix_test

### Shell commands (49)
help ver uptime date free heap ps cpus mount lspci ifconfig
ls cat echo fib hilbert clear reboot shutdown ping dns arp dev panic
whoami id uname lsusb beep env proc meminfo mounts dmesg mixer ip6
cache ntp wdog tmpfs fw rand cg pty sock shm trace hrt sysfs

## v3.1
51 kernel modules. Boot, memory, tasks, FS, net, devices, shell (24 cmds).

## v2.0
x86_64 encoder (119 instructions). 6KB bootable image.

## v1.0
H-L self-hosting compiler. Hilbert-curve spatial addressing.

## Roadmap

### v4.1
- Graphical login screen, copy-on-write fork, USB isochronous, HTTP/2

### v5.0
- Native H-L GUI framework, package manager, hardware GPU shaders, Btrfs/ZFS


