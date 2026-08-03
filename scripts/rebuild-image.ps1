# rebuild-image.ps1 -- Rebuild the BIOS boot image `hicos-hl.img`
#
# Host-side image layout:
#   Stage1 (MBR) + Stage2 (real→long mode loader) + kernel payload
#
# This remains a temporary host-side builder until `hl-bootstrap.hl`
# can own the full image build path again.

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

# === Buffer helpers ===
$script:buf = [System.Collections.ArrayList]::new()

function buf_emit([byte]$b) { [void]$script:buf.Add($b) }
function buf_emit16([uint16]$v) { buf_emit ($v -band 0xFF); buf_emit (($v -shr 8) -band 0xFF) }
function buf_emit32_signed([int64]$v) {
    # Emit 32-bit value allowing negative (two's complement)
    $bytes = [System.BitConverter]::GetBytes([int32]$v)
    foreach ($b in $bytes) { buf_emit $b }
}
function buf_emit32([int64]$v) {
    $bytes = [System.BitConverter]::GetBytes([int32]($v -band [int64]0xFFFFFFFF))
    foreach ($b in $bytes) { buf_emit $b }
}
function buf_len { return $script:buf.Count }
function buf_pad_to([int]$target) { while ($script:buf.Count -lt $target) { buf_emit 0 } }
function buf_set([int]$idx, [byte]$val) { $script:buf[$idx] = $val }

# === Instruction emitters ===
function emit_cli { buf_emit 0xFA }
function emit_sti { buf_emit 0xFB }
function emit_hlt { buf_emit 0xF4 }
function emit_cld { buf_emit 0xFC }
function emit_nop { buf_emit 0x90 }
function emit_ret { buf_emit 0xC3 }

# Real mode
function emit_xor_ax_ax { buf_emit 0x31; buf_emit 0xC0 }
function emit_mov_ds_ax { buf_emit 0x8E; buf_emit 0xD8 }
function emit_mov_es_ax { buf_emit 0x8E; buf_emit 0xC0 }
function emit_mov_ss_ax { buf_emit 0x8E; buf_emit 0xD0 }
function emit_mov_sp_imm16([uint16]$v) { buf_emit 0xBC; buf_emit16 $v }
function emit_mov_ah_imm8([byte]$v) { buf_emit 0xB4; buf_emit $v }
function emit_mov_al_imm8([byte]$v) { buf_emit 0xB0; buf_emit $v }
function emit_mov_bx_imm16([uint16]$v) { buf_emit 0xBB; buf_emit16 $v }
function emit_mov_ch_imm8([byte]$v) { buf_emit 0xB5; buf_emit $v }
function emit_mov_cl_imm8([byte]$v) { buf_emit 0xB1; buf_emit $v }
function emit_mov_dh_imm8([byte]$v) { buf_emit 0xB6; buf_emit $v }
function emit_mov_dl_imm8([byte]$v) { buf_emit 0xB2; buf_emit $v }
function emit_mov_dx_imm16([uint16]$v) { buf_emit 0xBA; buf_emit16 $v }
function emit_mov_di_imm16([uint16]$v) { buf_emit 0xBF; buf_emit16 $v }
function emit_int([byte]$n) { buf_emit 0xCD; buf_emit $n }
function emit_jmp_far16([uint16]$seg, [uint16]$off) { buf_emit 0xEA; buf_emit16 $off; buf_emit16 $seg }

# 32-bit
function emit_mov_eax_imm32([int64]$v) { buf_emit 0xB8; buf_emit32 $v }
function emit_mov_ecx_imm32([int64]$v) { buf_emit 0xB9; buf_emit32 $v }
function emit_mov_edx_imm32([int64]$v) { buf_emit 0xBA; buf_emit32 $v }
function emit_mov_edi_imm32([int64]$v) { buf_emit 0xBF; buf_emit32 $v }
function emit_mov_cr0_eax { buf_emit 0x0F; buf_emit 0x22; buf_emit 0xC0 }
function emit_mov_eax_cr0 { buf_emit 0x0F; buf_emit 0x20; buf_emit 0xC0 }
function emit_mov_cr3_eax { buf_emit 0x0F; buf_emit 0x22; buf_emit 0xD8 }
function emit_mov_eax_cr4 { buf_emit 0x0F; buf_emit 0x20; buf_emit 0xE0 }
function emit_mov_cr4_eax { buf_emit 0x0F; buf_emit 0x22; buf_emit 0xE0 }
function emit_bts_eax([byte]$bit) { buf_emit 0x0F; buf_emit 0xBA; buf_emit 0xE8; buf_emit $bit }
function emit_xor_eax_eax { buf_emit 0x31; buf_emit 0xC0 }
function emit_rep_stosd { buf_emit 0xF3; buf_emit 0xAB }
function emit_mov_mem_edi_eax { buf_emit 0x89; buf_emit 0x07 }
function emit_or_al_imm8([byte]$v) { buf_emit 0x0C; buf_emit $v }
function emit_lgdt_imm16([uint16]$a) { buf_emit 0x0F; buf_emit 0x01; buf_emit 0x16; buf_emit16 $a }
function emit_jmp_far32([uint16]$seg, [uint32]$off) { buf_emit 0xEA; buf_emit32 $off; buf_emit16 $seg }
function emit_mov_ax_imm16_32 { buf_emit 0x66; buf_emit 0xB8; buf_emit16 16 }
function emit_in_al_imm8([byte]$p) { buf_emit 0xE4; buf_emit $p }
function emit_out_imm8_al([byte]$p) { buf_emit 0xE6; buf_emit $p }
function emit_test_al_imm8([byte]$v) { buf_emit 0xA8; buf_emit $v }
function emit_rdmsr { buf_emit 0x0F; buf_emit 0x32 }
function emit_wrmsr { buf_emit 0x0F; buf_emit 0x30 }
function emit_in_al_dx { buf_emit 0xEC }
function emit_out_dx_al { buf_emit 0xEE }

# 64-bit
function emit_mov_rsp_imm64([uint64]$v) {
    buf_emit 0x48; buf_emit 0xBC
    buf_emit32 ([uint32]($v -band 0xFFFFFFFF))
    buf_emit32 ([uint32](($v -shr 32) -band 0xFFFFFFFF))
}
function emit_mov_rax_imm64([uint64]$v) {
    buf_emit 0x48; buf_emit 0xB8
    buf_emit32 ([uint32]($v -band 0xFFFFFFFF))
    buf_emit32 ([uint32](($v -shr 32) -band 0xFFFFFFFF))
}
function emit_jmp_rax { buf_emit 0xFF; buf_emit 0xE0 }
function emit_push_r64([byte]$r) { buf_emit ([byte](0x50 + $r)) }
function emit_pop_r64([byte]$r) { buf_emit ([byte](0x58 + $r)) }
function emit_iretq { buf_emit 0x48; buf_emit 0xCF }

# Serial string emitter
function emit_serial_string([string]$text, [uint32]$com1) {
    foreach ($ch in $text.ToCharArray()) {
        $code = [int]$ch
        # Wait for TX buffer empty
        emit_mov_edx_imm32 ($com1 + 5)
        emit_in_al_dx
        emit_test_al_imm8 0x20
        buf_emit 0x74; buf_emit 0xF6  # JZ -10
        # Send character
        emit_mov_edx_imm32 $com1
        emit_mov_al_imm8 ([byte]$code)
        emit_out_dx_al
    }
}

# Print EAX as 8-digit hex to serial (destroys eax,ecx,edx,r8)
function emit_serial_hex_eax([uint32]$com1) {
    # Save EAX in R8D
    buf_emit 0x41; buf_emit 0x89; buf_emit 0xC0  # mov r8d, eax
    # We'll process 8 nibbles (high to low)
    # mov ecx, 28 (shift count for first nibble)
    buf_emit 0xB9; buf_emit32 28

    # loop_top:
    $hex_loop = buf_len
    # mov eax, r8d
    buf_emit 0x44; buf_emit 0x89; buf_emit 0xC0  # mov eax, r8d
    # shr eax, cl
    buf_emit 0xD3; buf_emit 0xE8  # shr eax, cl
    # and al, 0xF
    buf_emit 0x24; buf_emit 0x0F
    # cmp al, 10
    buf_emit 0x3C; buf_emit 10
    buf_emit 0x72; buf_emit 2  # jb .digit
    buf_emit 0x04; buf_emit 7  # add al, 7 ('A'-'0'-10)
    # .digit: add al, '0'
    buf_emit 0x04; buf_emit 0x30
    # Save nibble char in r9b
    buf_emit 0x41; buf_emit 0x88; buf_emit 0xC1  # mov r9b, al
    # Wait TX ready
    emit_mov_edx_imm32 ($com1 + 5)
    emit_in_al_dx
    emit_test_al_imm8 0x20
    buf_emit 0x74; buf_emit 0xF6  # jz -10
    # Send char
    emit_mov_edx_imm32 $com1
    buf_emit 0x44; buf_emit 0x88; buf_emit 0xC8  # mov al, r9b
    emit_out_dx_al
    # sub ecx, 4; jge loop_top
    buf_emit 0x83; buf_emit 0xE9; buf_emit 4  # sub ecx, 4
    buf_emit 0x7D  # jge loop_top
    buf_emit ([byte](($hex_loop - (buf_len) - 1) -band 0xFF))
}

# Command string comparison: emit byte-by-byte cmp of [rsi+i] vs each char + null
# RSI must be 0x300800. Stores jne patch locations in $script:cmd_patches.
function emit_cmd_check([string]$cmd) {
    $script:cmd_patches = @()
    for ($i = 0; $i -lt $cmd.Length; $i++) {
        $ch = [byte][char]$cmd[$i]
        if ($i -eq 0) {
            buf_emit 0x80; buf_emit 0x3E; buf_emit $ch          # cmp byte [rsi], ch
        } else {
            buf_emit 0x80; buf_emit 0x7E; buf_emit ([byte]$i); buf_emit $ch  # cmp byte [rsi+i], ch
        }
        $script:cmd_patches += (buf_len)
        buf_emit 0x0F; buf_emit 0x85; buf_emit32 0              # jne skip (patched)
    }
    $n = [byte]$cmd.Length
    if ($n -eq 0) {
        buf_emit 0x80; buf_emit 0x3E; buf_emit 0
    } else {
        buf_emit 0x80; buf_emit 0x7E; buf_emit $n; buf_emit 0   # cmp byte [rsi+n], 0
    }
    $script:cmd_patches += (buf_len)
    buf_emit 0x0F; buf_emit 0x85; buf_emit32 0                  # jne skip (patched)
}

function emit_cmd_prefix_check([string]$prefix) {
    $script:cmd_patches = @()
    for ($i = 0; $i -lt $prefix.Length; $i++) {
        $ch = [byte][char]$prefix[$i]
        if ($i -eq 0) {
            buf_emit 0x80; buf_emit 0x3E; buf_emit $ch
        } else {
            buf_emit 0x80; buf_emit 0x7E; buf_emit ([byte]$i); buf_emit $ch
        }
        $script:cmd_patches += (buf_len)
        buf_emit 0x0F; buf_emit 0x85; buf_emit32 0
    }
}

# Patch all jne's from last emit_cmd_check to jump to current position
function patch_cmd_skip {
    $target = buf_len
    foreach ($loc in $script:cmd_patches) {
        $rel = $target - $loc - 6
        $bytes = [System.BitConverter]::GetBytes([int32]$rel)
        buf_set ($loc + 2) $bytes[0]
        buf_set ($loc + 3) $bytes[1]
        buf_set ($loc + 4) $bytes[2]
        buf_set ($loc + 5) $bytes[3]
    }
}

# Print AL as 2-digit hex byte to serial (destroys eax,ecx,edx,r9)
function emit_serial_hex_byte([uint32]$com1) {
    # Save AL in R9B
    buf_emit 0x41; buf_emit 0x88; buf_emit 0xC1  # mov r9b, al
    # High nibble
    buf_emit 0xC0; buf_emit 0xE8; buf_emit 4  # shr al, 4
    buf_emit 0x24; buf_emit 0x0F  # and al, 0xF
    buf_emit 0x3C; buf_emit 10; buf_emit 0x72; buf_emit 2; buf_emit 0x04; buf_emit 7  # cmp/jb/add
    buf_emit 0x04; buf_emit 0x30  # add al, '0'
    buf_emit 0x41; buf_emit 0x88; buf_emit 0xC2  # mov r10b, al (save char)
    emit_mov_edx_imm32 ($com1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
    buf_emit 0x74; buf_emit 0xF6
    emit_mov_edx_imm32 $com1
    buf_emit 0x44; buf_emit 0x88; buf_emit 0xD0  # mov al, r10b
    emit_out_dx_al
    # Low nibble
    buf_emit 0x44; buf_emit 0x88; buf_emit 0xC8  # mov al, r9b
    buf_emit 0x24; buf_emit 0x0F  # and al, 0xF
    buf_emit 0x3C; buf_emit 10; buf_emit 0x72; buf_emit 2; buf_emit 0x04; buf_emit 7
    buf_emit 0x04; buf_emit 0x30
    buf_emit 0x41; buf_emit 0x88; buf_emit 0xC2  # mov r10b, al
    emit_mov_edx_imm32 ($com1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
    buf_emit 0x74; buf_emit 0xF6
    emit_mov_edx_imm32 $com1
    buf_emit 0x44; buf_emit 0x88; buf_emit 0xD0  # mov al, r10b
    emit_out_dx_al
}

function emit_serial_dec_byte_from_abs32([uint32]$addr, [uint32]$com1) {
    buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x25; buf_emit32 $addr
    buf_emit 0x31; buf_emit 0xD2
    buf_emit 0xB9; buf_emit32 100
    buf_emit 0xF7; buf_emit 0xF1
    buf_emit 0x04; buf_emit 0x30
    buf_emit 0x50
    emit_mov_edx_imm32 ($com1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
    buf_emit 0x74; buf_emit 0xF6
    buf_emit 0x58
    emit_mov_edx_imm32 $com1; emit_out_dx_al

    buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x25; buf_emit32 $addr
    buf_emit 0x31; buf_emit 0xD2; buf_emit 0xB9; buf_emit32 100; buf_emit 0xF7; buf_emit 0xF1
    buf_emit 0x89; buf_emit 0xD0
    buf_emit 0x31; buf_emit 0xD2; buf_emit 0xB9; buf_emit32 10; buf_emit 0xF7; buf_emit 0xF1
    buf_emit 0x04; buf_emit 0x30
    buf_emit 0x50
    emit_mov_edx_imm32 ($com1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
    buf_emit 0x74; buf_emit 0xF6
    buf_emit 0x58
    emit_mov_edx_imm32 $com1; emit_out_dx_al

    buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x25; buf_emit32 $addr
    buf_emit 0x31; buf_emit 0xD2; buf_emit 0xB9; buf_emit32 10; buf_emit 0xF7; buf_emit 0xF1
    buf_emit 0x89; buf_emit 0xD0; buf_emit 0x04; buf_emit 0x30
    buf_emit 0x50
    emit_mov_edx_imm32 ($com1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
    buf_emit 0x74; buf_emit 0xF6
    buf_emit 0x58
    emit_mov_edx_imm32 $com1; emit_out_dx_al
}

function emit_stage2_kernel_read_chs_loop([uint16]$kernelSectors) {
    buf_emit 0xB9; buf_emit16 $kernelSectors                 # mov cx, total kernel sectors
    $kernelLbaPatch = (buf_len) + 1
    buf_emit 0xBF; buf_emit16 0                              # mov di, first kernel LBA (patched)
    $loadSegPatch = (buf_len) + 4
    buf_emit 0xC7; buf_emit 0x06; buf_emit16 0x0590; buf_emit16 0  # mov word [0x590], load segment (patched)

    $readLoopOff = buf_len
    buf_emit 0x85; buf_emit 0xC9                             # test cx, cx
    buf_emit 0x74; $jeDonePatch = buf_len; buf_emit 0        # je done
    buf_emit 0x51                                            # push cx
    buf_emit 0x57                                            # push di
    buf_emit 0x89; buf_emit 0xF8                             # mov ax, di
    buf_emit 0x31; buf_emit 0xD2                             # xor dx, dx
    buf_emit 0xBB; buf_emit16 63                             # mov bx, 63
    buf_emit 0xF7; buf_emit 0xF3                             # div bx
    buf_emit 0x88; buf_emit 0xD1                             # mov cl, dl
    buf_emit 0xFE; buf_emit 0xC1                             # inc cl (sector = rem + 1)
    buf_emit 0x31; buf_emit 0xD2                             # xor dx, dx
    buf_emit 0xBB; buf_emit16 16                             # mov bx, 16
    buf_emit 0xF7; buf_emit 0xF3                             # div bx
    buf_emit 0x88; buf_emit 0xD6                             # mov dh, dl (head)
    buf_emit 0x88; buf_emit 0xC5                             # mov ch, al (cylinder)
    buf_emit 0xA1; buf_emit16 0x0590                         # mov ax, [0x590]
    buf_emit 0x8E; buf_emit 0xC0                             # mov es, ax
    buf_emit 0xBB; buf_emit16 0                              # mov bx, 0
    emit_mov_ah_imm8 0x02
    emit_mov_al_imm8 1
    emit_mov_dl_imm8 0x80
    emit_int 0x13
    buf_emit 0x5F                                            # pop di
    buf_emit 0x59                                            # pop cx
    buf_emit 0x47                                            # inc di
    buf_emit 0x49                                            # dec cx
    buf_emit 0x83; buf_emit 0x06; buf_emit16 0x0590; buf_emit 32  # add word [0x590], 32 paragraphs
    $jmpBackRel = $readLoopOff - (buf_len + 2)
    buf_emit 0xEB; buf_emit ([byte]($jmpBackRel -band 0xFF))

    $readDoneOff = buf_len
    buf_set $jeDonePatch ([byte]($readDoneOff - $jeDonePatch - 1))

    return [PSCustomObject]@{
        KernelLbaPatch = $kernelLbaPatch
        LoadSegPatch = $loadSegPatch
    }
}

function emit_stage1_load_stage2_chs([byte]$stage2Sectors, [uint16]$loadOffset) {
    emit_mov_ah_imm8 0x02
    emit_mov_al_imm8 $stage2Sectors
    emit_mov_ch_imm8 0
    emit_mov_cl_imm8 2
    emit_mov_dh_imm8 0
    emit_mov_dl_imm8 0x80
    emit_mov_bx_imm16 $loadOffset
    emit_int 0x13
}

function emit_virtq_push_desc0_from_abs([uint32]$availBaseAddr, [uint32]$availIdxAddr) {
    buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 $availBaseAddr  # mov edi, [avail_base]
    buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x04; buf_emit 0x25; buf_emit32 $availIdxAddr  # movzx eax, word [avail_idx]
    buf_emit 0x89; buf_emit 0xC1                    # mov ecx, eax
    buf_emit 0xD1; buf_emit 0xE1                    # shl ecx, 1 (idx*2)
    buf_emit 0x83; buf_emit 0xC1; buf_emit 4        # add ecx, 4
    buf_emit 0x66; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x0F; buf_emit16 0  # mov word [rdi+rcx], 0
    buf_emit 0xFF; buf_emit 0xC0                    # inc eax
    buf_emit 0x66; buf_emit 0x89; buf_emit 0x47; buf_emit 2  # mov word [rdi+2], ax
    buf_emit 0x66; buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 $availIdxAddr
}

function emit_virtio_notify_queue_from_bar_abs([uint32]$barAddr, [byte]$queueIndex) {
    buf_emit 0x0F; buf_emit 0xAE; buf_emit 0xF0    # mfence
    buf_emit 0x8B; buf_emit 0x1C; buf_emit 0x25; buf_emit32 $barAddr  # mov ebx, [BAR]
    buf_emit 0x8D; buf_emit 0x53; buf_emit 0x10    # lea edx, [rbx+16]
    buf_emit 0xB0; buf_emit $queueIndex; buf_emit 0xEE  # mov al, queue; out dx, al
}

function emit_virtq_poll_used_loop {
    buf_emit 0xBA; buf_emit32 0x200000              # mov edx, 2M (timeout)
    $poll_top = buf_len
    buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 2  # movzx eax, word [rdi+2]
    buf_emit 0x39; buf_emit 0xC8                    # cmp eax, ecx
    buf_emit 0x7D; buf_emit 4                       # jge done
    buf_emit 0xFF; buf_emit 0xCA                    # dec edx
    buf_emit 0x75                                    # jnz poll
    buf_emit ([byte](($poll_top - (buf_len) - 1) -band 0xFF))
}

function emit_virtq_poll_used_from_abs([uint32]$availIdxAddr, [uint32]$usedBaseAddr) {
    buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 $availIdxAddr  # movzx ecx, word [avail_idx]
    buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 $usedBaseAddr                 # mov edi, [used_base]
    emit_virtq_poll_used_loop
}

Write-Host '=== Rebuilding hicos-hl.img ===' -ForegroundColor Cyan

# === Early read of kernel.bin entry offset (needed during kernel codegen at CALL _start) ===
$kernelBinPath = Join-Path $PSScriptRoot '..\bare-kernel\kernel.bin'
$kernelEntryPath = Join-Path $PSScriptRoot '..\bare-kernel\kernel.entry'
$kb_entry_offset = -1
if ((Test-Path $kernelBinPath) -and (Test-Path $kernelEntryPath)) {
    $kb_entry_offset = [int]([System.IO.File]::ReadAllText($kernelEntryPath).Trim())
    Write-Host "  Early read: kernel.entry offset = $kb_entry_offset" -ForegroundColor DarkGray
}

# =========================================
# Build Kernel
# =========================================
$script:buf = [System.Collections.ArrayList]::new()
$COM1 = [uint32]0x3F8

# --- VGA Text Mode state addresses ---
# 0x300900: vga_row, 0x300908: vga_col (tracked by kernel)
$VGA_TEXT_BASE = [uint32]0xB8000
$VGA_ROW_ADDR = [uint32]0x300900
$VGA_COL_ADDR = [uint32]0x300908

# Helper: emit VGA text-mode string write (white on black)
# Writes string directly to VGA text buffer and advances cursor.
# Destroys: RDI, RSI, RAX, RCX, RDX. Preserves: RBX.
function emit_vga_string([string]$text) {
    foreach ($ch in $text.ToCharArray()) {
        $code = [int]$ch
        if ($code -eq 13) { continue }  # skip CR, handle LF only
        if ($code -eq 10) {
            # Newline: col=0, row++
            # mov qword [VGA_COL_ADDR], 0
            buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25
            buf_emit32 $VGA_COL_ADDR; buf_emit32 0
            # inc qword [VGA_ROW_ADDR]
            buf_emit 0x48; buf_emit 0xFF; buf_emit 0x04; buf_emit 0x25
            buf_emit32 $VGA_ROW_ADDR
            continue
        }
        # Calculate offset: (row * 80 + col) * 2
        # mov rax, [VGA_ROW_ADDR]
        buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_ROW_ADDR
        # imul rax, 80
        buf_emit 0x48; buf_emit 0x6B; buf_emit 0xC0; buf_emit 80
        # add rax, [VGA_COL_ADDR]
        buf_emit 0x48; buf_emit 0x03; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_COL_ADDR
        # shl rax, 1  (multiply by 2)
        buf_emit 0x48; buf_emit 0xD1; buf_emit 0xE0
        # mov rdi, VGA_TEXT_BASE; add rdi, rax
        buf_emit 0x48; buf_emit 0xBF; buf_emit32 $VGA_TEXT_BASE; buf_emit32 0
        buf_emit 0x48; buf_emit 0x01; buf_emit 0xC7  # add rdi, rax
        # mov byte [rdi], char
        buf_emit 0xC6; buf_emit 0x07; buf_emit ([byte]$code)
        # mov byte [rdi+1], 0x07 (light gray on black)
        buf_emit 0xC6; buf_emit 0x47; buf_emit 1; buf_emit 0x07
        # inc qword [VGA_COL_ADDR]
        buf_emit 0x48; buf_emit 0xFF; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_COL_ADDR
    }
}

# Helper: emit dual output (serial + VGA)
function emit_dual_string([string]$text, [uint32]$com1) {
    emit_serial_string $text $com1
    emit_vga_string $text
}

# --- Initialize VGA cursor state ---
# mov qword [VGA_ROW_ADDR], 0
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25
buf_emit32 $VGA_ROW_ADDR; buf_emit32 0
# mov qword [VGA_COL_ADDR], 0
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25
buf_emit32 $VGA_COL_ADDR; buf_emit32 0

# --- Serial port init (COM1 38400 8N1) ---
emit_mov_edx_imm32 ($COM1 + 1); emit_mov_al_imm8 0; emit_out_dx_al    # disable interrupts
emit_mov_edx_imm32 ($COM1 + 3); emit_mov_al_imm8 0x80; emit_out_dx_al # DLAB on
emit_mov_edx_imm32 $COM1; emit_mov_al_imm8 3; emit_out_dx_al          # baud divisor lo=3
emit_mov_edx_imm32 ($COM1 + 1); emit_mov_al_imm8 0; emit_out_dx_al    # baud divisor hi=0
emit_mov_edx_imm32 ($COM1 + 3); emit_mov_al_imm8 3; emit_out_dx_al    # 8N1
emit_mov_edx_imm32 ($COM1 + 2); emit_mov_al_imm8 0xC7; emit_out_dx_al # FIFO
emit_mov_edx_imm32 ($COM1 + 4); emit_mov_al_imm8 0x0B; emit_out_dx_al # IRQ + RTS/DSR

# --- Boot banner (dual output: serial + VGA monitor) ---
emit_dual_string "HicOS 6.0 -- Hilbert-Lang Kernel`r`n" $COM1
emit_dual_string "=== Kernel Init ===`r`n" $COM1
emit_dual_string "  [ok] Serial: COM1 38400 8N1`r`n" $COM1

# --- Remap PIC ---
emit_mov_edx_imm32 0x20; emit_mov_al_imm8 0x11; emit_out_dx_al   # PIC1 ICW1
emit_mov_edx_imm32 0xA0; emit_mov_al_imm8 0x11; emit_out_dx_al   # PIC2 ICW1
emit_mov_edx_imm32 0x21; emit_mov_al_imm8 0x20; emit_out_dx_al   # PIC1 ICW2: IRQ0→vec32
emit_mov_edx_imm32 0xA1; emit_mov_al_imm8 0x28; emit_out_dx_al   # PIC2 ICW2: IRQ8→vec40
emit_mov_edx_imm32 0x21; emit_mov_al_imm8 4; emit_out_dx_al      # PIC1 ICW3: cascade
emit_mov_edx_imm32 0xA1; emit_mov_al_imm8 2; emit_out_dx_al      # PIC2 ICW3: cascade
emit_mov_edx_imm32 0x21; emit_mov_al_imm8 1; emit_out_dx_al      # PIC1 ICW4: 8086
emit_mov_edx_imm32 0xA1; emit_mov_al_imm8 1; emit_out_dx_al      # PIC2 ICW4: 8086
emit_mov_edx_imm32 0x21; emit_mov_al_imm8 0xFC; emit_out_dx_al   # unmask IRQ0+1
emit_mov_edx_imm32 0xA1; emit_mov_al_imm8 0xFF; emit_out_dx_al   # mask PIC2
emit_dual_string "  [ok] PIC: 8259A remapped`r`n" $COM1

# --- PIT 100Hz ---
emit_mov_edx_imm32 0x43; emit_mov_al_imm8 0x36; emit_out_dx_al   # PIT cmd
emit_mov_edx_imm32 0x40; emit_mov_al_imm8 0x9C; emit_out_dx_al   # divisor lo
emit_mov_al_imm8 0x2E; emit_out_dx_al                              # divisor hi
emit_dual_string "  [ok] PIT: 100 Hz timer`r`n" $COM1

# --- Build IDT at 0x200000 ---
$idt_base = [uint32]0x200000
$isr_base = [uint32]0x210000

# Generate ISR stub code
$isr_buf_saved = $script:buf
$script:buf = [System.Collections.ArrayList]::new()

$err_vecs = @(8, 10, 11, 12, 13, 14, 17, 21, 29, 30)
$common_off = 256 * 16

for ($vec = 0; $vec -lt 256; $vec++) {
    if ($vec -notin $err_vecs) {
        buf_emit 0x6A; buf_emit 0  # push 0 (dummy error)
    }
    buf_emit 0x6A; buf_emit ([byte]($vec -band 0xFF))  # push vector#
    buf_emit 0xE9  # JMP rel32
    $jmp_target = $common_off - (buf_len) - 4
    buf_emit32_signed $jmp_target
    # Pad to 16 bytes
    while ((buf_len) -lt ($vec + 1) * 16) { emit_nop }
}

# Common ISR handler
emit_push_r64 0; emit_push_r64 1; emit_push_r64 2; emit_push_r64 3
emit_push_r64 6; emit_push_r64 7
for ($ri = 8; $ri -le 15; $ri++) { buf_emit 0x41; buf_emit ([byte](0x50 + $ri - 8)) }

# mov rdi, [rsp+112] (vector number)
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x7C; buf_emit 0x24; buf_emit 112
# mov rsi, [rsp+120] (error code)
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x74; buf_emit 0x24; buf_emit 120

# Check timer (vec 32): cmp rdi, 32
buf_emit 0x48; buf_emit 0x83; buf_emit 0xFF; buf_emit 32
$jne_skip_tick_patch = buf_len
buf_emit 0x75; buf_emit 0  # jne skip_tick (patched)

# inc qword [0x300000] (tick counter)
buf_emit 0x48; buf_emit 0xFF; buf_emit 0x04; buf_emit 0x25
buf_emit32 0x300000

# Check if tick % 100 == 0 → set heartbeat flag at 0x300020
# mov rax, [0x300000]
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300000
# Push/use rcx for mod: mov rcx, 100; xor rdx,rdx; div rcx; test rdx,rdx
buf_emit 0x48; buf_emit 0xB9; buf_emit32 100; buf_emit32 0  # mov rcx, 100
buf_emit 0x48; buf_emit 0x31; buf_emit 0xD2                  # xor rdx, rdx
buf_emit 0x48; buf_emit 0xF7; buf_emit 0xF1                  # div rcx (rax=quo, rdx=rem)
buf_emit 0x48; buf_emit 0x85; buf_emit 0xD2                  # test rdx, rdx
$jnz_no_heartbeat_patch = buf_len
buf_emit 0x75; buf_emit 0   # jnz no_heartbeat (patched)
# Set heartbeat flag: mov qword [0x300020], 1
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25
buf_emit32 0x300020; buf_emit32 1
# inc qword [0x300028] (heartbeat counter = seconds)
buf_emit 0x48; buf_emit 0xFF; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300028
# Set task_id = seconds & 1 (alternating 0/1) at [0x300030]
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300028
buf_emit 0x48; buf_emit 0x83; buf_emit 0xE0; buf_emit 1  # and rax, 1
buf_emit 0x48; buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300030
# no_heartbeat:
$no_heartbeat_off = buf_len
buf_set ($jnz_no_heartbeat_patch + 1) ([byte](($no_heartbeat_off - $jnz_no_heartbeat_patch - 2) -band 0xFF))

# jmp send_eoi
$jmp_eoi_patch1 = buf_len
buf_emit 0xEB; buf_emit 0  # patched below

# skip_tick:
$skip_tick_off = buf_len
buf_set ($jne_skip_tick_patch + 1) ([byte](($skip_tick_off - $jne_skip_tick_patch - 2) -band 0xFF))

# Check keyboard (vec 33): cmp rdi, 33
buf_emit 0x48; buf_emit 0x83; buf_emit 0xFF; buf_emit 33
$jne_skip_kbd_patch = buf_len
buf_emit 0x75; buf_emit 0  # jne send_eoi (patched)
# in al, 0x60
buf_emit 0xE4; buf_emit 0x60
# movzx rax, al
buf_emit 0x48; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0xC0
# mov [0x300008], rax
buf_emit 0x48; buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300008
# mov qword [0x300010], 1
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300010; buf_emit32 1

# send_eoi:
$send_eoi_off = buf_len
# Patch all jumps to send_eoi
buf_set ($jmp_eoi_patch1 + 1) ([byte](($send_eoi_off - $jmp_eoi_patch1 - 2) -band 0xFF))
buf_set ($jne_skip_kbd_patch + 1) ([byte](($send_eoi_off - $jne_skip_kbd_patch - 2) -band 0xFF))

emit_mov_al_imm8 0x20; buf_emit 0xE6; buf_emit 0x20
# if vec >= 40 also PIC2
buf_emit 0x48; buf_emit 0x83; buf_emit 0xFF; buf_emit 40
buf_emit 0x72; buf_emit 4  # jb skip_pic2
emit_mov_al_imm8 0x20; buf_emit 0xE6; buf_emit 0xA0

# Restore regs
for ($ri = 15; $ri -ge 8; $ri--) { buf_emit 0x41; buf_emit ([byte](0x58 + $ri - 8)) }
emit_pop_r64 7; emit_pop_r64 6; emit_pop_r64 3; emit_pop_r64 2
emit_pop_r64 1; emit_pop_r64 0
# add rsp, 16
buf_emit 0x48; buf_emit 0x83; buf_emit 0xC4; buf_emit 16
emit_iretq

$isr_bytes = [byte[]]$script:buf.ToArray()
$script:buf = $isr_buf_saved

# Build IDT entries as raw data
$idt_data = [byte[]]::new(256 * 16)
for ($vec = 0; $vec -lt 256; $vec++) {
    $handler = [uint32]($isr_base + $vec * 16)
    $idt_off = $vec * 16
    $lo16 = [uint16]($handler -band 0xFFFF)
    $mid16 = [uint16](($handler -shr 16) -band 0xFFFF)
    $idt_data[$idt_off + 0] = [byte]($lo16 -band 0xFF)
    $idt_data[$idt_off + 1] = [byte](($lo16 -shr 8) -band 0xFF)
    $idt_data[$idt_off + 2] = 0x18  # selector lo
    $idt_data[$idt_off + 3] = 0x00  # selector hi
    $idt_data[$idt_off + 4] = 0x00  # IST
    $idt_data[$idt_off + 5] = 0x8E  # type_attr
    $idt_data[$idt_off + 6] = [byte]($mid16 -band 0xFF)
    $idt_data[$idt_off + 7] = [byte](($mid16 -shr 8) -band 0xFF)
    # offset_hi + reserved = 0 (handler < 4GB)
}

# Instead of emitting per-byte mov instructions, use rep movsb loops.
# First record where the ISR + IDT raw data will be appended in the kernel image.
# We'll emit:
#   1. Copy ISR data from kernel_data_isr to isr_base using rep movsb
#   2. Copy IDT data from kernel_data_idt to idt_base using rep movsb
#   3. Setup LIDT + STI
# The raw data blobs are appended after all code.

# Mark placeholder for data addresses (patched after we know code length)
# mov rsi, <isr_data_addr>; mov rdi, isr_base; mov rcx, isr_len; cld; rep movsb
$isr_copy_rsi_patch = (buf_len) + 2  # offset of imm64 in REX.W MOV RSI
buf_emit 0x48; buf_emit 0xBE; buf_emit32 0; buf_emit32 0  # mov rsi, <patched>
buf_emit 0x48; buf_emit 0xBF; buf_emit32 ([int64]$isr_base); buf_emit32 0  # mov rdi, isr_base
buf_emit 0x48; buf_emit 0xB9; buf_emit32 ([int64]$isr_bytes.Length); buf_emit32 0  # mov rcx, isr_len
emit_cld; buf_emit 0xF3; buf_emit 0xA4  # rep movsb

# mov rsi, <idt_data_addr>; mov rdi, idt_base; mov rcx, idt_len; rep movsb
$idt_copy_rsi_patch = (buf_len) + 2
buf_emit 0x48; buf_emit 0xBE; buf_emit32 0; buf_emit32 0  # mov rsi, <patched>
buf_emit 0x48; buf_emit 0xBF; buf_emit32 ([int64]$idt_base); buf_emit32 0  # mov rdi, idt_base
buf_emit 0x48; buf_emit 0xB9; buf_emit32 ([int64]$idt_data.Length); buf_emit32 0  # mov rcx, 4096
emit_cld; buf_emit 0xF3; buf_emit 0xA4  # rep movsb

# LIDT: write 10-byte IDTR structure at idtr_addr, then load it
$idtr_addr = [uint32]($idt_base - 10)
# Write IDTR: limit=0x0FFF, base=idt_base
# Use individual byte writes (only 10 bytes, small)
emit_mov_edx_imm32 $idtr_addr; emit_mov_al_imm8 0xFF; buf_emit 0x88; buf_emit 0x02
emit_mov_edx_imm32 ($idtr_addr + 1); emit_mov_al_imm8 0x0F; buf_emit 0x88; buf_emit 0x02
$idt_le = [System.BitConverter]::GetBytes([uint32]$idt_base)
for ($ib = 0; $ib -lt 4; $ib++) {
    emit_mov_edx_imm32 ($idtr_addr + 2 + $ib); emit_mov_al_imm8 $idt_le[$ib]; buf_emit 0x88; buf_emit 0x02
}
for ($ib = 0; $ib -lt 4; $ib++) {
    emit_mov_edx_imm32 ($idtr_addr + 6 + $ib); emit_mov_al_imm8 0; buf_emit 0x88; buf_emit 0x02
}
# LIDT [disp32]
buf_emit 0x0F; buf_emit 0x01; buf_emit 0x1C  # LIDT [SIB]
buf_emit 0x25                                   # SIB = [disp32]
buf_emit32 $idtr_addr

emit_sti
emit_dual_string "  [ok] IDT: 256 vectors`r`n" $COM1
# --- Scancode to ASCII lookup table at 0x300100 ---
# Write PS/2 Set 1 scancode→ASCII table (128 entries, 1 byte each)
# 0x300100 + scancode = ASCII char (0 = no mapping)
$scan_table = [byte[]]::new(128)
# Row 1: Esc(01)=27, 1-9(02-0A), 0(0B), -(0C), =(0D), BS(0E), Tab(0F)
$scan_table[0x01] = 27   # ESC
$scan_table[0x02] = [byte][char]'1'; $scan_table[0x03] = [byte][char]'2'
$scan_table[0x04] = [byte][char]'3'; $scan_table[0x05] = [byte][char]'4'
$scan_table[0x06] = [byte][char]'5'; $scan_table[0x07] = [byte][char]'6'
$scan_table[0x08] = [byte][char]'7'; $scan_table[0x09] = [byte][char]'8'
$scan_table[0x0A] = [byte][char]'9'; $scan_table[0x0B] = [byte][char]'0'
$scan_table[0x0C] = [byte][char]'-'; $scan_table[0x0D] = [byte][char]'='
$scan_table[0x0E] = 8    # Backspace
$scan_table[0x0F] = 9    # Tab
# Row 2: Q-P (10-19)
$qwerty1 = 'qwertyuiop'
for ($qi = 0; $qi -lt 10; $qi++) { $scan_table[0x10 + $qi] = [byte][char]$qwerty1[$qi] }
$scan_table[0x1A] = [byte][char]'['; $scan_table[0x1B] = [byte][char]']'
$scan_table[0x1C] = 13   # Enter
# Row 3: A-L (1E-26)
$qwerty2 = 'asdfghjkl'
for ($qi = 0; $qi -lt 9; $qi++) { $scan_table[0x1E + $qi] = [byte][char]$qwerty2[$qi] }
$scan_table[0x27] = [byte][char]';'; $scan_table[0x28] = [byte][char]"'"
$scan_table[0x29] = [byte][char]'`'
$scan_table[0x2B] = [byte][char]'\'
# Row 4: Z-M (2C-32)
$qwerty3 = 'zxcvbnm'
for ($qi = 0; $qi -lt 7; $qi++) { $scan_table[0x2C + $qi] = [byte][char]$qwerty3[$qi] }
$scan_table[0x33] = [byte][char]','; $scan_table[0x34] = [byte][char]'.'
$scan_table[0x35] = [byte][char]'/'; $scan_table[0x39] = [byte][char]' '  # Space

# Write scancode table to 0x300100 using per-byte mov instructions
for ($si = 0; $si -lt 128; $si++) {
    if ($scan_table[$si] -ne 0) {
        emit_mov_edx_imm32 (0x300100 + $si)
        emit_mov_al_imm8 $scan_table[$si]
        buf_emit 0x88; buf_emit 0x02  # mov [rdx], al
    }
}
emit_dual_string "  [ok] Scancode: PS/2 loaded`r`n" $COM1

# --- Print tick count and memory info ---
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300000
emit_dual_string "  [ok] Timer ticks: active`r`n" $COM1

# --- PCI Bus Scan ---
# Enumerate PCI bus 0, scan devices 0-31, function 0
# PCI config address port = 0xCF8, data port = 0xCFC
# Address format: 1<<31 | bus<<16 | dev<<11 | func<<8 | reg
# Read vendor ID (reg 0) - if not 0xFFFF, device exists
# Memory layout: 0x300200 = device count, 0x300208+ = vendor:device pairs
# mov qword [0x300200], 0 (device count)
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300200; buf_emit32 0

# r12 = device count, r13 = device slot, r15 = store pointer
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC4; buf_emit32 0  # mov r12, 0 (count)
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC5; buf_emit32 0  # mov r13, 0 (dev)
buf_emit 0x49; buf_emit 0xBF; buf_emit32 0x300208; buf_emit32 0  # mov r15, 0x300208

$pci_loop_start = buf_len
# Build config address: eax = 0x80000000 | (dev << 11) | (reg=0)
# mov eax, r13d
buf_emit 0x44; buf_emit 0x89; buf_emit 0xE8  # mov eax, r13d
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11     # shl eax, 11
buf_emit 0x0D; buf_emit32 0x80000000          # or eax, 0x80000000
# out 0xCF8, eax (32-bit out)
buf_emit 0xBA; buf_emit32 0xCF8               # mov edx, 0xCF8
buf_emit 0xEF                                  # out dx, eax
# in eax, 0xCFC (read vendor:device)
buf_emit 0xBA; buf_emit32 0xCFC               # mov edx, 0xCFC
buf_emit 0xED                                  # in eax, dx

# Check if vendor == 0xFFFF (no device)
# cmp ax, 0xFFFF
buf_emit 0x66; buf_emit 0x3D; buf_emit16 0xFFFF
$je_no_pci_dev_patch = buf_len
buf_emit 0x74; buf_emit 0  # je skip_pci_dev (patched)

# Device found! Store vendor:device pair
# Use r15 as store pointer (initialized before PCI loop)
# mov [r15], eax
buf_emit 0x41; buf_emit 0x89; buf_emit 0x07  # mov [r15], eax
# add r15, 4
buf_emit 0x49; buf_emit 0x83; buf_emit 0xC7; buf_emit 4
# inc r12
buf_emit 0x49; buf_emit 0xFF; buf_emit 0xC4  # inc r12

# skip_pci_dev:
$skip_pci_dev_off = buf_len
buf_set ($je_no_pci_dev_patch + 1) ([byte](($skip_pci_dev_off - $je_no_pci_dev_patch - 2) -band 0xFF))

# inc r13
buf_emit 0x49; buf_emit 0xFF; buf_emit 0xC5  # inc r13
# cmp r13, 32
buf_emit 0x49; buf_emit 0x83; buf_emit 0xFD; buf_emit 32
# jl pci_loop_start
buf_emit 0x7C
$jl_rel = $pci_loop_start - (buf_len) - 1
buf_emit ([byte]($jl_rel -band 0xFF))

# Store device count: mov [0x300200], r12
buf_emit 0x4C; buf_emit 0x89; buf_emit 0x24; buf_emit 0x25; buf_emit32 0x300200

# Build PCI result string: "  [ok] PCI: N device(s) found"
# We'll emit for 0-9 devices (print digit directly)
# mov rax, r12; add al, '0'
buf_emit 0x4C; buf_emit 0x89; buf_emit 0xE0  # mov rax, r12
emit_serial_string "  [ok] PCI: " $COM1
# Print count digit via serial
emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6  # jz -10
emit_mov_edx_imm32 $COM1
buf_emit 0x4C; buf_emit 0x89; buf_emit 0xE0  # mov rax, r12
buf_emit 0x04; buf_emit 0x30                  # add al, '0'
emit_out_dx_al
emit_serial_string " device(s)`r`n" $COM1

# --- Check for VirtIO devices ---
# Scan stored PCI IDs for vendor 0x1AF4 (Red Hat / VirtIO)
# r14 = index, r13 = pointer to stored PCI IDs
# Use [0x300230] as VirtIO flags: bit0=blk, bit1=net
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300230; buf_emit32 0  # clear flags
buf_emit 0x4D; buf_emit 0x31; buf_emit 0xF6  # xor r14, r14
buf_emit 0x49; buf_emit 0xBD; buf_emit32 0x300208; buf_emit32 0  # mov r13, 0x300208

$virtio_loop = buf_len
# cmp r14, r12
buf_emit 0x4D; buf_emit 0x39; buf_emit 0xE6
$jge_virtio_done_patch = buf_len
buf_emit 0x7D; buf_emit 0

# mov eax, [r13+0]
buf_emit 0x41; buf_emit 0x8B; buf_emit 0x45; buf_emit 0x00
# cmp ax, 0x1AF4 (VirtIO vendor)
buf_emit 0x66; buf_emit 0x3D; buf_emit16 0x1AF4
$jne_not_virtio_patch = buf_len
buf_emit 0x75; buf_emit 0

# VirtIO found - check device ID in upper 16 bits
buf_emit 0x89; buf_emit 0xC1  # mov ecx, eax (save)
buf_emit 0xC1; buf_emit 0xE9; buf_emit 16  # shr ecx, 16
# cmp cx, 0x1001 (blk)
buf_emit 0x66; buf_emit 0x81; buf_emit 0xF9; buf_emit16 0x1001
$jne_check_net_patch = buf_len
buf_emit 0x75; buf_emit 0  # jne check_net (patched)
# Set blk flag: or qword [0x300230], 1
buf_emit 0x48; buf_emit 0x83; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x300230; buf_emit 1

# check_net:
$check_net_off = buf_len
buf_set ($jne_check_net_patch + 1) ([byte](($check_net_off - $jne_check_net_patch - 2) -band 0xFF))
buf_emit 0x66; buf_emit 0x81; buf_emit 0xF9; buf_emit16 0x1000
$jne_not_virtio2_patch = buf_len
buf_emit 0x75; buf_emit 0  # jne not_virtio (patched)
buf_emit 0x48; buf_emit 0x83; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x300230; buf_emit 2

# not_virtio:
$not_virtio_off = buf_len
buf_set ($jne_not_virtio_patch + 1) ([byte](($not_virtio_off - $jne_not_virtio_patch - 2) -band 0xFF))
buf_set ($jne_not_virtio2_patch + 1) ([byte](($not_virtio_off - $jne_not_virtio2_patch - 2) -band 0xFF))

# Advance: add r13, 4; inc r14
buf_emit 0x49; buf_emit 0x83; buf_emit 0xC5; buf_emit 4
buf_emit 0x49; buf_emit 0xFF; buf_emit 0xC6
buf_emit 0xEB
buf_emit ([byte](($virtio_loop - (buf_len) - 1) -band 0xFF))

# virtio_done:
$virtio_done_off = buf_len
buf_set ($jge_virtio_done_patch + 1) ([byte](($virtio_done_off - $jge_virtio_done_patch - 2) -band 0xFF))

# Now print results based on flags at [0x300230]
# Check bit 0 (blk)
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300230  # mov rax, [0x300230]
buf_emit 0xA8; buf_emit 1  # test al, 1
# JZ near (0F 84 rel32) to skip VirtIO-blk init block
$jz_no_blk_patch = buf_len
buf_emit 0x0F; buf_emit 0x84; buf_emit32 0  # patched later
emit_serial_string "  [ok] VirtIO-blk: detected (PCI 1AF4:1001)`r`n" $COM1

# --- VirtIO-blk initialization: find slot, read BAR0, read capacity ---
# Re-scan PCI bus 0 for device with vendor:device 1AF4:1001
# Use R14 as dev counter (0-31), EAX for PCI config ops
buf_emit 0x4D; buf_emit 0x31; buf_emit 0xF6  # xor r14, r14 (dev=0)
$blk_scan_loop = buf_len
# PCI config address: 0x80000000 | (r14d << 11) | reg 0
buf_emit 0x44; buf_emit 0x89; buf_emit 0xF0  # mov eax, r14d
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11  # shl eax, 11
buf_emit 0x0D; buf_emit32 0x80000000
buf_emit 0xBA; buf_emit32 0xCF8; buf_emit 0xEF  # mov edx, 0xCF8; out dx, eax
buf_emit 0xBA; buf_emit32 0xCFC; buf_emit 0xED  # mov edx, 0xCFC; in eax, dx
# cmp eax, 0x10011AF4 (device:vendor packed, little-endian)
buf_emit 0x3D; buf_emit32 0x10011AF4
# JNE near (0F 85 rel32) to skip the entire VirtIO-blk init block
$jne_blk_next_patch = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # patched later

# Found! Read BAR0 (PCI reg 0x10): config addr = 0x80000000 | (r14d<<11) | 0x10
buf_emit 0x44; buf_emit 0x89; buf_emit 0xF0  # mov eax, r14d
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11
buf_emit 0x0D; buf_emit32 0x80000010  # | 0x10
buf_emit 0xBA; buf_emit32 0xCF8; buf_emit 0xEF
buf_emit 0xBA; buf_emit32 0xCFC; buf_emit 0xED
# Read BAR0 and mask
buf_emit 0xBA; buf_emit32 0xCFC; buf_emit 0xED  # in eax, dx from 0xCFC
buf_emit 0x83; buf_emit 0xE0; buf_emit 0xFC  # and eax, ~3 (mask I/O bits)
# Store BAR0 at 0x300238
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300238
# Save bar in ebx for later use
buf_emit 0x89; buf_emit 0xC3  # mov ebx, eax

# Enable PCI I/O space + bus master for this device
# Write PCI command register (offset 0x04): set bits 0 (I/O) + 2 (Bus Master)
buf_emit 0x44; buf_emit 0x89; buf_emit 0xF0  # mov eax, r14d
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11
buf_emit 0x0D; buf_emit32 0x80000004  # config addr with reg=0x04 (Command)
buf_emit 0xBA; buf_emit32 0xCF8; buf_emit 0xEF
buf_emit 0xBA; buf_emit32 0xCFC; buf_emit 0xED  # read current command
buf_emit 0x83; buf_emit 0xC8; buf_emit 0x07  # or eax, 7 (I/O + Memory + Bus Master)
buf_emit 0xBA; buf_emit32 0xCFC; buf_emit 0xEF  # write back

# Print BAR0 value
emit_serial_string "  [ok] VirtIO-blk: BAR0=0x" $COM1
buf_emit 0x89; buf_emit 0xD8  # mov eax, ebx
emit_serial_hex_eax $COM1

# Read VirtIO device status: reset → ack → driver → features_ok → driver_ok
# Reset: out (bar+18), 0
buf_emit 0x8D; buf_emit 0x53; buf_emit 18  # lea edx, [rbx+18]
emit_mov_al_imm8 0; emit_out_dx_al
# Acknowledge: out (bar+18), 1
buf_emit 0x8D; buf_emit 0x53; buf_emit 18
emit_mov_al_imm8 1; emit_out_dx_al
# Driver: out (bar+18), 3
buf_emit 0x8D; buf_emit 0x53; buf_emit 18
emit_mov_al_imm8 3; emit_out_dx_al
# Read features (bar+0) then write 0 (bar+4)
buf_emit 0x89; buf_emit 0xDA  # mov edx, ebx
buf_emit 0xED  # in eax, dx (features)
buf_emit 0x8D; buf_emit 0x53; buf_emit 4  # lea edx, [rbx+4]
buf_emit 0x31; buf_emit 0xC0  # xor eax, eax
buf_emit 0xEF  # out dx, eax
# Features OK: out (bar+18), 11
buf_emit 0x8D; buf_emit 0x53; buf_emit 18
emit_mov_al_imm8 11; emit_out_dx_al

# === Virtqueue 0 setup ===
# Select queue 0: out8 (bar+0x0E), 0 (only need low byte)
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x0E  # lea edx, [rbx+14]
buf_emit 0xB0; buf_emit 0     # mov al, 0
buf_emit 0xEE                  # out dx, al (byte)
# Read queue size: in32 (bar+0x0C) → eax, then mask to 16 bits
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x0C  # lea edx, [rbx+12]
buf_emit 0xED  # in eax, dx (32-bit read)
buf_emit 0x25; buf_emit32 0xFFFF  # and eax, 0xFFFF (keep low 16 bits)
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300250

# Print queue size (eax still has qsz from the read)
buf_emit 0x50  # push rax (save qsz)
emit_serial_string " qsz=" $COM1
buf_emit 0x58  # pop rax
emit_serial_hex_eax $COM1
emit_serial_string "`r`n" $COM1

# Virtqueue memory layout at 0x400000 (page-aligned):
#   Descriptor table: qsize * 16 bytes (at 0x400000)
#   Available ring: 6 + qsize*2 bytes (right after descriptors)
#   Used ring: 6 + qsize*8 bytes (page-aligned after avail)
# For simplicity, zero 16KB from 0x400000
# Save EBX (BAR) on stack
buf_emit 0x53  # push rbx
emit_mov_edi_imm32 0x400000
emit_mov_ecx_imm32 4096  # 16KB / 4 = 4096 dwords
emit_xor_eax_eax
buf_emit 0xFC  # CLD
buf_emit 0xF3; buf_emit 0xAB  # rep stosd
buf_emit 0x5B  # pop rbx

# Initialize free descriptor chain: desc[i].next = i+1, flags = NEXT
# desc entry = 16 bytes: addr(8) + len(4) + flags(2) + next(2)
# Use r12 as qsize, r13 as index
buf_emit 0x44; buf_emit 0x8B; buf_emit 0x24; buf_emit 0x25; buf_emit32 0x300250  # mov r12d, [0x300250]
buf_emit 0x45; buf_emit 0x31; buf_emit 0xED  # xor r13d, r13d (i=0)
$desc_init_loop = buf_len
# desc[i].flags at offset 12 = 1 (NEXT)
buf_emit 0x44; buf_emit 0x89; buf_emit 0xE8  # mov eax, r13d
buf_emit 0xC1; buf_emit 0xE0; buf_emit 4      # shl eax, 4 (i*16)
buf_emit 0x8D; buf_emit 0x90; buf_emit32 0x400000  # lea edx, [rax+0x400000]
# desc[i].flags = 1 (VIRTQ_DESC_F_NEXT)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x42; buf_emit 12; buf_emit16 1  # mov word [rdx+12], 1
# desc[i].next = i+1
buf_emit 0x44; buf_emit 0x89; buf_emit 0xE8  # mov eax, r13d
buf_emit 0xFF; buf_emit 0xC0                  # inc eax
buf_emit 0x66; buf_emit 0x89; buf_emit 0x42; buf_emit 14  # mov word [rdx+14], ax
# inc r13; cmp r13, r12-1
buf_emit 0x49; buf_emit 0xFF; buf_emit 0xC5  # inc r13
buf_emit 0x45; buf_emit 0x8D; buf_emit 0x44; buf_emit 0x24; buf_emit 0xFF  # lea r8d, [r12-1]
buf_emit 0x45; buf_emit 0x39; buf_emit 0xC5  # cmp r13d, r8d
buf_emit 0x7C  # jl desc_init_loop
buf_emit ([byte](($desc_init_loop - (buf_len) - 1) -band 0xFF))

# Tell device queue address: PFN = 0x400000 / 4096 = 0x400
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x08  # lea edx, [rbx+8]
buf_emit 0xB8; buf_emit32 0x400  # mov eax, 0x400
buf_emit 0xEF  # out dx, eax (32-bit)

# Store virtqueue layout addresses (computed for actual qsize)
# desc_base = 0x400000
# avail_base = 0x400000 + qsize*16
# used_base = align4096(avail_base + 6 + qsize*2)
# For qsize=256: desc=0x400000, avail=0x401000, used=0x402000
# For qsize=128: desc=0x400000, avail=0x400800, used=0x401000
# Compute dynamically:
# r12 = qsize (saved from earlier)
# avail = 0x400000 + r12*16
buf_emit 0x44; buf_emit 0x89; buf_emit 0xE0  # mov eax, r12d
buf_emit 0xC1; buf_emit 0xE0; buf_emit 4      # shl eax, 4 (qsize*16)
buf_emit 0x05; buf_emit32 0x400000            # add eax, 0x400000
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300260  # store avail_base

# used = align_4096(avail + 6 + qsize*2)
# eax still has avail_base
buf_emit 0x89; buf_emit 0xC1  # mov ecx, eax (avail)
buf_emit 0x44; buf_emit 0x89; buf_emit 0xE0  # mov eax, r12d
buf_emit 0xD1; buf_emit 0xE0  # shl eax, 1 (qsize*2)
buf_emit 0x01; buf_emit 0xC8  # add eax, ecx
buf_emit 0x83; buf_emit 0xC0; buf_emit 6  # add eax, 6
buf_emit 0x05; buf_emit32 0xFFF  # add eax, 0xFFF
buf_emit 0x25; buf_emit32 0xFFFFF000  # and eax, ~0xFFF (align to 4096)
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300268  # store used_base

buf_emit 0xB8; buf_emit32 0x400000
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300258  # store desc_base

# Driver OK: out (bar+18), 15
buf_emit 0x8D; buf_emit 0x53; buf_emit 18
emit_mov_al_imm8 15; emit_out_dx_al

# Read capacity: try both offsets (0x14 without MSI-X, 0x18 with MSI-X)
# First try offset 0x14 (20)
buf_emit 0x8D; buf_emit 0x53; buf_emit 20  # lea edx, [rbx+20]
buf_emit 0xED  # in eax, dx → low 32 bits of capacity
# If zero, try offset 0x18 (24) for MSI-X enabled devices
buf_emit 0x85; buf_emit 0xC0  # test eax, eax
buf_emit 0x75; buf_emit 4     # jnz cap_ok
buf_emit 0x8D; buf_emit 0x53; buf_emit 24  # lea edx, [rbx+24]
buf_emit 0xED  # in eax, dx
# cap_ok:
# Store at 0x300240
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300240

# Capacity in MB = (sectors * 512) / 1048576 = sectors / 2048
# shr eax, 11  (divide by 2048)
buf_emit 0xC1; buf_emit 0xE8; buf_emit 11
# Store MB at 0x300248
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300248

# Print capacity: "  [ok] VirtIO-blk: BAR=0xNNNN cap=NNN MB"
# Simple: print the MB digit (0-9 for <10MB, or tens/units)
emit_serial_string "  [ok] VirtIO-blk: initialized (" $COM1
# Print MB count (tens digit)
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300248  # mov eax, [0x300248]
buf_emit 0x31; buf_emit 0xD2  # xor edx, edx
buf_emit 0xB9; buf_emit32 10  # mov ecx, 10
buf_emit 0xF7; buf_emit 0xF1  # div ecx (eax=quo, edx=rem)
# Print tens digit
buf_emit 0x04; buf_emit 0x30  # add al, '0'
buf_emit 0x50  # push rax (save)
emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6
buf_emit 0x58  # pop rax
emit_mov_edx_imm32 $COM1; emit_out_dx_al
# Print units digit (remainder was in edx, now need to reload)
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300248
buf_emit 0x31; buf_emit 0xD2; buf_emit 0xB9; buf_emit32 10; buf_emit 0xF7; buf_emit 0xF1
# edx = remainder
buf_emit 0x89; buf_emit 0xD0  # mov eax, edx
buf_emit 0x04; buf_emit 0x30
buf_emit 0x50
emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6
buf_emit 0x58
emit_mov_edx_imm32 $COM1; emit_out_dx_al
emit_serial_string " MB)`r`n" $COM1

# === VirtIO-blk: Test read sector 0 ===
# Request buffers at 0x500000:
#   0x500000: request header (16 bytes: type=0 IN, reserved=0, sector=0)
#   0x500010: data buffer (512 bytes)
#   0x500210: status byte (1 byte)

# Build request header: type=0 (read), reserved=0, sector=0
buf_emit 0xBF; buf_emit32 0x500000  # mov edi, 0x500000
buf_emit 0x31; buf_emit 0xC0  # xor eax, eax
buf_emit 0x89; buf_emit 0x07  # mov [rdi], eax (type=0)
buf_emit 0x89; buf_emit 0x47; buf_emit 4  # mov [rdi+4], eax (reserved=0)
buf_emit 0x89; buf_emit 0x47; buf_emit 8  # mov [rdi+8], eax (sector lo=0)
buf_emit 0x89; buf_emit 0x47; buf_emit 12  # mov [rdi+12], eax (sector hi=0)

# Set status byte to 0xFF (will be overwritten by device)
buf_emit 0xC6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500210; buf_emit 0xFF  # mov byte [0x500210], 0xFF

# Setup descriptor chain: desc[0] → header, desc[1] → data, desc[2] → status
# desc[0]: addr=0x500000, len=16, flags=NEXT(1), next=1
buf_emit 0xBF; buf_emit32 0x400000  # mov edi, 0x400000 (desc base)
# desc[0].addr = 0x500000 (8 bytes)
buf_emit 0xB8; buf_emit32 0x500000; buf_emit 0x89; buf_emit 0x07  # mov [rdi], eax=0x500000
buf_emit 0x31; buf_emit 0xC0; buf_emit 0x89; buf_emit 0x47; buf_emit 4  # mov [rdi+4], 0 (high)
# desc[0].len = 16
buf_emit 0xC7; buf_emit 0x47; buf_emit 8; buf_emit32 16
# desc[0].flags = 1 (NEXT)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit16 1
# desc[0].next = 1
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 14; buf_emit16 1

# desc[1] at offset 16: addr=0x500010, len=512, flags=WRITE|NEXT(3), next=2
buf_emit 0xC7; buf_emit 0x47; buf_emit 16; buf_emit32 0x500010  # addr lo
buf_emit 0xC7; buf_emit 0x47; buf_emit 20; buf_emit32 0          # addr hi
buf_emit 0xC7; buf_emit 0x47; buf_emit 24; buf_emit32 512        # len
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 28; buf_emit16 3  # flags=WRITE|NEXT
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 30; buf_emit16 2  # next=2

# desc[2] at offset 32: addr=0x500210, len=1, flags=WRITE(2), next=0
buf_emit 0xC7; buf_emit 0x47; buf_emit 32; buf_emit32 0x500210  # addr lo
buf_emit 0xC7; buf_emit 0x47; buf_emit 36; buf_emit32 0          # addr hi
buf_emit 0xC7; buf_emit 0x47; buf_emit 40; buf_emit32 1          # len
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 44; buf_emit16 2  # flags=WRITE only
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 46; buf_emit16 0  # next=0

# Add desc[0] to available ring:
# avail_base from [0x300260]
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300260  # mov edi, [0x300260]
# avail->flags(2) = 0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x07; buf_emit16 0
# avail->idx(2) = 1
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 2; buf_emit16 1
# avail->ring[0](2) = 0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit16 0

# Memory fence before notify (ensure avail ring writes are visible)
buf_emit 0x0F; buf_emit 0xAE; buf_emit 0xF0  # mfence

# Notify device
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x10  # lea edx, [rbx+16]
buf_emit 0xB0; buf_emit 0
buf_emit 0xEE  # out dx, al

# Poll used ring until used->idx != 0 (with short timeout)
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300268  # mov edi, [0x300268]
buf_emit 0xB9; buf_emit32 0x100000  # mov ecx, 1M (timeout)
$poll_used_loop = buf_len
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 2  # movzx eax, word [rdi+2]
buf_emit 0x85; buf_emit 0xC0  # test eax, eax
buf_emit 0x75; buf_emit 4     # jnz poll_done
buf_emit 0xFF; buf_emit 0xC9  # dec ecx
buf_emit 0x75  # jnz poll_used_loop
buf_emit ([byte](($poll_used_loop - (buf_len) - 1) -band 0xFF))
# poll_done:

# Check status byte
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500210  # movzx eax, byte [0x500210]
buf_emit 0x85; buf_emit 0xC0  # test eax, eax
$jnz_read_fail_patch = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # jnz read_failed (patched)

# Read success! Print first 16 bytes as hex
emit_serial_string "  [ok] Disk: sector 0 = " $COM1
buf_emit 0x45; buf_emit 0x31; buf_emit 0xED  # xor r13d, r13d
$hex_dump_loop = buf_len
buf_emit 0x41; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x85; buf_emit32 0x500010  # movzx eax, byte [r13+0x500010]
emit_serial_hex_byte $COM1
emit_serial_string " " $COM1
buf_emit 0x49; buf_emit 0xFF; buf_emit 0xC5  # inc r13
buf_emit 0x49; buf_emit 0x83; buf_emit 0xFD; buf_emit 16  # cmp r13, 16
buf_emit 0x7C  # jl hex_dump_loop
buf_emit ([byte](($hex_dump_loop - (buf_len) - 1) -band 0xFF))
emit_serial_string "`r`n" $COM1
emit_serial_string "`r`n" $COM1
$jmp_read_end_patch = buf_len
buf_emit 0xE9; buf_emit32 0  # jmp read_end

# read_failed:
$read_fail_off = buf_len
$rf_rel = $read_fail_off - ($jnz_read_fail_patch + 6)
buf_set ($jnz_read_fail_patch + 2) ([byte]($rf_rel -band 0xFF))
buf_set ($jnz_read_fail_patch + 3) ([byte](($rf_rel -shr 8) -band 0xFF))
buf_set ($jnz_read_fail_patch + 4) ([byte](($rf_rel -shr 16) -band 0xFF))
buf_set ($jnz_read_fail_patch + 5) ([byte](($rf_rel -shr 24) -band 0xFF))
emit_serial_string "  [!!] VirtIO-blk: sector 0 read FAILED (status=" $COM1
emit_serial_hex_eax $COM1
emit_serial_string ")`r`n" $COM1

# read_end:
$read_end_off = buf_len
$re_rel = $read_end_off - ($jmp_read_end_patch + 5)
buf_set ($jmp_read_end_patch + 1) ([byte]($re_rel -band 0xFF))
buf_set ($jmp_read_end_patch + 2) ([byte](($re_rel -shr 8) -band 0xFF))
buf_set ($jmp_read_end_patch + 3) ([byte](($re_rel -shr 16) -band 0xFF))
buf_set ($jmp_read_end_patch + 4) ([byte](($re_rel -shr 24) -band 0xFF))

# === Write+Readback test: write "HicOS!" to sector 100, read back, verify ===
# Write "HicOS!\0\0" (8 bytes) to data buffer 0x500010
buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500010; buf_emit32 0x634F6948  # "HicO" LE
buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500014; buf_emit32 0x00002153  # "S!\0\0" LE

# Set request header: type=1 (WRITE), sector=100
buf_emit 0xBF; buf_emit32 0x500000
buf_emit 0xC7; buf_emit 0x07; buf_emit32 1   # type=1 (OUT/WRITE)
buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit32 0   # reserved
buf_emit 0xC7; buf_emit 0x47; buf_emit 8; buf_emit32 100  # sector=100
buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit32 0   # sector hi

# Reset status
buf_emit 0xC6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500210; buf_emit 0xFF

# Reuse desc[0-2] but fix desc[1] flags for WRITE (readable by device)
# desc[1].flags should be NEXT only (no WRITE flag) for device-readable data
buf_emit 0xBF; buf_emit32 0x400000
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 28; buf_emit16 1  # flags=NEXT (device reads)

# Update avail ring: avail->idx = 2 (next), ring[avail_idx%qsize] = 0
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300260  # mov edi, [avail_base]
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 6; buf_emit16 0  # ring[1] = desc 0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 2; buf_emit16 2  # idx = 2

buf_emit 0x0F; buf_emit 0xAE; buf_emit 0xF0  # mfence
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x10; buf_emit 0xB0; buf_emit 0; buf_emit 0xEE  # notify

# Poll for write completion
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300268
buf_emit 0xB9; buf_emit32 0x100000
$poll_write_loop = buf_len
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 2  # movzx eax, word [rdi+2]
buf_emit 0x83; buf_emit 0xF8; buf_emit 2  # cmp eax, 2 (used_idx should be 2 now)
buf_emit 0x7D; buf_emit 4  # jge done
buf_emit 0xFF; buf_emit 0xC9
buf_emit 0x75
buf_emit ([byte](($poll_write_loop - (buf_len) - 1) -band 0xFF))

# Check write status
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500210
buf_emit 0x85; buf_emit 0xC0
$jnz_write_fail = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0

# Write OK! Now readback: set type=0 (READ), sector=100
buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500000; buf_emit32 0  # type=0
# sector stays 100
# Clear data buffer first 8 bytes
buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500010; buf_emit32 0
buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500014; buf_emit32 0
# Reset status
buf_emit 0xC6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500210; buf_emit 0xFF
# Fix desc[1].flags back to WRITE|NEXT for device-writable data
buf_emit 0xBF; buf_emit32 0x400000
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 28; buf_emit16 3  # WRITE|NEXT

# Update avail: ring[2%qsize] = 0, idx = 3
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300260
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 8; buf_emit16 0  # ring[2] = 0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 2; buf_emit16 3  # idx = 3

buf_emit 0x0F; buf_emit 0xAE; buf_emit 0xF0  # mfence
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x10; buf_emit 0xB0; buf_emit 0; buf_emit 0xEE  # notify

# Poll for readback
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300268
buf_emit 0xB9; buf_emit32 0x100000
$poll_rb_loop = buf_len
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 2
buf_emit 0x83; buf_emit 0xF8; buf_emit 3  # cmp eax, 3
buf_emit 0x7D; buf_emit 4
buf_emit 0xFF; buf_emit 0xC9
buf_emit 0x75
buf_emit ([byte](($poll_rb_loop - (buf_len) - 1) -band 0xFF))

# Check readback status
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500210
buf_emit 0x85; buf_emit 0xC0
$jnz_rb_fail = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0

# Compare first 4 bytes with "HicO" (0x634F6948)
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500010
buf_emit 0x3D; buf_emit32 0x634F6948  # cmp eax, "HicO"
$jne_verify_fail = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0

# SUCCESS!
emit_serial_string "  [ok] Disk: write+readback sector 100 verified`r`n" $COM1
$jmp_disk_end = buf_len
buf_emit 0xE9; buf_emit32 0

# write_failed:
$wf_off = buf_len
$wf_rel = $wf_off - ($jnz_write_fail + 6)
buf_set ($jnz_write_fail + 2) ([byte]($wf_rel -band 0xFF))
buf_set ($jnz_write_fail + 3) ([byte](($wf_rel -shr 8) -band 0xFF))
buf_set ($jnz_write_fail + 4) ([byte](($wf_rel -shr 16) -band 0xFF))
buf_set ($jnz_write_fail + 5) ([byte](($wf_rel -shr 24) -band 0xFF))
emit_serial_string "  [!!] Disk: write FAILED`r`n" $COM1
$jmp_disk_end2 = buf_len
buf_emit 0xE9; buf_emit32 0

# rb_failed:
$rbf_off = buf_len
$rbf_rel = $rbf_off - ($jnz_rb_fail + 6)
buf_set ($jnz_rb_fail + 2) ([byte]($rbf_rel -band 0xFF))
buf_set ($jnz_rb_fail + 3) ([byte](($rbf_rel -shr 8) -band 0xFF))
buf_set ($jnz_rb_fail + 4) ([byte](($rbf_rel -shr 16) -band 0xFF))
buf_set ($jnz_rb_fail + 5) ([byte](($rbf_rel -shr 24) -band 0xFF))
emit_serial_string "  [!!] Disk: readback FAILED`r`n" $COM1
$jmp_disk_end3 = buf_len
buf_emit 0xE9; buf_emit32 0

# verify_failed:
$vf_off = buf_len
$vf_rel = $vf_off - ($jne_verify_fail + 6)
buf_set ($jne_verify_fail + 2) ([byte]($vf_rel -band 0xFF))
buf_set ($jne_verify_fail + 3) ([byte](($vf_rel -shr 8) -band 0xFF))
buf_set ($jne_verify_fail + 4) ([byte](($vf_rel -shr 16) -band 0xFF))
buf_set ($jne_verify_fail + 5) ([byte](($vf_rel -shr 24) -band 0xFF))
emit_serial_string "  [!!] Disk: verify FAILED`r`n" $COM1

# disk_test_end:
$disk_end_off = buf_len
foreach ($p in @($jmp_disk_end, $jmp_disk_end2, $jmp_disk_end3)) {
    $rel = $disk_end_off - ($p + 5)
    buf_set ($p + 1) ([byte]($rel -band 0xFF))
    buf_set ($p + 2) ([byte](($rel -shr 8) -band 0xFF))
    buf_set ($p + 3) ([byte](($rel -shr 16) -band 0xFF))
    buf_set ($p + 4) ([byte](($rel -shr 24) -band 0xFF))
}

# Jump past blk scan loop end
$jmp_blk_done_patch = buf_len
buf_emit 0xE9; buf_emit32 0  # jmp blk_done (patched)

# blk_next: (didn't match, try next dev)
$blk_next_off = buf_len
$blk_next_rel = $blk_next_off - ($jne_blk_next_patch + 6)  # 6 = opcode(2) + rel32(4)
buf_set ($jne_blk_next_patch + 2) ([byte]($blk_next_rel -band 0xFF))
buf_set ($jne_blk_next_patch + 3) ([byte](($blk_next_rel -shr 8) -band 0xFF))
buf_set ($jne_blk_next_patch + 4) ([byte](($blk_next_rel -shr 16) -band 0xFF))
buf_set ($jne_blk_next_patch + 5) ([byte](($blk_next_rel -shr 24) -band 0xFF))
buf_emit 0x49; buf_emit 0xFF; buf_emit 0xC6  # inc r14
buf_emit 0x49; buf_emit 0x83; buf_emit 0xFE; buf_emit 32  # cmp r14, 32
# JL near (0F 8C rel32) back to blk_scan_loop
buf_emit 0x0F; buf_emit 0x8C
$blk_jl_rel = $blk_scan_loop - (buf_len) - 4  # rel32 offset
buf_emit32_signed $blk_jl_rel

# blk_done:
$blk_done_off = buf_len
$blk_done_rel = $blk_done_off - ($jmp_blk_done_patch + 5)
buf_set ($jmp_blk_done_patch + 1) ([byte]($blk_done_rel -band 0xFF))
buf_set ($jmp_blk_done_patch + 2) ([byte](($blk_done_rel -shr 8) -band 0xFF))
buf_set ($jmp_blk_done_patch + 3) ([byte](($blk_done_rel -shr 16) -band 0xFF))
buf_set ($jmp_blk_done_patch + 4) ([byte](($blk_done_rel -shr 24) -band 0xFF))

$after_blk = buf_len
$jz_blk_rel = $after_blk - ($jz_no_blk_patch + 6)  # 6 = opcode(2) + rel32(4)
buf_set ($jz_no_blk_patch + 2) ([byte]($jz_blk_rel -band 0xFF))
buf_set ($jz_no_blk_patch + 3) ([byte](($jz_blk_rel -shr 8) -band 0xFF))
buf_set ($jz_no_blk_patch + 4) ([byte](($jz_blk_rel -shr 16) -band 0xFF))
buf_set ($jz_no_blk_patch + 5) ([byte](($jz_blk_rel -shr 24) -band 0xFF))

# Check bit 1 (net)
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300230  # reload
buf_emit 0xA8; buf_emit 2  # test al, 2
$jz_no_net_patch = buf_len
buf_emit 0x0F; buf_emit 0x84; buf_emit32 0  # JZ near (patched later)

emit_serial_string "  [ok] VirtIO-net: detected (PCI 1AF4:1000)`r`n" $COM1

# === VirtIO-net initialization ===
# Re-scan PCI for 1AF4:1000
buf_emit 0x4D; buf_emit 0x31; buf_emit 0xF6  # xor r14, r14 (dev=0)
$net_scan_loop = buf_len
buf_emit 0x44; buf_emit 0x89; buf_emit 0xF0  # mov eax, r14d
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11
buf_emit 0x0D; buf_emit32 0x80000000
buf_emit 0xBA; buf_emit32 0xCF8; buf_emit 0xEF
buf_emit 0xBA; buf_emit32 0xCFC; buf_emit 0xED
buf_emit 0x3D; buf_emit32 0x10001AF4  # cmp eax, vendor:device
$jne_net_next_patch = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # JNE near (patched)

# Found VirtIO-net! Read BAR0
buf_emit 0x44; buf_emit 0x89; buf_emit 0xF0  # mov eax, r14d
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11
buf_emit 0x0D; buf_emit32 0x80000010  # reg 0x10 (BAR0)
buf_emit 0xBA; buf_emit32 0xCF8; buf_emit 0xEF
buf_emit 0xBA; buf_emit32 0xCFC; buf_emit 0xED
buf_emit 0x83; buf_emit 0xE0; buf_emit 0xFC  # and eax, ~3
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300280  # store net BAR at 0x300280
buf_emit 0x89; buf_emit 0xC3  # mov ebx, eax (BAR in EBX)

# Enable PCI Bus Master
buf_emit 0x44; buf_emit 0x89; buf_emit 0xF0  # mov eax, r14d
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11
buf_emit 0x0D; buf_emit32 0x80000004  # reg 0x04 (Command)
buf_emit 0xBA; buf_emit32 0xCF8; buf_emit 0xEF
buf_emit 0xBA; buf_emit32 0xCFC; buf_emit 0xED
buf_emit 0x83; buf_emit 0xC8; buf_emit 0x07  # or eax, 7 (I/O+Mem+BusMaster)
buf_emit 0xBA; buf_emit32 0xCFC; buf_emit 0xEF  # write back

# VirtIO legacy init: reset → ack → driver → features → driver_ok
# Reset
buf_emit 0x8D; buf_emit 0x53; buf_emit 18  # lea edx, [rbx+18]
emit_mov_al_imm8 0; emit_out_dx_al
# ACK
buf_emit 0x8D; buf_emit 0x53; buf_emit 18
emit_mov_al_imm8 1; emit_out_dx_al
# DRIVER
buf_emit 0x8D; buf_emit 0x53; buf_emit 18
emit_mov_al_imm8 3; emit_out_dx_al
# Read features, accept low bits
buf_emit 0x89; buf_emit 0xDA; buf_emit 0xED  # mov edx, ebx; in eax, dx
buf_emit 0x8D; buf_emit 0x53; buf_emit 4  # lea edx, [rbx+4]
buf_emit 0x31; buf_emit 0xC0; buf_emit 0xEF  # xor eax,eax; out dx, eax
# FEATURES_OK
buf_emit 0x8D; buf_emit 0x53; buf_emit 18
emit_mov_al_imm8 11; emit_out_dx_al

# Setup RX queue (queue 0) at 0x600000
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x0E  # lea edx, [rbx+14] (queue select)
buf_emit 0xB0; buf_emit 0; buf_emit 0xEE      # mov al,0; out dx,al
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x0C
buf_emit 0xED                                   # in eax, dx (queue size)
buf_emit 0x25; buf_emit32 0xFFFF               # and eax, 0xFFFF
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300288  # store rx qsize

# Zero 16KB at 0x600000 for RX virtqueue
buf_emit 0x53  # push rbx
emit_mov_edi_imm32 0x600000
emit_mov_ecx_imm32 4096
emit_xor_eax_eax
buf_emit 0xFC; buf_emit 0xF3; buf_emit 0xAB  # cld; rep stosd
buf_emit 0x5B  # pop rbx

# Tell device RX queue PFN: 0x600000/4096 = 0x600
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x08  # lea edx, [rbx+8]
buf_emit 0xB8; buf_emit32 0x600; buf_emit 0xEF  # mov eax, 0x600; out dx, eax

# Setup TX queue (queue 1) at 0x610000
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x0E  # queue select
buf_emit 0xB0; buf_emit 1; buf_emit 0xEE
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x0C
buf_emit 0xED
buf_emit 0x25; buf_emit32 0xFFFF
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300290  # store tx qsize

# Zero 16KB at 0x610000 for TX virtqueue
buf_emit 0x53
emit_mov_edi_imm32 0x610000
emit_mov_ecx_imm32 4096
emit_xor_eax_eax
buf_emit 0xFC; buf_emit 0xF3; buf_emit 0xAB
buf_emit 0x5B

buf_emit 0x8D; buf_emit 0x53; buf_emit 0x08
buf_emit 0xB8; buf_emit32 0x610; buf_emit 0xEF  # TX PFN = 0x610

# DRIVER_OK
buf_emit 0x8D; buf_emit 0x53; buf_emit 18
emit_mov_al_imm8 15; emit_out_dx_al

# Read MAC address from device config (BAR+20..25)
emit_serial_string "  [ok] VirtIO-net: MAC=" $COM1
# Read 6 bytes unrolled to keep the emitter straightforward and local.
for ($mi = 0; $mi -lt 6; $mi++) {
    if ($mi -gt 0) { emit_serial_string ":" $COM1 }
    # in al, (BAR + 20 + $mi)
    buf_emit 0x8D; buf_emit 0x53; buf_emit ([byte](20 + $mi))  # lea edx, [rbx+20+mi]
    buf_emit 0xEC  # in al, dx
    emit_serial_hex_byte $COM1
}
emit_serial_string "`r`n" $COM1

# === Send ARP request: who-has 10.0.2.2 (QEMU gateway) ===
# ARP packet at 0x620000 (42 bytes Ethernet + ARP)
# Ethernet header (14 bytes):
#   dst MAC: FF:FF:FF:FF:FF:FF (broadcast)
#   src MAC: 52:54:00:12:34:56 (our MAC)
#   EtherType: 0x0806 (ARP)
# ARP payload (28 bytes):
#   HTYPE=1(Ethernet), PTYPE=0x0800(IPv4), HLEN=6, PLEN=4
#   OPER=1(request)
#   SHA=our MAC, SPA=10.0.2.15 (QEMU guest default)
#   THA=00:00:00:00:00:00, TPA=10.0.2.2

# Build packet in memory at 0x620000
buf_emit 0xBF; buf_emit32 0x620000  # mov edi, 0x620000

# Ethernet dst: FF FF FF FF FF FF
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0xFFFFFFFF  # [edi+0] = FF FF FF FF
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit16 0xFFFF  # [edi+4] = FF FF
# Ethernet src: 52 54 00 12 34 56
buf_emit 0xC7; buf_emit 0x47; buf_emit 6; buf_emit32 0x12005452  # 52 54 00 12 (LE)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 10; buf_emit16 0x5634  # 34 56 (LE)
# EtherType: 08 06 (ARP) - network byte order
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit16 0x0608  # 08 06 in LE = 0x0608

# ARP header at offset 14:
# HTYPE=0x0001 (Ethernet)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 14; buf_emit16 0x0100  # 00 01 BE
# PTYPE=0x0800 (IPv4)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 16; buf_emit16 0x0008  # 08 00 BE
# HLEN=6, PLEN=4
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 18; buf_emit16 0x0406  # 06 04
# OPER=1 (request)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 20; buf_emit16 0x0100  # 00 01 BE

# SHA (sender MAC): 52:54:00:12:34:56 at offset 22
buf_emit 0xC7; buf_emit 0x47; buf_emit 22; buf_emit32 0x12005452
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 26; buf_emit16 0x5634

# SPA (sender IP): 10.0.2.15 = 0x0A00020F at offset 28
buf_emit 0xC7; buf_emit 0x47; buf_emit 28; buf_emit32 0x0F02000A  # 0A 00 02 0F LE

# THA (target MAC): 00:00:00:00:00:00 at offset 32
buf_emit 0xC7; buf_emit 0x47; buf_emit 32; buf_emit32 0x00000000
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 36; buf_emit16 0x0000

# TPA (target IP): 10.0.2.2 = 0x0A000202 at offset 38
buf_emit 0xC7; buf_emit 0x47; buf_emit 38; buf_emit32 0x0202000A  # 0A 00 02 02 LE

# Now build VirtIO-net header (10 bytes, all zeros) at 0x620100
buf_emit 0xBF; buf_emit32 0x620100
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0  # first 4 bytes = 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit32 0  # next 4 bytes = 0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 8; buf_emit16 0  # last 2 bytes = 0

# Setup TX descriptors at 0x610000:
# desc[0]: VirtIO header (addr=0x620100, len=10, flags=NEXT, next=1)
# desc[1]: ARP packet (addr=0x620000, len=42, flags=0, next=0)
buf_emit 0xBF; buf_emit32 0x610000
# desc[0].addr = 0x620100
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0x620100
buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit32 0  # addr high
buf_emit 0xC7; buf_emit 0x47; buf_emit 8; buf_emit32 10  # len=10
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit16 1  # flags=NEXT
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 14; buf_emit16 1  # next=1

# desc[1]: packet data
buf_emit 0xC7; buf_emit 0x47; buf_emit 16; buf_emit32 0x620000  # addr
buf_emit 0xC7; buf_emit 0x47; buf_emit 20; buf_emit32 0         # addr high
buf_emit 0xC7; buf_emit 0x47; buf_emit 24; buf_emit32 42        # len=42 (14 eth + 28 arp)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 28; buf_emit16 0  # flags=0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 30; buf_emit16 0  # next=0

# Add to TX avail ring (need to compute avail_base from tx_qsize)
# tx_qsize stored at [0x300290], avail_base = 0x610000 + qsize*16
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300290  # mov eax, [tx_qsize]
buf_emit 0xC1; buf_emit 0xE0; buf_emit 4  # shl eax, 4 (qsize*16)
buf_emit 0x05; buf_emit32 0x610000  # add eax, 0x610000 = avail_base
buf_emit 0x89; buf_emit 0xC7  # mov edi, eax
# avail->flags = 0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x07; buf_emit16 0
# avail->idx = 1
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 2; buf_emit16 1
# avail->ring[0] = 0 (desc index 0)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit16 0

# mfence + notify TX queue (queue 1)
buf_emit 0x0F; buf_emit 0xAE; buf_emit 0xF0  # mfence
buf_emit 0x8D; buf_emit 0x53; buf_emit 0x10  # lea edx, [rbx+16] (queue notify)
buf_emit 0xB0; buf_emit 1; buf_emit 0xEE      # mov al, 1; out dx, al

emit_serial_string "  [ok] VirtIO-net: ARP request sent (who-has 10.0.2.2)`r`n" $COM1

# Jump past net scan loop end
$jmp_net_done_patch = buf_len
buf_emit 0xE9; buf_emit32 0  # jmp net_done (patched)

# net_next: (didn't match)
$net_next_off = buf_len
$nn_rel = $net_next_off - ($jne_net_next_patch + 6)
buf_set ($jne_net_next_patch + 2) ([byte]($nn_rel -band 0xFF))
buf_set ($jne_net_next_patch + 3) ([byte](($nn_rel -shr 8) -band 0xFF))
buf_set ($jne_net_next_patch + 4) ([byte](($nn_rel -shr 16) -band 0xFF))
buf_set ($jne_net_next_patch + 5) ([byte](($nn_rel -shr 24) -band 0xFF))
buf_emit 0x49; buf_emit 0xFF; buf_emit 0xC6  # inc r14
buf_emit 0x49; buf_emit 0x83; buf_emit 0xFE; buf_emit 32
buf_emit 0x0F; buf_emit 0x8C  # jl near net_scan_loop
$net_jl_rel = $net_scan_loop - (buf_len) - 4
buf_emit32_signed $net_jl_rel

# net_done:
$net_done_off = buf_len
$nd_rel = $net_done_off - ($jmp_net_done_patch + 5)
buf_set ($jmp_net_done_patch + 1) ([byte]($nd_rel -band 0xFF))
buf_set ($jmp_net_done_patch + 2) ([byte](($nd_rel -shr 8) -band 0xFF))
buf_set ($jmp_net_done_patch + 3) ([byte](($nd_rel -shr 16) -band 0xFF))
buf_set ($jmp_net_done_patch + 4) ([byte](($nd_rel -shr 24) -band 0xFF))

$after_net = buf_len
$jz_net_rel = $after_net - ($jz_no_net_patch + 6)
buf_set ($jz_no_net_patch + 2) ([byte]($jz_net_rel -band 0xFF))
buf_set ($jz_no_net_patch + 3) ([byte](($jz_net_rel -shr 8) -band 0xFF))
buf_set ($jz_no_net_patch + 4) ([byte](($jz_net_rel -shr 16) -band 0xFF))
buf_set ($jz_no_net_patch + 5) ([byte](($jz_net_rel -shr 24) -band 0xFF))

emit_dual_string "  [ok] Memory: 8MB identity mapped`r`n" $COM1

# Save VESA framebuffer address from [0x7000] to [0x3002B8]
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x7000  # mov eax, [0x7000]
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002B8  # mov [0x3002B8], eax
# Print VESA init status with LFB address
emit_serial_string "  [ok] VESA: 1024x768x32 LFB=" $COM1
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002B8
emit_serial_hex_eax $COM1
emit_serial_string "`r`n" $COM1

# Quick framebuffer test: write+read first pixel
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x3002B8  # mov edi, [LFB]
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0x00FF0000  # mov [rdi], 0x00FF0000 (blue in BGRA)
buf_emit 0x8B; buf_emit 0x07  # mov eax, [rdi] (read back)
buf_emit 0x3D; buf_emit32 0x00FF0000  # cmp eax, 0x00FF0000
$jne_vesa_fail = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # JNE fail (patch)
emit_serial_string "  [ok] VESA: framebuffer write/read verified`r`n" $COM1
$jmp_vesa_ok = buf_len
buf_emit 0xE9; buf_emit32 0  # JMP past fail (patch)
$vesa_fail_off = buf_len
$rel_vf = $vesa_fail_off - $jne_vesa_fail - 6
$b_vf = [System.BitConverter]::GetBytes([int32]$rel_vf)
buf_set ($jne_vesa_fail + 2) $b_vf[0]; buf_set ($jne_vesa_fail + 3) $b_vf[1]
buf_set ($jne_vesa_fail + 4) $b_vf[2]; buf_set ($jne_vesa_fail + 5) $b_vf[3]
emit_serial_string "  [!!] VESA: framebuffer test FAILED`r`n" $COM1
$vesa_ok_off = buf_len
$rel_vo = $vesa_ok_off - $jmp_vesa_ok - 5
$b_vo = [System.BitConverter]::GetBytes([int32]$rel_vo)
buf_set ($jmp_vesa_ok + 1) $b_vo[0]; buf_set ($jmp_vesa_ok + 2) $b_vo[1]
buf_set ($jmp_vesa_ok + 3) $b_vo[2]; buf_set ($jmp_vesa_ok + 4) $b_vo[3]

# === TSS + SYSCALL MSR Setup ===
# Initialize TSS at 0x6000 (104 bytes, mostly zeros)
# Clear TSS area
buf_emit 0xBF; buf_emit32 0x6000  # mov edi, 0x6000
buf_emit 0x31; buf_emit 0xC0; buf_emit 0xB9; buf_emit32 26  # xor eax,eax; mov ecx, 26 (104/4)
emit_cld; buf_emit 0xF3; buf_emit 0xAB  # rep stosd
# Set RSP0 (kernel stack) at TSS+4 (8 bytes)
buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x6004; buf_emit32 0x70000  # RSP0 low
buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x6008; buf_emit32 0       # RSP0 high
# Set IOPB offset at TSS+102 (2 bytes) = 104 (no IOPB)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x6066; buf_emit16 104

# Load TR (Task Register) with TSS selector 0x40
buf_emit 0x66; buf_emit 0xB8; buf_emit16 0x40  # mov ax, 0x40
buf_emit 0x0F; buf_emit 0x00; buf_emit 0xD8    # ltr ax

# Set SYSCALL MSRs
# STAR (0xC0000081): [63:48]=0x28 (SYSRET base), [47:32]=0x18 (SYSCALL CS), [31:0]=0
buf_emit 0xB9; buf_emit32 0xC0000081  # mov ecx, STAR
buf_emit 0xBA; buf_emit32 0x00280018  # mov edx, (0x28 << 16) | 0x18
buf_emit 0x31; buf_emit 0xC0          # xor eax, eax
buf_emit 0x0F; buf_emit 0x30          # wrmsr

# LSTAR (0xC0000082): syscall entry point (patched later)
buf_emit 0xB9; buf_emit32 0xC0000082  # mov ecx, LSTAR
$lstar_patch = buf_len
buf_emit 0xB8; buf_emit32 0           # mov eax, entry_low (patched)
buf_emit 0x31; buf_emit 0xD2          # xor edx, edx (entry_high = 0)
buf_emit 0x0F; buf_emit 0x30          # wrmsr

# FMASK (0xC0000084): mask IF (bit 9) on SYSCALL
buf_emit 0xB9; buf_emit32 0xC0000084  # mov ecx, FMASK
buf_emit 0xB8; buf_emit32 0x200       # mov eax, 0x200 (IF)
buf_emit 0x31; buf_emit 0xD2          # xor edx, edx
buf_emit 0x0F; buf_emit 0x30          # wrmsr

emit_dual_string "  [ok] SYSCALL: configured`r`n" $COM1

# Jump past SYSCALL entry stub
$jmp_past_syscall = buf_len
buf_emit 0xE9; buf_emit32 0  # patched

# === SYSCALL Entry Stub ===
# On SYSCALL: RCX=return RIP, R11=saved RFLAGS, CS=0x18, SS=0x20
# Convention: RAX=syscall number (0=exit, 1=print_char with RDI=char)
$syscall_entry_off = buf_len

# Save user RSP, then switch to the kernel stack.
buf_emit 0x48; buf_emit 0x87; buf_emit 0xE4  # xchg rsp, rsp (two-byte no-op)
buf_emit 0x48; buf_emit 0x89; buf_emit 0x24; buf_emit 0x25; buf_emit32 0x6100  # mov [0x6100], rsp (save user RSP)
buf_emit 0x48; buf_emit 0xBC  # mov rsp, imm64 (kernel stack)
buf_emit32 0x70000; buf_emit32 0

# Push user state for potential SYSRET
buf_emit 0x51  # push rcx (user RIP)
buf_emit 0x41; buf_emit 0x53  # push r11 (user RFLAGS)

# Dispatch: RAX=0 → exit, RAX=1 → print char (RDI=char)
buf_emit 0x48; buf_emit 0x83; buf_emit 0xF8; buf_emit 0  # cmp rax, 0
$je_syscall_exit = buf_len
buf_emit 0x0F; buf_emit 0x84; buf_emit32 0  # je exit (patched)

buf_emit 0x48; buf_emit 0x83; buf_emit 0xF8; buf_emit 1  # cmp rax, 1
$jne_syscall_ret = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # jne just_return (patched)

# Syscall 1: print char (RDI = ASCII char)
buf_emit 0x89; buf_emit 0xF8  # mov eax, edi (char)
buf_emit 0x50  # push rax
emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6  # jz wait
buf_emit 0x58  # pop rax
emit_mov_edx_imm32 $COM1; emit_out_dx_al

# SYSRET back to user: pop r11→RFLAGS, pop rcx→RIP
$syscall_ret_off = buf_len
$rel_sr = $syscall_ret_off - $jne_syscall_ret - 6
$b_sr = [System.BitConverter]::GetBytes([int32]$rel_sr)
buf_set ($jne_syscall_ret + 2) $b_sr[0]; buf_set ($jne_syscall_ret + 3) $b_sr[1]
buf_set ($jne_syscall_ret + 4) $b_sr[2]; buf_set ($jne_syscall_ret + 5) $b_sr[3]

buf_emit 0x41; buf_emit 0x5B  # pop r11
buf_emit 0x59  # pop rcx
# Restore user RSP
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x24; buf_emit 0x25; buf_emit32 0x6100
buf_emit 0x48; buf_emit 0x0F; buf_emit 0x07  # sysretq (REX.W + 0F 07)

# Syscall 0: exit — return to kernel shell
$syscall_exit_off = buf_len
$rel_se = $syscall_exit_off - $je_syscall_exit - 6
$b_se = [System.BitConverter]::GetBytes([int32]$rel_se)
buf_set ($je_syscall_exit + 2) $b_se[0]; buf_set ($je_syscall_exit + 3) $b_se[1]
buf_set ($je_syscall_exit + 4) $b_se[2]; buf_set ($je_syscall_exit + 5) $b_se[3]

buf_emit 0x41; buf_emit 0x5B  # pop r11
buf_emit 0x59  # pop rcx
# Switch back to kernel stack (already on it), restore kernel state
buf_emit 0x48; buf_emit 0xBC  # mov rsp, kernel stack
buf_emit32 0x70000; buf_emit32 0
# Return to ring3 command handler (stored at [0x6108])
buf_emit 0xFF; buf_emit 0x24; buf_emit 0x25; buf_emit32 0x6108  # jmp [0x6108]

# Patch LSTAR to point to syscall_entry
$entry_addr = 0x100000 + $syscall_entry_off
buf_set ($lstar_patch + 1) ([byte]($entry_addr -band 0xFF))
buf_set ($lstar_patch + 2) ([byte](($entry_addr -shr 8) -band 0xFF))
buf_set ($lstar_patch + 3) ([byte](($entry_addr -shr 16) -band 0xFF))
buf_set ($lstar_patch + 4) ([byte](($entry_addr -shr 24) -band 0xFF))

# Patch jump past syscall entry
$past_off = buf_len
$rel_ps = $past_off - $jmp_past_syscall - 5
$b_ps = [System.BitConverter]::GetBytes([int32]$rel_ps)
buf_set ($jmp_past_syscall + 1) $b_ps[0]; buf_set ($jmp_past_syscall + 2) $b_ps[1]
buf_set ($jmp_past_syscall + 3) $b_ps[2]; buf_set ($jmp_past_syscall + 4) $b_ps[3]

emit_dual_string "  [ok] Modules: 113 kernel, 27 userspace`r`n" $COM1
emit_dual_string "=== Boot Complete ===`r`n" $COM1

# === Call appended `kernel.bin` entrypoint when present ===
# Absolute address = 0x120000 + `_start` offset (read from `kernel.entry`)
if ($kb_entry_offset -ge 0 -and (Test-Path (Join-Path $PSScriptRoot '..\bare-kernel\kernel.bin'))) {
    $start_addr = [int64]0x120000 + $kb_entry_offset
    Write-Host "  Emitting CALL _start at 0x$($start_addr.ToString('X'))" -ForegroundColor Cyan
    # mov rax, imm64 (REX.W + B8 + imm64)
    buf_emit 0x48; buf_emit 0xB8
    $ab = [System.BitConverter]::GetBytes([int64]$start_addr)
    for ($bi = 0; $bi -lt 8; $bi++) { buf_emit $ab[$bi] }
    # call rax (FF D0)
    buf_emit 0xFF; buf_emit 0xD0
}

emit_dual_string "HicOS> " $COM1
buf_emit 0xE9  # jmp rel32
$jmp_past_puts_patch = buf_len
buf_emit32 0  # patched after subroutine

# === serial_puts subroutine ===
# Callable function: RSI = pointer to null-terminated string -> prints via COM1
# Clobbers: RAX, RBX, RDX. Preserves RSI (advances past string).
$serial_puts_off = buf_len
# .loop: movzx ebx, byte [rsi]
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x1E
# test bl, bl
buf_emit 0x84; buf_emit 0xDB
# jz .done (+23)
buf_emit 0x74; buf_emit 23
# .wait: mov edx, COM1+5
emit_mov_edx_imm32 ($COM1 + 5)
# in al, dx
emit_in_al_dx
# test al, 0x20
emit_test_al_imm8 0x20
# jz .wait (-10 = 0xF6)
buf_emit 0x74; buf_emit 0xF6
# mov edx, COM1
emit_mov_edx_imm32 $COM1
# mov al, bl
buf_emit 0x88; buf_emit 0xD8
# out dx, al
emit_out_dx_al
# inc rsi
buf_emit 0x48; buf_emit 0xFF; buf_emit 0xC6
# jmp .loop (-30 = 0xE2)
buf_emit 0xEB; buf_emit 0xE2
# .done: ret
emit_ret

# === serial_hex_byte subroutine ===
# Callable function: AL = byte to print as 2 hex chars to COM1
# Clobbers: RAX, RBX, RDX. Preserves all others.
$serial_hex_byte_off = buf_len
# Save byte in BL
buf_emit 0x88; buf_emit 0xC3  # mov bl, al
# High nibble: shr al, 4
buf_emit 0xC0; buf_emit 0xE8; buf_emit 4  # shr al, 4
buf_emit 0x24; buf_emit 0x0F  # and al, 0xF
buf_emit 0x3C; buf_emit 10    # cmp al, 10
buf_emit 0x72; buf_emit 2     # jb .digit1
buf_emit 0x04; buf_emit 7     # add al, 7
# .digit1:
buf_emit 0x04; buf_emit 0x30  # add al, '0'
# Save in BH for now
buf_emit 0x88; buf_emit 0xC7  # mov bh, al
# Wait TX ready
emit_mov_edx_imm32 ($COM1 + 5)
emit_in_al_dx
emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6  # jz -10 (back to wait)
# Send high nibble
emit_mov_edx_imm32 $COM1
buf_emit 0x88; buf_emit 0xF8  # mov al, bh
emit_out_dx_al
# Low nibble
buf_emit 0x88; buf_emit 0xD8  # mov al, bl
buf_emit 0x24; buf_emit 0x0F  # and al, 0xF
buf_emit 0x3C; buf_emit 10
buf_emit 0x72; buf_emit 2
buf_emit 0x04; buf_emit 7
buf_emit 0x04; buf_emit 0x30
buf_emit 0x88; buf_emit 0xC7  # mov bh, al
emit_mov_edx_imm32 ($COM1 + 5)
emit_in_al_dx
emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6
emit_mov_edx_imm32 $COM1
buf_emit 0x88; buf_emit 0xF8  # mov al, bh
emit_out_dx_al
emit_ret

# === serial_space subroutine ===
# Print a single space to COM1
$serial_space_off = buf_len
emit_mov_edx_imm32 ($COM1 + 5)
emit_in_al_dx
emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6
emit_mov_edx_imm32 $COM1
buf_emit 0xB0; buf_emit 0x20  # mov al, ' '
emit_out_dx_al
emit_ret

# === disk_rw_sector subroutine ===
# Reusable VirtIO-blk sector read/write.
#   R8D = sector number
#   R9  = buffer address (512 bytes)
#   R10B = operation: 0=READ, 1=WRITE
# Returns: AL = status (0=OK)
# Clobbers: RAX, RCX, RDX, RDI
$disk_rw_off = buf_len

# Build request header at 0x500000: type(4) + reserved(4) + sector(8)
buf_emit 0xBF; buf_emit32 0x500000              # mov edi, 0x500000
buf_emit 0x41; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0xC2  # movzx eax, r10b (type) REX.B for R10
buf_emit 0x89; buf_emit 0x07                     # mov [rdi], eax
buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit32 0  # reserved = 0
buf_emit 0x44; buf_emit 0x89; buf_emit 0x47; buf_emit 8  # mov [rdi+8], r8d (sector lo)
buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit32 0  # sector hi = 0

# Reset status byte
buf_emit 0xC6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500210; buf_emit 0xFF

# Setup desc[0]: header (addr=0x500000, len=16, flags=NEXT, next=1)
buf_emit 0xBF; buf_emit32 0x400000              # mov edi, desc_base
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0x500000  # desc[0].addr lo
buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit32 0  # addr hi
buf_emit 0xC7; buf_emit 0x47; buf_emit 8; buf_emit32 16  # len
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit16 1  # flags=NEXT
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 14; buf_emit16 1  # next=1

# Setup desc[1]: data buffer (addr=R9, len=512, flags depend on op, next=2)
# desc[1].addr = R9
buf_emit 0x4C; buf_emit 0x89; buf_emit 0x4F; buf_emit 16  # mov [rdi+16], r9
buf_emit 0xC7; buf_emit 0x47; buf_emit 20; buf_emit32 0    # addr hi = 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 24; buf_emit32 512  # len=512
# flags: READ -> WRITE|NEXT (0x0003), WRITE -> NEXT only (0x0001)
# If r10b==0 (READ): device writes data -> flags = WRITE|NEXT = 3
# If r10b==1 (WRITE): device reads data -> flags = NEXT = 1
buf_emit 0xB8; buf_emit32 3                     # mov eax, 3 (assume READ)
buf_emit 0x41; buf_emit 0x80; buf_emit 0xFA; buf_emit 0  # cmp r10b, 0
buf_emit 0x74; buf_emit 3                       # je +3 (skip)
buf_emit 0xB8; buf_emit32 1                     # mov eax, 1 (WRITE)
buf_emit 0x66; buf_emit 0x89; buf_emit 0x47; buf_emit 28  # mov word [rdi+28], ax
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 30; buf_emit16 2  # next=2

# Setup desc[2]: status (addr=0x500210, len=1, flags=WRITE, next=0)
buf_emit 0xC7; buf_emit 0x47; buf_emit 32; buf_emit32 0x500210
buf_emit 0xC7; buf_emit 0x47; buf_emit 36; buf_emit32 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 40; buf_emit32 1
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 44; buf_emit16 2
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 46; buf_emit16 0

# Load avail_idx from [0x300270], add desc 0 to the avail ring, and bump idx.
emit_virtq_push_desc0_from_abs 0x300260 0x300270

# mfence + notify
emit_virtio_notify_queue_from_bar_abs 0x300238 0

# Poll used ring: wait for used->idx >= our expected avail idx.
emit_virtq_poll_used_from_abs 0x300270 0x300268

# Read status
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x500210  # movzx eax, byte [status]
emit_ret

# === net_send subroutine ===
# Send a packet via VirtIO-net TX queue.
#   R8D = packet length (Ethernet frame, no VirtIO header)
#   R9  = packet buffer address
# VirtIO-net header (10 bytes, all zeros) placed at 0x630F00.
# Clobbers: RAX, RCX, RDX, RDI, RBX
$net_send_off = buf_len

# Zero the 10-byte VirtIO-net header at 0x630F00
buf_emit 0xBF; buf_emit32 0x630F00
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit32 0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 8; buf_emit16 0

# Setup TX descriptors at 0x610000:
# desc[0]: VirtIO header (addr=0x630F00, len=10, flags=NEXT, next=1)
# desc[1]: packet data (addr=R9, len=R8D, flags=0, next=0)
buf_emit 0xBF; buf_emit32 0x610000
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0x630F00       # desc[0].addr lo
buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit32 0  # addr hi
buf_emit 0xC7; buf_emit 0x47; buf_emit 8; buf_emit32 10 # len=10
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit16 1  # flags=NEXT
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 14; buf_emit16 1  # next=1
# desc[1]: packet
buf_emit 0x4C; buf_emit 0x89; buf_emit 0x4F; buf_emit 16  # mov [rdi+16], r9 (addr)
buf_emit 0xC7; buf_emit 0x47; buf_emit 20; buf_emit32 0    # addr hi
buf_emit 0x44; buf_emit 0x89; buf_emit 0x47; buf_emit 24   # mov [rdi+24], r8d (len)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 28; buf_emit16 0  # flags=0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 30; buf_emit16 0  # next=0

# Compute TX avail_base = 0x610000 + tx_qsize*16
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300290  # mov eax, [tx_qsize]
buf_emit 0xC1; buf_emit 0xE0; buf_emit 4  # shl eax, 4
buf_emit 0x05; buf_emit32 0x610000  # add eax, 0x610000
buf_emit 0x89; buf_emit 0xC7  # mov edi, eax (avail_base)
buf_emit 0x89; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300294  # mov [0x300294], edi

# Load TX avail idx from [0x300298], add desc 0 to the avail ring, and bump idx.
emit_virtq_push_desc0_from_abs 0x300294 0x300298

# mfence + notify TX queue 1
emit_virtio_notify_queue_from_bar_abs 0x300280 1

# Poll TX used ring: load expected idx, compute TX used_base, then poll.
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x300298  # movzx ecx, word [tx_avail_idx]
# Compute used_base for TX: align4096(avail_base + 6 + qsize*2)
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300290  # tx_qsize
buf_emit 0xD1; buf_emit 0xE0  # shl eax, 1 (qsize*2)
buf_emit 0x83; buf_emit 0xC0; buf_emit 6  # add eax, 6
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300290
buf_emit 0xC1; buf_emit 0xE7; buf_emit 4  # shl edi, 4
buf_emit 0x81; buf_emit 0xC7; buf_emit32 0x610000  # add edi, 0x610000
buf_emit 0x01; buf_emit 0xF8  # add eax, edi
buf_emit 0x05; buf_emit32 0xFFF  # add eax, 0xFFF
buf_emit 0x25; buf_emit32 0xFFFFF000  # align
buf_emit 0x89; buf_emit 0xC7  # mov edi, eax (used_base)
emit_virtq_poll_used_loop
emit_ret

# === net_rx_poll subroutine ===
# Check if a packet has been received. Returns:
#   EAX = 0 if no packet, >0 = received packet length (with VirtIO header)
#   If received, the packet data is at 0x620000+rx_slot*2048+10 (skip VirtIO header)
# Clobbers: RAX, RCX, RDX, RDI
$net_rx_poll_off = buf_len

# Compute RX used_base
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300288  # rx_qsize
buf_emit 0xD1; buf_emit 0xE0  # shl eax, 1
buf_emit 0x83; buf_emit 0xC0; buf_emit 6
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xC1; buf_emit 0xE7; buf_emit 4  # qsize*16
buf_emit 0x81; buf_emit 0xC7; buf_emit32 0x600000  # add 0x600000
buf_emit 0x01; buf_emit 0xF8  # add eax, edi
buf_emit 0x05; buf_emit32 0xFFF
buf_emit 0x25; buf_emit32 0xFFFFF000
buf_emit 0x89; buf_emit 0xC7  # mov edi, eax (RX used_base)

# Check used->idx > last_rx_used (stored at [0x3002A0])
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 2  # movzx eax, word [rdi+2]
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0  # last_rx_used
buf_emit 0x39; buf_emit 0xC8  # cmp eax, ecx
buf_emit 0x7F; buf_emit 4     # jg have_packet
buf_emit 0x31; buf_emit 0xC0  # xor eax, eax (no packet)
emit_ret
# have_packet: read used ring entry
# used_ring entry at used_base + 4 + (last_rx_used % qsize) * 8
buf_emit 0x89; buf_emit 0xC8  # mov eax, ecx (last_rx_used)
buf_emit 0x8B; buf_emit 0x14; buf_emit 0x25; buf_emit32 0x300288  # mov edx, [rx_qsize]
buf_emit 0xFF; buf_emit 0xCA  # dec edx (qsize-1, for and-mask)
buf_emit 0x21; buf_emit 0xD0  # and eax, edx (idx % qsize)
buf_emit 0xC1; buf_emit 0xE0; buf_emit 3  # shl eax, 3 (*8)
buf_emit 0x83; buf_emit 0xC0; buf_emit 4  # add eax, 4
buf_emit 0x8B; buf_emit 0x44; buf_emit 0x07; buf_emit 4  # mov eax, [rdi+rax+4] = used_len

# Advance last_rx_used
buf_emit 0xFF; buf_emit 0xC1  # inc ecx
buf_emit 0x66; buf_emit 0x89; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0

# Re-post the RX buffer: add desc back to avail ring
# Compute RX avail_base = 0x600000 + rx_qsize*16
buf_emit 0x51  # push rcx (save)
buf_emit 0x50  # push rax (save len)
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xC1; buf_emit 0xE0; buf_emit 4
buf_emit 0x05; buf_emit32 0x600000
buf_emit 0x89; buf_emit 0xC7  # mov edi, eax (RX avail_base)
# Load RX avail idx from [0x3002A8] (we'll reuse 0x3002A8 for this)
# Actually, use avail->idx at [edi+2]
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 2  # movzx eax, word [edi+2]
buf_emit 0x89; buf_emit 0xC1; buf_emit 0xD1; buf_emit 0xE1
buf_emit 0x83; buf_emit 0xC1; buf_emit 4
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x0F; buf_emit16 0  # ring[idx%q] = desc 0
buf_emit 0xFF; buf_emit 0xC0
buf_emit 0x66; buf_emit 0x89; buf_emit 0x47; buf_emit 2  # avail->idx++

# Notify RX queue 0
emit_virtio_notify_queue_from_bar_abs 0x300280 0

buf_emit 0x58  # pop rax (restore len)
buf_emit 0x59  # pop rcx
emit_ret

# === vga_putchar subroutine ===
# Write character in BL to VGA text buffer at current cursor position.
# Handles: printable chars, CR (13), LF (10), BS (8)
# Clobbers: RAX, RCX, RDX, RDI. Preserves: RBX, RSI.
$vga_putchar_off = buf_len

# Check LF (10): newline -> col=0, row++
buf_emit 0x80; buf_emit 0xFB; buf_emit 10  # cmp bl, 10
buf_emit 0x75; buf_emit 0  # jne .not_lf (patched)
$jne_not_lf_patch = (buf_len) - 1
# col = 0
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25
buf_emit32 $VGA_COL_ADDR; buf_emit32 0
# row++
buf_emit 0x48; buf_emit 0xFF; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_ROW_ADDR
# Check row >= 25 -> scroll
buf_emit 0x48; buf_emit 0x83; buf_emit 0x3C; buf_emit 0x25; buf_emit32 $VGA_ROW_ADDR; buf_emit 25
buf_emit 0x7C; buf_emit 0  # jl .lf_done (patched)
$jl_lf_done_patch = (buf_len) - 1
# === VGA SCROLL: copy rows 1..24 to 0..23, clear row 24 ===
# row = 24
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25
buf_emit32 $VGA_ROW_ADDR; buf_emit32 24
# Save RBX (caller's char), RSI
buf_emit 0x53  # push rbx
buf_emit 0x56  # push rsi
# Copy 24 rows * 160 bytes = 3840 bytes from 0xB80A0 to 0xB8000
# mov rdi, 0xB8000 (dest = row 0)
buf_emit 0x48; buf_emit 0xBF; buf_emit32 $VGA_TEXT_BASE; buf_emit32 0
# mov rsi, 0xB80A0 (src = row 1 = 0xB8000 + 160)
buf_emit 0x48; buf_emit 0xBE; buf_emit32 ([uint32]($VGA_TEXT_BASE + 160)); buf_emit32 0
# mov rcx, 3840 (24 rows * 160 bytes)
buf_emit 0x48; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 3840
# cld; rep movsb
emit_cld
buf_emit 0xF3; buf_emit 0xA4  # rep movsb
# Clear row 24: fill 160 bytes at 0xB8000 + 24*160 = 0xB8F00 with space+attr
# mov rdi, 0xB8F00
buf_emit 0x48; buf_emit 0xBF; buf_emit32 ([uint32]($VGA_TEXT_BASE + 24 * 160)); buf_emit32 0
# mov rcx, 80 (80 character cells)
buf_emit 0x48; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 80
# .clear_loop: mov word [rdi], 0x0720 (space + light gray attr); add rdi, 2; dec rcx; jnz
$vga_clear_loop = buf_len
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x07; buf_emit 0x20; buf_emit 0x07  # mov word [rdi], 0x0720
buf_emit 0x48; buf_emit 0x83; buf_emit 0xC7; buf_emit 2  # add rdi, 2
buf_emit 0x48; buf_emit 0xFF; buf_emit 0xC9  # dec rcx
buf_emit 0x75; buf_emit ([byte](($vga_clear_loop - (buf_len) - 1) -band 0xFF))  # jnz .clear_loop
# Restore RSI, RBX
buf_emit 0x5E  # pop rsi
buf_emit 0x5B  # pop rbx
# .lf_done:
buf_set $jl_lf_done_patch ([byte]((buf_len) - $jl_lf_done_patch - 1))
emit_ret
# .not_lf:
buf_set $jne_not_lf_patch ([byte]((buf_len) - $jne_not_lf_patch - 1))

# Check CR (13): col=0
buf_emit 0x80; buf_emit 0xFB; buf_emit 13  # cmp bl, 13
buf_emit 0x75; buf_emit 0  # jne .not_cr
$jne_not_cr_patch = (buf_len) - 1
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25
buf_emit32 $VGA_COL_ADDR; buf_emit32 0
emit_ret
buf_set $jne_not_cr_patch ([byte]((buf_len) - $jne_not_cr_patch - 1))

# Check BS (8): col-- and erase
buf_emit 0x80; buf_emit 0xFB; buf_emit 8  # cmp bl, 8
buf_emit 0x75; buf_emit 0  # jne .not_bs
$jne_not_vbs_patch = (buf_len) - 1
# if col > 0: col--
buf_emit 0x48; buf_emit 0x83; buf_emit 0x3C; buf_emit 0x25; buf_emit32 $VGA_COL_ADDR; buf_emit 0
buf_emit 0x74; buf_emit 0  # je .bs_done
$je_vbs_done_patch = (buf_len) - 1
# dec col
buf_emit 0x48; buf_emit 0xFF; buf_emit 0x0C; buf_emit 0x25; buf_emit32 $VGA_COL_ADDR
# Erase: compute offset, write space+attr
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_ROW_ADDR  # mov rax, [row]
buf_emit 0x48; buf_emit 0x6B; buf_emit 0xC0; buf_emit 80  # imul rax, 80
buf_emit 0x48; buf_emit 0x03; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_COL_ADDR  # add rax, [col]
buf_emit 0x48; buf_emit 0xD1; buf_emit 0xE0  # shl rax, 1
buf_emit 0x48; buf_emit 0xBF; buf_emit32 $VGA_TEXT_BASE; buf_emit32 0  # mov rdi, 0xB8000
buf_emit 0x48; buf_emit 0x01; buf_emit 0xC7  # add rdi, rax
buf_emit 0xC6; buf_emit 0x07; buf_emit 0x20  # mov byte [rdi], ' '
buf_emit 0xC6; buf_emit 0x47; buf_emit 1; buf_emit 0x07  # mov byte [rdi+1], 0x07
# .bs_done:
buf_set $je_vbs_done_patch ([byte]((buf_len) - $je_vbs_done_patch - 1))
emit_ret
buf_set $jne_not_vbs_patch ([byte]((buf_len) - $jne_not_vbs_patch - 1))

# Default: printable character in BL
# Compute VGA offset: (row * 80 + col) * 2
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_ROW_ADDR
buf_emit 0x48; buf_emit 0x6B; buf_emit 0xC0; buf_emit 80  # imul rax, 80
buf_emit 0x48; buf_emit 0x03; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_COL_ADDR
buf_emit 0x48; buf_emit 0xD1; buf_emit 0xE0  # shl rax, 1
buf_emit 0x48; buf_emit 0xBF; buf_emit32 $VGA_TEXT_BASE; buf_emit32 0
buf_emit 0x48; buf_emit 0x01; buf_emit 0xC7  # add rdi, rax
# Write char + attribute
buf_emit 0x88; buf_emit 0x1F  # mov byte [rdi], bl
buf_emit 0xC6; buf_emit 0x47; buf_emit 1; buf_emit 0x07  # mov byte [rdi+1], 0x07
# Advance col
buf_emit 0x48; buf_emit 0xFF; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_COL_ADDR
# If col >= 80: col=0, row++
buf_emit 0x48; buf_emit 0x83; buf_emit 0x3C; buf_emit 0x25; buf_emit32 $VGA_COL_ADDR; buf_emit 80
buf_emit 0x7C; buf_emit 0  # jl .no_wrap
$jl_nowrap_patch = (buf_len) - 1
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_COL_ADDR; buf_emit32 0
buf_emit 0x48; buf_emit 0xFF; buf_emit 0x04; buf_emit 0x25; buf_emit32 $VGA_ROW_ADDR
# If row >= 25: call vga_putchar with LF to trigger scroll
buf_emit 0x48; buf_emit 0x83; buf_emit 0x3C; buf_emit 0x25; buf_emit32 $VGA_ROW_ADDR; buf_emit 25
buf_emit 0x7C; buf_emit 0  # jl .no_wrap2
$jl_nowrap2_patch = (buf_len) - 1
# Scroll inline: same as LF scroll above
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25
buf_emit32 $VGA_ROW_ADDR; buf_emit32 24
buf_emit 0x53; buf_emit 0x56  # push rbx, rsi
buf_emit 0x48; buf_emit 0xBF; buf_emit32 $VGA_TEXT_BASE; buf_emit32 0
buf_emit 0x48; buf_emit 0xBE; buf_emit32 ([uint32]($VGA_TEXT_BASE + 160)); buf_emit32 0
buf_emit 0x48; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 3840
emit_cld
buf_emit 0xF3; buf_emit 0xA4  # rep movsb
buf_emit 0x48; buf_emit 0xBF; buf_emit32 ([uint32]($VGA_TEXT_BASE + 24 * 160)); buf_emit32 0
buf_emit 0x48; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 80
$vga_wrap_clear = buf_len
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x07; buf_emit 0x20; buf_emit 0x07
buf_emit 0x48; buf_emit 0x83; buf_emit 0xC7; buf_emit 2
buf_emit 0x48; buf_emit 0xFF; buf_emit 0xC9
buf_emit 0x75; buf_emit ([byte](($vga_wrap_clear - (buf_len) - 1) -band 0xFF))
buf_emit 0x5E; buf_emit 0x5B  # pop rsi, rbx
buf_set $jl_nowrap2_patch ([byte]((buf_len) - $jl_nowrap2_patch - 1))
# .no_wrap:
buf_set $jl_nowrap_patch ([byte]((buf_len) - $jl_nowrap_patch - 1))
emit_ret

# Patch the jump past subroutines (serial_puts + disk_rw + net_send + net_rx_poll + vga_putchar)
$past_puts_off = buf_len
$rel_pp = $past_puts_off - $jmp_past_puts_patch - 4
$bytes_pp = [System.BitConverter]::GetBytes([int32]$rel_pp)
for ($p = 0; $p -lt 4; $p++) { buf_set ($jmp_past_puts_patch + $p) $bytes_pp[$p] }

# Initialize disk I/O avail counter (starts at 3, after boot-time read+write+readback)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300270
buf_emit16 3  # avail_idx = 3

# Initialize TX avail counter (starts at 1, after boot ARP send)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300298
buf_emit16 1
# Initialize RX last_used counter = 0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002A0
buf_emit16 0
# Initialize our IP to 0 (no IP yet)
buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002A8; buf_emit32 0

# === Post initial RX buffers ===
# Give device 8 RX buffers at 0x620000 + i*2048 (each 2048 bytes)
# Each RX descriptor: addr=buffer, len=2048, flags=WRITE(2), next=0
buf_emit 0x31; buf_emit 0xC9  # xor ecx, ecx (i=0)
$rx_post_loop = buf_len
# desc[i].addr = 0x620000 + i*2048
buf_emit 0x89; buf_emit 0xC8  # mov eax, ecx
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11  # shl eax, 11 (i*2048)
buf_emit 0x05; buf_emit32 0x620000  # add eax, 0x620000
# desc offset = i*16
buf_emit 0x89; buf_emit 0xCA  # mov edx, ecx
buf_emit 0xC1; buf_emit 0xE2; buf_emit 4  # shl edx, 4
buf_emit 0x81; buf_emit 0xC2; buf_emit32 0x600000  # add edx, 0x600000 (desc_base)
# desc[i].addr
buf_emit 0x89; buf_emit 0x02  # mov [rdx], eax
buf_emit 0xC7; buf_emit 0x42; buf_emit 4; buf_emit32 0  # addr hi
buf_emit 0xC7; buf_emit 0x42; buf_emit 8; buf_emit32 2048  # len
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x42; buf_emit 12; buf_emit16 2  # flags=WRITE
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x42; buf_emit 14; buf_emit16 0  # next=0
# avail ring[i] = i
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300288  # rx_qsize
buf_emit 0xC1; buf_emit 0xE0; buf_emit 4; buf_emit 0x05; buf_emit32 0x600000  # avail_base
buf_emit 0x89; buf_emit 0xC7  # mov edi, eax
buf_emit 0x89; buf_emit 0xC8  # mov eax, ecx
buf_emit 0xD1; buf_emit 0xE0; buf_emit 0x83; buf_emit 0xC0; buf_emit 4  # i*2+4
buf_emit 0x66; buf_emit 0x89; buf_emit 0x0C; buf_emit 0x07  # mov [edi+eax], cx (ring[i]=i)
# next
buf_emit 0xFF; buf_emit 0xC1  # inc ecx
buf_emit 0x83; buf_emit 0xF9; buf_emit 8  # cmp ecx, 8
buf_emit 0x7C
buf_emit ([byte](($rx_post_loop - (buf_len) - 1) -band 0xFF))
# Set avail->idx = 8
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 2; buf_emit16 8
# Notify RX queue 0
emit_virtio_notify_queue_from_bar_abs 0x300280 0

# === Initialize command buffer ===
# Memory layout: 0x300800 = cmd buffer (128 bytes), 0x300880 = write index (8 bytes)
# mov qword [0x300880], 0
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25
buf_emit32 0x300880; buf_emit32 0

# --- Main shell loop ---
$loop_start = buf_len
emit_hlt

# Check heartbeat flag at 0x300020 (set by timer ISR every 1 second)
buf_emit 0x48; buf_emit 0x83; buf_emit 0x3C; buf_emit 0x25
buf_emit32 0x300020; buf_emit 0
$je_no_heartbeat_main = buf_len
# Heartbeat indicator disabled: unconditionally skip the A/B char print
# (kept timer flag logic intact, only the noisy serial output is suppressed)
buf_emit 0xEB; buf_emit 0  # jmp skip_heartbeat (patched)
# Clear heartbeat flag
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300020; buf_emit32 0
# Print alternating task indicator based on [0x300030]: task0='A' task1='B'
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300030  # mov rax, [task_id]
buf_emit 0x04; buf_emit ([byte][char]'A')  # add al, 'A' (0→'A', 1→'B')
buf_emit 0x50  # push rax
emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6
buf_emit 0x58  # pop rax
emit_mov_edx_imm32 $COM1; emit_out_dx_al
# skip_heartbeat:
$skip_hb_off = buf_len
buf_set ($je_no_heartbeat_main + 1) ([byte](($skip_hb_off - $je_no_heartbeat_main - 2) -band 0xFF))

# === Serial RX poll: allow serial console input (COM1 RX ready check) ===
# Poll LSR bit0 (RX data ready); if no data, skip
emit_mov_edx_imm32 ($COM1 + 5)  # mov edx, COM1+5 (LSR)
emit_in_al_dx                    # in al, dx
emit_test_al_imm8 1              # test al, 0x01 (RX ready)
$je_serial_no_rx = buf_len
buf_emit 0x74; buf_emit 0        # je serial_no_rx (patched)
# Read byte from COM1
emit_mov_edx_imm32 $COM1
emit_in_al_dx                    # al = serial char
# movzx rax, al
buf_emit 0x48; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0xC0
# Skip NUL
buf_emit 0x84; buf_emit 0xC0     # test al, al
$je_serial_no_rx2 = buf_len
buf_emit 0x74; buf_emit 0        # je serial_no_rx (patched)
# mov rbx, rax (ASCII char in RBX, same state as keyboard-after-lookup)
buf_emit 0x48; buf_emit 0x89; buf_emit 0xC3
# jmp key_ascii_common (near jump, patched below)
buf_emit 0xE9
$jmp_key_ascii = buf_len
buf_emit32 0
# serial_no_rx:
$serial_no_rx_off = buf_len
buf_set ($je_serial_no_rx + 1) ([byte](($serial_no_rx_off - $je_serial_no_rx - 2) -band 0xFF))
buf_set ($je_serial_no_rx2 + 1) ([byte](($serial_no_rx_off - $je_serial_no_rx2 - 2) -band 0xFF))

# cmp qword [0x300010], 0 (key_ready)
buf_emit 0x48; buf_emit 0x83; buf_emit 0x3C; buf_emit 0x25
buf_emit32 0x300010; buf_emit 0
# je loop_start (skip if no key)
buf_emit 0x74
$je_rel = $loop_start - (buf_len) - 1
buf_emit ([byte]($je_rel -band 0xFF))

# Read raw scancode from 0x300008
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300008
# Clear key_ready
buf_emit 0x48; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300010; buf_emit32 0

# Filter: ignore key release (bit 7 set = scancode >= 0x80)
# test al, 0x80; jnz loop_start
buf_emit 0xA8; buf_emit 0x80
buf_emit 0x75
$jnz_rel = $loop_start - (buf_len) - 1
buf_emit ([byte]($jnz_rel -band 0xFF))

# Lookup ASCII: movzx rax, al; movzx rax, byte [0x300100 + rax]
buf_emit 0x48; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0xC0  # movzx rax, al
emit_mov_edx_imm32 0x300100
buf_emit 0x48; buf_emit 0x01; buf_emit 0xC2  # add rdx, rax
buf_emit 0x48; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x02  # movzx rax, byte [rdx]

# If ASCII == 0 (unmapped key), skip
# test al, al; jz loop_start
buf_emit 0x84; buf_emit 0xC0
buf_emit 0x74
$jz_rel = $loop_start - (buf_len) - 1
buf_emit ([byte]($jz_rel -band 0xFF))

# Save ASCII char in RBX
buf_emit 0x48; buf_emit 0x89; buf_emit 0xC3  # mov rbx, rax
# key_ascii_common: serial RX path jumps here (RBX already = ASCII char)
$key_ascii_common = buf_len
# Patch serial RX near jump to key_ascii_common
$rel_key_ascii = $key_ascii_common - ($jmp_key_ascii + 4)
$bytes_ka = [System.BitConverter]::GetBytes([int32]$rel_key_ascii)
for ($p = 0; $p -lt 4; $p++) { buf_set ($jmp_key_ascii + $p) $bytes_ka[$p] }

# === Check Backspace (ASCII 8 or 127) ===
buf_emit 0x80; buf_emit 0xFB; buf_emit 8  # cmp bl, 8
$je_bs_8 = buf_len
buf_emit 0x0F; buf_emit 0x84; buf_emit32 0  # je backspace (near, patched)
buf_emit 0x80; buf_emit 0xFB; buf_emit 0x7F  # cmp bl, 0x7F (DEL)
$je_bs_7f = buf_len
buf_emit 0x0F; buf_emit 0x84; buf_emit32 0  # je backspace (near, patched)
$jne_not_bs = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # jne not_bs (near, patched)
# backspace: patch both je targets to fall through here
$bs_target = buf_len
$rel_bs8 = $bs_target - ($je_bs_8 + 6)
$bytes_bs8 = [System.BitConverter]::GetBytes([int32]$rel_bs8)
for ($p = 0; $p -lt 4; $p++) { buf_set ($je_bs_8 + 2 + $p) $bytes_bs8[$p] }
$rel_bs7f = $bs_target - ($je_bs_7f + 6)
$bytes_bs7f = [System.BitConverter]::GetBytes([int32]$rel_bs7f)
for ($p = 0; $p -lt 4; $p++) { buf_set ($je_bs_7f + 2 + $p) $bytes_bs7f[$p] }
# Load index
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x300880  # mov rcx, [0x300880]
# If index == 0, nothing to delete -> jmp loop_start
buf_emit 0x48; buf_emit 0x85; buf_emit 0xC9  # test rcx, rcx
buf_emit 0x0F; buf_emit 0x84  # jz loop_start (near)
buf_emit32_signed ($loop_start - (buf_len) - 4)
# dec qword [0x300880]
buf_emit 0x48; buf_emit 0xFF; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x300880
# Echo: BS(8) + Space(32) + BS(8) to erase character on terminal
foreach ($bsc in @(8, 32, 8)) {
    emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
    buf_emit 0x74; buf_emit 0xF6
    emit_mov_edx_imm32 $COM1; emit_mov_al_imm8 $bsc; emit_out_dx_al
}
# Erase character on VGA: call vga_putchar with BL=8 (backspace) — disabled
# Pure serial shell: VGA echo hangs. Serial BS+SP+BS erase above is sufficient.
buf_emit 0xB3; buf_emit 8  # mov bl, 8
for ($vn = 0; $vn -lt 6; $vn++) { buf_emit 0x90 }  # 6x NOP replaces mov rax,imm64
buf_emit 0x90; buf_emit 0x90  # 2x NOP replaces call rax
# jmp loop_start
buf_emit 0xE9; buf_emit32_signed ($loop_start - (buf_len) - 4)
# not_bs: patch jne
$not_bs_off = buf_len
$rel_nb = $not_bs_off - $jne_not_bs - 6
$bytes_nb = [System.BitConverter]::GetBytes([int32]$rel_nb)
for ($p = 0; $p -lt 4; $p++) { buf_set ($jne_not_bs + 2 + $p) $bytes_nb[$p] }

# === Check Enter (ASCII 13) ===
buf_emit 0x80; buf_emit 0xFB; buf_emit 13  # cmp bl, 13
$jne_not_enter = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # jne not_enter (near, patched)
# Jump to command dispatch (forward reference, patched later)
buf_emit 0xE9  # jmp cmd_dispatch
$jmp_to_dispatch = buf_len
buf_emit32 0

# cmd_return: (dispatch returns here to clear buffer + print prompt)
$cmd_return = buf_len
# Clear buffer: mov rdi, 0x300800; xor eax, eax; mov ecx, 136; cld; rep stosb
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x300800; buf_emit32 0  # mov rdi, 0x300800
buf_emit 0x31; buf_emit 0xC0  # xor eax, eax
buf_emit 0xB9; buf_emit32 136  # mov ecx, 136
emit_cld
buf_emit 0xF3; buf_emit 0xAA  # rep stosb
# Print prompt
emit_dual_string "HicOS> " $COM1
# jmp loop_start
buf_emit 0xE9; buf_emit32_signed ($loop_start - (buf_len) - 4)

# not_enter: patch jne
$not_enter_off = buf_len
$rel_ne = $not_enter_off - $jne_not_enter - 6
$bytes_ne = [System.BitConverter]::GetBytes([int32]$rel_ne)
for ($p = 0; $p -lt 4; $p++) { buf_set ($jne_not_enter + 2 + $p) $bytes_ne[$p] }

# === Store character in buffer + echo ===
# mov rcx, [0x300880]  (buffer index)
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x300880
# cmp rcx, 126
buf_emit 0x48; buf_emit 0x83; buf_emit 0xF9; buf_emit 126
# jge loop_start (buffer full, ignore)
buf_emit 0x0F; buf_emit 0x8D; buf_emit32_signed ($loop_start - (buf_len) - 4)
# Store: mov rdi, 0x300800; add rdi, rcx; mov [rdi], bl
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x300800; buf_emit32 0  # mov rdi, 0x300800
buf_emit 0x48; buf_emit 0x01; buf_emit 0xCF  # add rdi, rcx
buf_emit 0x88; buf_emit 0x1F  # mov [rdi], bl
# inc qword [0x300880]
buf_emit 0x48; buf_emit 0xFF; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300880
# Echo character via serial
emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6
buf_emit 0x48; buf_emit 0x89; buf_emit 0xD8  # mov rax, rbx
emit_mov_edx_imm32 $COM1
emit_out_dx_al
# Echo character via VGA: disabled (pure serial shell, vga_putchar hangs)
for ($vn = 0; $vn -lt 6; $vn++) { buf_emit 0x90 }  # 6x NOP replaces 12-byte mov rax,imm64
buf_emit 0x90; buf_emit 0x90  # 2x NOP replaces call rax
# jmp loop_start
buf_emit 0xE9; buf_emit32_signed ($loop_start - (buf_len) - 4)

# =============================================================
# Command Dispatch (entered via jmp from Enter handler)
# =============================================================
$cmd_dispatch = buf_len
# Patch the forward jump to cmd_dispatch
$rel_disp = $cmd_dispatch - $jmp_to_dispatch - 4
$bytes_d = [System.BitConverter]::GetBytes([int32]$rel_disp)
for ($p = 0; $p -lt 4; $p++) { buf_set ($jmp_to_dispatch + $p) $bytes_d[$p] }

# Print CR+LF (serial + VGA)
emit_serial_string "`r`n" $COM1
# VGA newline: call vga_putchar with BL=10 (disabled, pure serial shell)
buf_emit 0xB3; buf_emit 10  # mov bl, 10 (LF)
for ($vn = 0; $vn -lt 6; $vn++) { buf_emit 0x90 }  # 6x NOP replaces mov rax,imm64
buf_emit 0x90; buf_emit 0x90  # 2x NOP replaces call rax
# Null-terminate buffer: mov rcx,[0x300880]; mov rdi,0x300800; add rdi,rcx; mov byte [rdi],0
buf_emit 0x48; buf_emit 0x8B; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x300880
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x300800; buf_emit32 0
buf_emit 0x48; buf_emit 0x01; buf_emit 0xCF  # add rdi, rcx
buf_emit 0xC6; buf_emit 0x07; buf_emit 0     # mov byte [rdi], 0
# If empty (rcx==0), skip dispatch
buf_emit 0x48; buf_emit 0x85; buf_emit 0xC9  # test rcx, rcx
buf_emit 0x0F; buf_emit 0x84  # jz cmd_return (near)
buf_emit32_signed ($cmd_return - (buf_len) - 4)
# Load buffer base into RSI (used by all emit_cmd_check calls)
buf_emit 0x48; buf_emit 0xBE; buf_emit32 0x300800; buf_emit32 0  # mov rsi, 0x300800

# Collect string data for deferred emission
$script:str_data = @()
$script:str_patches = @()

# Helper: emit "load string addr + call serial_puts" (address patched later)
function emit_call_puts_str([string]$str) {
    buf_emit 0xBE  # mov esi, imm32 (zero-extends to RSI)
    $script:str_patches += @([PSCustomObject]@{ loc = (buf_len); idx = $script:str_data.Count })
    buf_emit32 0  # placeholder for string address
    # call serial_puts (rel32)
    buf_emit 0xE8
    buf_emit32_signed ($script:serial_puts_off - (buf_len) - 4)
    $script:str_data += $str
}

# --- Command: help ---
emit_cmd_check "help"
emit_call_puts_str "=== HicOS Shell Commands ===`r`nSystem:  help ver reboot shutdown halt clear`r`nInfo:    free ps lspci uptime`r`nDisk:    format ls cat mkfile hexdump`r`nNet:     dhcp ping ifconfig nslookup`r`nGraphics: vesa`r`nKernel:  ring3`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)  # jmp cmd_return
patch_cmd_skip

# --- Command: ver ---
emit_cmd_check "ver"
emit_call_puts_str "HicOS 6.0 -- Hilbert-Lang Kernel (114 modules, zero deps)`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: free ---
emit_cmd_check "free"
emit_call_puts_str "Memory: 8 MB identity mapped`r`n  Heap:  0x300000-0x3FFFFF (1 MB)`r`n  Pages: 0x400000-0x7FFFFF (4 MB bitmap)`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: ps ---
emit_cmd_check "ps"
emit_call_puts_str "  PID 0  kernel   running`r`n  PID 1  idle     sleeping`r`nTasks: 2/64`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: lspci ---
emit_cmd_check "lspci"
emit_call_puts_str "PCI bus 0: 5 device(s)`r`n  0:0.0 Host bridge`r`n  0:1.0 ISA bridge`r`n  0:2.0 VGA`r`n  0:3.0 VirtIO-blk (1AF4:1001)`r`n  0:4.0 VirtIO-net (1AF4:1000)`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: uptime ---
emit_cmd_check "uptime"
# Dynamic: read tick counter at [0x300000], divide by 100, print
emit_call_puts_str "Uptime: 0x"
# mov eax, [0x300000]
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300000
# Push tick count, divide by 100 for seconds
# xor edx, edx; mov ecx, 100; div ecx  -> eax = seconds
buf_emit 0x31; buf_emit 0xD2  # xor edx, edx
buf_emit 0xB9; buf_emit32 100  # mov ecx, 100
buf_emit 0xF7; buf_emit 0xF1  # div ecx
# Print seconds as hex
emit_serial_hex_eax $COM1
emit_call_puts_str " seconds (hex)`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: reboot ---
emit_cmd_check "reboot"
emit_call_puts_str "Rebooting...`r`n"
# Keyboard controller reset: out 0x64, 0xFE
emit_mov_al_imm8 0xFE
buf_emit 0xE6; buf_emit 0x64  # out 0x64, al
# Fallback: PCI reset
emit_mov_edx_imm32 0xCF9
emit_mov_al_imm8 0x06
emit_out_dx_al
# HLT loop (in case reset fails)
emit_cli; emit_hlt
buf_emit 0xEB; buf_emit 0xFD  # jmp $-1 (infinite HLT)
patch_cmd_skip

# --- Command: shutdown ---
emit_cmd_check "shutdown"
emit_call_puts_str "Powering off...`r`n"
# QEMU ACPI shutdown: out 0x604, 0x2000
emit_mov_edx_imm32 0x604
buf_emit 0x66; buf_emit 0xB8; buf_emit 0x00; buf_emit 0x20  # mov ax, 0x2000
buf_emit 0x66; buf_emit 0xEF  # out dx, ax
# Fallback: HLT
emit_cli; emit_hlt
buf_emit 0xEB; buf_emit 0xFD
patch_cmd_skip

# --- Command: halt ---
emit_cmd_check "halt"
emit_call_puts_str "System halted.`r`n"
emit_cli; emit_hlt
buf_emit 0xEB; buf_emit 0xFD  # jmp $-1
patch_cmd_skip

# =============================================================
# FAT16 Commands (format, ls, cat, mkfile)
# =============================================================
# FAT16 layout for 32 MB disk (65536 sectors):
#   Sector 0:     BPB (Boot Parameter Block)
#   Sectors 1-3:  Reserved
#   Sectors 4-67: FAT1 (64 sectors = 32768 entries, enough for 32MB/2KB)
#   Sectors 68-131: FAT2 (copy)
#   Sectors 132-163: Root directory (32 sectors = 512 entries)
#   Sectors 164+: Data area (cluster 2 = sector 164)
#   Sectors per cluster: 4 (2048 bytes per cluster)
# Memory: 0x510000 = sector buffer (512 bytes), 0x511000 = FAT16 scratch

# --- Command: format ---
emit_cmd_check "format"
emit_call_puts_str "Formatting disk as FAT16...`r`n"

# Build BPB in scratch buffer at 0x510000 (512 bytes, cleared first)
# Clear 512 bytes
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x510000; buf_emit32 0  # mov rdi, 0x510000
buf_emit 0x31; buf_emit 0xC0  # xor eax, eax
buf_emit 0xB9; buf_emit32 128  # mov ecx, 128 (512/4)
emit_cld; buf_emit 0xF3; buf_emit 0xAB  # rep stosd

# Write BPB fields
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x510000; buf_emit32 0  # mov rdi, 0x510000
# 0x00: JMP + NOP
buf_emit 0xC6; buf_emit 0x07; buf_emit 0xEB          # [0] = 0xEB
buf_emit 0xC6; buf_emit 0x47; buf_emit 1; buf_emit 0x3C  # [1] = 0x3C
buf_emit 0xC6; buf_emit 0x47; buf_emit 2; buf_emit 0x90  # [2] = NOP
# 0x03: OEM = "HICOS   "
$oem = [byte[]]@(0x48,0x49,0x43,0x4F,0x53,0x20,0x20,0x20)
foreach ($i in 0..7) {
    buf_emit 0xC6; buf_emit 0x47; buf_emit ([byte](3+$i)); buf_emit $oem[$i]
}
# 0x0B: bytes per sector = 512 (0x0200)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 0x0B; buf_emit16 512
# 0x0D: sectors per cluster = 4
buf_emit 0xC6; buf_emit 0x47; buf_emit 0x0D; buf_emit 4
# 0x0E: reserved sectors = 4
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 0x0E; buf_emit16 4
# 0x10: number of FATs = 2
buf_emit 0xC6; buf_emit 0x47; buf_emit 0x10; buf_emit 2
# 0x11: root entry count = 512 (0x0200)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 0x11; buf_emit16 512
# 0x13: total sectors 16 = 0 (use 32-bit field)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 0x13; buf_emit16 0
# 0x15: media = 0xF8
buf_emit 0xC6; buf_emit 0x47; buf_emit 0x15; buf_emit 0xF8
# 0x16: FAT size = 64 sectors
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 0x16; buf_emit16 64
# 0x18: sectors per track = 63
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 0x18; buf_emit16 63
# 0x1A: heads = 16
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 0x1A; buf_emit16 16
# 0x1C: hidden sectors = 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 0x1C; buf_emit32 0
# 0x20: total sectors 32 = 65536
buf_emit 0xC7; buf_emit 0x47; buf_emit 0x20; buf_emit32 65536
# 0x24: drive number = 0x80
buf_emit 0xC6; buf_emit 0x47; buf_emit 0x24; buf_emit 0x80
# 0x26: ext boot sig = 0x29
buf_emit 0xC6; buf_emit 0x47; buf_emit 0x26; buf_emit 0x29
# 0x27: serial = 0x48434F53 ("HCOS")
buf_emit 0xC7; buf_emit 0x47; buf_emit 0x27; buf_emit32 0x48434F53
# 0x2B: volume label = "HICOS      "
$vol = [byte[]]@(0x48,0x49,0x43,0x4F,0x53,0x20,0x20,0x20,0x20,0x20,0x20)
foreach ($i in 0..10) {
    buf_emit 0xC6; buf_emit 0x47; buf_emit ([byte](0x2B+$i)); buf_emit $vol[$i]
}
# 0x36: FS type = "FAT16   "
$fst = [byte[]]@(0x46,0x41,0x54,0x31,0x36,0x20,0x20,0x20)
foreach ($i in 0..7) {
    buf_emit 0xC6; buf_emit 0x47; buf_emit ([byte](0x36+$i)); buf_emit $fst[$i]
}
# 0x1FE: boot sig = 0x55AA (mod=10 needs disp32)
buf_emit 0xC6; buf_emit 0x87; buf_emit32 0x01FE; buf_emit 0x55  # [rdi+0x1FE] = 0x55
buf_emit 0xC6; buf_emit 0x87; buf_emit32 0x01FF; buf_emit 0xAA  # [rdi+0x1FF] = 0xAA

# Write BPB to sector 0
buf_emit 0x45; buf_emit 0x31; buf_emit 0xC0     # xor r8d, r8d (sector=0)
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000  # mov r9, buf
buf_emit 0x41; buf_emit 0xB2; buf_emit 1        # mov r10b, 1 (WRITE)
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)  # call disk_rw
buf_emit 0x85; buf_emit 0xC0                    # test eax, eax
$jnz_fmt_fail = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0      # jnz format_fail (patched)

# Write FAT1 first sector (sector 4): F8 FF FF FF 00 00 ...
# Clear buffer
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x510000; buf_emit32 0
buf_emit 0x31; buf_emit 0xC0; buf_emit 0xB9; buf_emit32 128; emit_cld; buf_emit 0xF3; buf_emit 0xAB
# FAT entry 0 = 0xFFF8, entry 1 = 0xFFFF (reserved)
buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x510000; buf_emit32 0xFFFFFFF8
# Write to sector 4 (FAT1 start) and sector 68 (FAT2 start)
buf_emit 0x41; buf_emit 0xB0; buf_emit 4        # mov r8b, 4
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 1        # WRITE
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)
buf_emit 0x41; buf_emit 0xB0; buf_emit 68       # mov r8b, 68 (FAT2)
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 1
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)

# Write remaining FAT sectors (5-67 and 69-131) as zeros
# Clear buffer for zero sectors
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x510000; buf_emit32 0
buf_emit 0x31; buf_emit 0xC0; buf_emit 0xB9; buf_emit32 128; emit_cld; buf_emit 0xF3; buf_emit 0xAB
# Write zeros to FAT1 sectors 5-67 (63 sectors)
buf_emit 0x41; buf_emit 0xB0; buf_emit 5        # r8b = 5 (start)
$fmt_fat_loop = buf_len
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 1        # WRITE
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)
buf_emit 0x41; buf_emit 0xFE; buf_emit 0xC0     # inc r8b
buf_emit 0x41; buf_emit 0x80; buf_emit 0xF8; buf_emit 68  # cmp r8b, 68
buf_emit 0x7C  # jl loop
buf_emit ([byte](($fmt_fat_loop - (buf_len) - 1) -band 0xFF))
# FAT2 sectors 69-131
buf_emit 0x41; buf_emit 0xB0; buf_emit 69
$fmt_fat2_loop = buf_len
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 1
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)
buf_emit 0x41; buf_emit 0xFE; buf_emit 0xC0
buf_emit 0x41; buf_emit 0x80; buf_emit 0xF8; buf_emit 132
buf_emit 0x72  # jb (unsigned below) instead of jl (signed)
buf_emit ([byte](($fmt_fat2_loop - (buf_len) - 1) -band 0xFF))

# Write root directory (32 sectors of zeros, sectors 132-163)
buf_emit 0x41; buf_emit 0xB0; buf_emit 132
$fmt_root_loop = buf_len
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 1
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)
buf_emit 0x41; buf_emit 0xFE; buf_emit 0xC0
buf_emit 0x41; buf_emit 0x80; buf_emit 0xF8; buf_emit 164
buf_emit 0x72  # jb (unsigned below) instead of jl (signed)
buf_emit ([byte](($fmt_root_loop - (buf_len) - 1) -band 0xFF))

emit_call_puts_str "Format complete. FAT16, 32 MB, 2 KB clusters.`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
# format_fail:
$fmt_fail_off = buf_len
$rel_ff = $fmt_fail_off - $jnz_fmt_fail - 6
$bytes_ff = [System.BitConverter]::GetBytes([int32]$rel_ff)
for ($p = 0; $p -lt 4; $p++) { buf_set ($jnz_fmt_fail + 2 + $p) $bytes_ff[$p] }
emit_call_puts_str "Format FAILED.`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: ls ---
emit_cmd_check "ls"
# Read root directory sector 132 into 0x510000
buf_emit 0x41; buf_emit 0xB0; buf_emit 132      # mov r8b, 132
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000  # buf
buf_emit 0x41; buf_emit 0xB2; buf_emit 0        # READ
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)
# Parse up to 16 entries per sector (512/32=16)
# For simplicity, scan first sector only (16 entries)
# R12 = entry index, R13 = ptr
buf_emit 0x45; buf_emit 0x31; buf_emit 0xE4     # xor r12d, r12d
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC5; buf_emit32 0x510000  # mov r13, 0x510000
$ls_loop = buf_len
# Check first byte: 0x00 = end, 0xE5 = deleted, else valid
buf_emit 0x41; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x45; buf_emit 0  # movzx eax, byte [r13]
buf_emit 0x85; buf_emit 0xC0                    # test eax, eax
$jz_ls_end = buf_len
buf_emit 0x0F; buf_emit 0x84; buf_emit32 0      # jz ls_end (NEAR, patched)
buf_emit 0x3C; buf_emit 0xE5                    # cmp al, 0xE5 (deleted)
$je_ls_skip = buf_len
buf_emit 0x0F; buf_emit 0x84; buf_emit32 0      # je ls_skip (NEAR, patched)
# Check attr byte [r13+11]: skip if LFN (0x0F) or volume label (0x08)
buf_emit 0x41; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x45; buf_emit 11  # movzx eax, byte [r13+11]
buf_emit 0x3C; buf_emit 0x0F                    # cmp al, 0x0F
$je_ls_skip2 = buf_len
buf_emit 0x0F; buf_emit 0x84; buf_emit32 0      # je ls_skip (NEAR, patched)
buf_emit 0xA8; buf_emit 0x08                    # test al, 0x08 (volume label)
$jnz_ls_skip3 = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0      # jnz ls_skip (NEAR, patched)

# Print filename (8 chars from [r13+0]) + extension (3 chars from [r13+8])
# Print "  " prefix
emit_call_puts_str "  "
# Print 8 chars of filename via serial
buf_emit 0x31; buf_emit 0xC9                    # xor ecx, ecx
$ls_name_loop = buf_len
buf_emit 0x41; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x44; buf_emit 0x0D; buf_emit 0  # movzx eax, byte [r13+rcx]
buf_emit 0x50  # push rax
emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6
buf_emit 0x58  # pop rax
emit_mov_edx_imm32 $COM1; emit_out_dx_al
buf_emit 0xFF; buf_emit 0xC1                    # inc ecx
buf_emit 0x83; buf_emit 0xF9; buf_emit 8        # cmp ecx, 8
buf_emit 0x7C  # jl
buf_emit ([byte](($ls_name_loop - (buf_len) - 1) -band 0xFF))
# Print "."
emit_call_puts_str "."
# Print 3 chars of extension
buf_emit 0xB1; buf_emit 8                       # mov cl, 8
$ls_ext_loop = buf_len
buf_emit 0x41; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x44; buf_emit 0x0D; buf_emit 0
buf_emit 0x50
emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6; buf_emit 0x58
emit_mov_edx_imm32 $COM1; emit_out_dx_al
buf_emit 0xFF; buf_emit 0xC1
buf_emit 0x83; buf_emit 0xF9; buf_emit 11       # cmp ecx, 11
buf_emit 0x7C
buf_emit ([byte](($ls_ext_loop - (buf_len) - 1) -band 0xFF))
# Print file size from [r13+28..31] (4 bytes LE)
emit_call_puts_str "  "
buf_emit 0x41; buf_emit 0x8B; buf_emit 0x45; buf_emit 28  # mov eax, [r13+28]
emit_serial_hex_eax $COM1
emit_call_puts_str " bytes`r`n"

# ls_skip: (patch all near forward jumps here)
$ls_skip_off = buf_len
foreach ($p in @($je_ls_skip, $je_ls_skip2, $jnz_ls_skip3)) {
    $rel = $ls_skip_off - $p - 6
    $bytes_p = [System.BitConverter]::GetBytes([int32]$rel)
    buf_set ($p + 2) $bytes_p[0]; buf_set ($p + 3) $bytes_p[1]
    buf_set ($p + 4) $bytes_p[2]; buf_set ($p + 5) $bytes_p[3]
}
buf_emit 0x49; buf_emit 0x83; buf_emit 0xC5; buf_emit 32  # add r13, 32 (next entry)
buf_emit 0x41; buf_emit 0xFF; buf_emit 0xC4     # inc r12d
buf_emit 0x41; buf_emit 0x83; buf_emit 0xFC; buf_emit 16  # cmp r12d, 16
# jl ls_loop (NEAR backward jump)
buf_emit 0x0F; buf_emit 0x8C
buf_emit32_signed ($ls_loop - (buf_len) - 4)
# ls_end: (patch the jz near forward jump)
$ls_end_off = buf_len
$rel_le = $ls_end_off - $jz_ls_end - 6
$bytes_le = [System.BitConverter]::GetBytes([int32]$rel_le)
buf_set ($jz_ls_end + 2) $bytes_le[0]; buf_set ($jz_ls_end + 3) $bytes_le[1]
buf_set ($jz_ls_end + 4) $bytes_le[2]; buf_set ($jz_ls_end + 5) $bytes_le[3]
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: mkfile (mkfile FILENAME.EXT data...) ---
# Creates a file in the root directory with inline content.
emit_cmd_check "mkfile"
# `emit_cmd_check` performs an exact string match including the null terminator.
# `mkfile` accepts trailing arguments, so command recognition uses a dedicated
# prefix matcher for `mkfile ` instead of the exact-match helper above.
patch_cmd_skip

# --- Command: mkfile (prefix match) ---
# Check first 7 bytes: "mkfile " (with space)
emit_cmd_prefix_check "mkfile "

# Parse filename and payload from the command buffer.
# The current parser treats the first token after `mkfile ` as the 8.3 name and
# the remaining bytes as inline file data.

# Allocate dir entry in scratch at 0x511000 (32 bytes)
# Clear it
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x511000; buf_emit32 0
buf_emit 0x31; buf_emit 0xC0; buf_emit 0xB9; buf_emit32 8; emit_cld; buf_emit 0xF3; buf_emit 0xAB
# Fill name with spaces (0x20)
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x511000; buf_emit32 0
buf_emit 0xB0; buf_emit 0x20  # mov al, 0x20
buf_emit 0xB9; buf_emit32 11  # mov ecx, 11
buf_emit 0xF3; buf_emit 0xAA  # rep stosb (fill 11 bytes with space)

# Copy filename from cmd buffer [0x300807+] into dir entry name
# RSI = 0x300800 + 7 = 0x300807
buf_emit 0x48; buf_emit 0xBE; buf_emit32 0x300807; buf_emit32 0  # mov rsi, cmd+7
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x511000; buf_emit32 0  # mov rdi, entry name
buf_emit 0x31; buf_emit 0xC9  # xor ecx, ecx
$mkf_name_loop = buf_len
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x06      # movzx eax, byte [rsi]
buf_emit 0x3C; buf_emit 0x20                     # cmp al, ' '
$je_mkf_name_done = buf_len
buf_emit 0x74; buf_emit 0                        # je name_done (patched)
buf_emit 0x3C; buf_emit 0                        # cmp al, 0
$je_mkf_name_done2 = buf_len
buf_emit 0x74; buf_emit 0                        # je name_done (patched)
# Convert to uppercase: if al >= 'a' && al <= 'z', sub 32
buf_emit 0x3C; buf_emit 0x61                     # cmp al, 'a'
buf_emit 0x72; buf_emit 4                        # jb no_upper
buf_emit 0x3C; buf_emit 0x7A                     # cmp al, 'z'
buf_emit 0x77; buf_emit 2                        # ja no_upper
buf_emit 0x2C; buf_emit 32                       # sub al, 32
# no_upper:
buf_emit 0x88; buf_emit 0x07                     # mov [rdi], al
buf_emit 0x48; buf_emit 0xFF; buf_emit 0xC6      # inc rsi
buf_emit 0x48; buf_emit 0xFF; buf_emit 0xC7      # inc rdi
buf_emit 0xFF; buf_emit 0xC1                     # inc ecx
buf_emit 0x83; buf_emit 0xF9; buf_emit 11        # cmp ecx, 11
buf_emit 0x7C                                     # jl loop
buf_emit ([byte](($mkf_name_loop - (buf_len) - 1) -band 0xFF))
# name_done:
$mkf_name_done_off = buf_len
buf_set ($je_mkf_name_done + 1) ([byte](($mkf_name_done_off - $je_mkf_name_done - 2) -band 0xFF))
buf_set ($je_mkf_name_done2 + 1) ([byte](($mkf_name_done_off - $je_mkf_name_done2 - 2) -band 0xFF))

# Skip space between filename and data: advance rsi past space
buf_emit 0x80; buf_emit 0x3E; buf_emit 0x20      # cmp byte [rsi], ' '
buf_emit 0x75; buf_emit 3                        # jne no_skip
buf_emit 0x48; buf_emit 0xFF; buf_emit 0xC6      # inc rsi
# no_skip: RSI now points to data content

# Set dir entry attributes: [0x511000+11] = 0x20 (archive)
buf_emit 0xC6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x51100B; buf_emit 0x20

# Set starting cluster = 2 at [0x511000+26..27]
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x51101A; buf_emit16 2

# Compute data length: scan from RSI to null byte
buf_emit 0x48; buf_emit 0x89; buf_emit 0xF2      # mov rdx, rsi (save data start)
buf_emit 0x31; buf_emit 0xC9                     # xor ecx, ecx
$mkf_len_loop = buf_len
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x0E  # movzx eax, byte [rsi+rcx]
buf_emit 0x85; buf_emit 0xC0                     # test eax, eax
$jz_mkf_len_done = buf_len
buf_emit 0x74; buf_emit 0                        # jz (patched)
buf_emit 0xFF; buf_emit 0xC1                     # inc ecx
buf_emit 0xEB  # jmp loop
buf_emit ([byte](($mkf_len_loop - (buf_len) - 1) -band 0xFF))
$mkf_len_done_off = buf_len
buf_set ($jz_mkf_len_done + 1) ([byte](($mkf_len_done_off - $jz_mkf_len_done - 2) -band 0xFF))

# Set file size at [0x511000+28..31] = ecx
buf_emit 0x89; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x51101C

# Copy data content into cluster buffer at 0x510000 (max 512 bytes for now)
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x510000; buf_emit32 0  # mov rdi, 0x510000
# Clear buffer first
buf_emit 0x50; buf_emit 0x51  # push rax, rcx
buf_emit 0x31; buf_emit 0xC0; buf_emit 0xB9; buf_emit32 128; emit_cld; buf_emit 0xF3; buf_emit 0xAB
buf_emit 0x59; buf_emit 0x58  # pop rcx, rax
# Copy data
buf_emit 0x48; buf_emit 0x89; buf_emit 0xD6      # mov rsi, rdx (data start)
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x510000; buf_emit32 0
emit_cld; buf_emit 0xF3; buf_emit 0xA4           # rep movsb (ecx bytes)

# Write data to cluster 2 = sector 164
buf_emit 0x41; buf_emit 0xC7; buf_emit 0xC0; buf_emit32 164  # mov r8d, 164
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 1         # WRITE
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)

# Update FAT: entry 2 = 0xFFFF (end of chain)
# Read FAT1 first sector (sector 4)
buf_emit 0x41; buf_emit 0xB0; buf_emit 4
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 0         # READ
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)
# Set entry[2] = 0xFFFF (offset 4 in FAT sector, since each entry is 2 bytes)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x510004; buf_emit16 0xFFFF
# Write FAT back
buf_emit 0x41; buf_emit 0xB0; buf_emit 4
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 1
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)
# Also write to FAT2 (sector 68)
buf_emit 0x41; buf_emit 0xB0; buf_emit 68
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 1
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)

# Write dir entry to root dir (sector 132, first entry)
# Read root dir sector first
buf_emit 0x41; buf_emit 0xB0; buf_emit 132
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 0
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)
# Find first free entry (first byte == 0x00 or 0xE5)
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x510000; buf_emit32 0
buf_emit 0x31; buf_emit 0xC9  # xor ecx, ecx
$mkf_find_loop = buf_len
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x07     # movzx eax, byte [rdi]
buf_emit 0x85; buf_emit 0xC0                    # test eax, eax
$jz_mkf_found = buf_len
buf_emit 0x74; buf_emit 0                       # jz found (patched)
buf_emit 0x3C; buf_emit 0xE5
$je_mkf_found2 = buf_len
buf_emit 0x74; buf_emit 0                       # je found (patched)
buf_emit 0x48; buf_emit 0x83; buf_emit 0xC7; buf_emit 32  # add rdi, 32
buf_emit 0xFF; buf_emit 0xC1                    # inc ecx
buf_emit 0x83; buf_emit 0xF9; buf_emit 16
buf_emit 0x7C
buf_emit ([byte](($mkf_find_loop - (buf_len) - 1) -band 0xFF))
# No free entry found - just use first slot
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x510000; buf_emit32 0
$mkf_found_off = buf_len
buf_set ($jz_mkf_found + 1) ([byte](($mkf_found_off - $jz_mkf_found - 2) -band 0xFF))
buf_set ($je_mkf_found2 + 1) ([byte](($mkf_found_off - $je_mkf_found2 - 2) -band 0xFF))

# Copy 32-byte dir entry from 0x511000 to [rdi]
buf_emit 0x48; buf_emit 0xBE; buf_emit32 0x511000; buf_emit32 0  # mov rsi, entry
buf_emit 0xB9; buf_emit32 32  # mov ecx, 32
emit_cld; buf_emit 0xF3; buf_emit 0xA4  # rep movsb

# Write root dir sector back
buf_emit 0x41; buf_emit 0xB0; buf_emit 132
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 1
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)

emit_call_puts_str "File created.`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: cat (prefix match: "cat ") ---
emit_cmd_prefix_check "cat "

# Read root dir sector 132
buf_emit 0x41; buf_emit 0xB0; buf_emit 132
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 0
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)

# Build search name at 0x511000 (11 bytes, space-padded, uppercase)
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x511000; buf_emit32 0
buf_emit 0xB0; buf_emit 0x20; buf_emit 0xB9; buf_emit32 11; emit_cld; buf_emit 0xF3; buf_emit 0xAA
buf_emit 0x48; buf_emit 0xBE; buf_emit32 0x300804; buf_emit32 0  # "cat " -> name at offset 4
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x511000; buf_emit32 0
buf_emit 0x31; buf_emit 0xC9
$cat_bld_loop = buf_len
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x06
buf_emit 0x3C; buf_emit 0x20
$je_cat_bld_done = buf_len
buf_emit 0x74; buf_emit 0
buf_emit 0x3C; buf_emit 0
$je_cat_bld_done2 = buf_len
buf_emit 0x74; buf_emit 0
buf_emit 0x3C; buf_emit 0x61; buf_emit 0x72; buf_emit 4; buf_emit 0x3C; buf_emit 0x7A; buf_emit 0x77; buf_emit 2; buf_emit 0x2C; buf_emit 32
buf_emit 0x88; buf_emit 0x07
buf_emit 0x48; buf_emit 0xFF; buf_emit 0xC6; buf_emit 0x48; buf_emit 0xFF; buf_emit 0xC7
buf_emit 0xFF; buf_emit 0xC1; buf_emit 0x83; buf_emit 0xF9; buf_emit 11; buf_emit 0x7C
buf_emit ([byte](($cat_bld_loop - (buf_len) - 1) -band 0xFF))
$cat_bld_done_off = buf_len
buf_set ($je_cat_bld_done + 1) ([byte](($cat_bld_done_off - $je_cat_bld_done - 2) -band 0xFF))
buf_set ($je_cat_bld_done2 + 1) ([byte](($cat_bld_done_off - $je_cat_bld_done2 - 2) -band 0xFF))

# Search dir entries: compare 11 bytes at [entry+0] with [0x511000]
buf_emit 0x48; buf_emit 0xBF; buf_emit32 0x510000; buf_emit32 0  # rdi = dir sector
buf_emit 0x31; buf_emit 0xC9  # ecx = 0 (entry index)
$cat_search = buf_len
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x07     # movzx eax, byte [rdi]
buf_emit 0x85; buf_emit 0xC0
$jz_cat_notfound = buf_len
buf_emit 0x74; buf_emit 0                       # jz not found
# Compare 11 bytes
buf_emit 0x51; buf_emit 0x57                    # push rcx, rdi
buf_emit 0x48; buf_emit 0xBE; buf_emit32 0x511000; buf_emit32 0  # rsi = search name
buf_emit 0xB9; buf_emit32 11; emit_cld; buf_emit 0xF3; buf_emit 0xA6  # repe cmpsb
buf_emit 0x5F; buf_emit 0x59                    # pop rdi, rcx
$je_cat_found = buf_len
buf_emit 0x74; buf_emit 0                       # je found (patched)
buf_emit 0x48; buf_emit 0x83; buf_emit 0xC7; buf_emit 32  # add rdi, 32
buf_emit 0xFF; buf_emit 0xC1; buf_emit 0x83; buf_emit 0xF9; buf_emit 16
buf_emit 0x7C
buf_emit ([byte](($cat_search - (buf_len) - 1) -band 0xFF))
# Not found:
$cat_notfound_off = buf_len
buf_set ($jz_cat_notfound + 1) ([byte](($cat_notfound_off - $jz_cat_notfound - 2) -band 0xFF))
emit_call_puts_str "File not found.`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)

# Found: rdi points to dir entry
$cat_found_off = buf_len
buf_set ($je_cat_found + 1) ([byte](($cat_found_off - $je_cat_found - 2) -band 0xFF))
# Get starting cluster from [rdi+26..27]
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 26  # movzx eax, word [rdi+26]
# Get file size from [rdi+28..31]
buf_emit 0x8B; buf_emit 0x4F; buf_emit 28       # mov ecx, [rdi+28] (file size)
buf_emit 0x89; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x511020  # save size at 0x511020
# Compute sector = 164 + (cluster - 2) * 4
buf_emit 0x83; buf_emit 0xE8; buf_emit 2        # sub eax, 2
buf_emit 0xC1; buf_emit 0xE0; buf_emit 2        # shl eax, 2 (×4 sectors/cluster)
buf_emit 0x05; buf_emit32 164                   # add eax, 164
buf_emit 0x41; buf_emit 0x89; buf_emit 0xC0     # mov r8d, eax (sector)
# Read data sector
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000
buf_emit 0x41; buf_emit 0xB2; buf_emit 0        # READ
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)
# Print file contents (ecx bytes from 0x510000)
buf_emit 0x8B; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x511020  # reload size
buf_emit 0x48; buf_emit 0xBE; buf_emit32 0x510000; buf_emit32 0
$cat_print = buf_len
buf_emit 0x85; buf_emit 0xC9                    # test ecx, ecx
$jz_cat_print_done = buf_len
buf_emit 0x74; buf_emit 0
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x1E     # movzx ebx, byte [rsi]
buf_emit 0x51  # push rcx
emit_mov_edx_imm32 ($COM1 + 5); emit_in_al_dx; emit_test_al_imm8 0x20
buf_emit 0x74; buf_emit 0xF6
buf_emit 0x88; buf_emit 0xD8                    # mov al, bl
emit_mov_edx_imm32 $COM1; emit_out_dx_al
buf_emit 0x59  # pop rcx
buf_emit 0x48; buf_emit 0xFF; buf_emit 0xC6     # inc rsi
buf_emit 0xFF; buf_emit 0xC9                    # dec ecx
buf_emit 0xEB
buf_emit ([byte](($cat_print - (buf_len) - 1) -band 0xFF))
$cat_print_done_off = buf_len
buf_set ($jz_cat_print_done + 1) ([byte](($cat_print_done_off - $jz_cat_print_done - 2) -band 0xFF))
emit_call_puts_str "`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# =============================================================
# Network Commands (dhcp, ping, ifconfig)
# =============================================================

# --- Command: ifconfig ---
emit_cmd_check "ifconfig"
emit_call_puts_str "eth0: VirtIO-net MAC=52:54:00:12:34:56`r`n      "
# Print IP if set, else "no IP"
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002A8  # mov eax, [our_ip]
buf_emit 0x85; buf_emit 0xC0  # test eax, eax
$jnz_has_ip = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # jnz has_ip
emit_call_puts_str "inet: (no IP - run dhcp)`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
$has_ip_off = buf_len
$rel_hi = $has_ip_off - $jnz_has_ip - 6
$b_hi = [System.BitConverter]::GetBytes([int32]$rel_hi)
buf_set ($jnz_has_ip + 2) $b_hi[0]; buf_set ($jnz_has_ip + 3) $b_hi[1]
buf_set ($jnz_has_ip + 4) $b_hi[2]; buf_set ($jnz_has_ip + 5) $b_hi[3]
# Print IP as dotted decimal (4 octets from [0x3002A8])
emit_call_puts_str "inet: "
for ($oct = 0; $oct -lt 4; $oct++) {
    if ($oct -gt 0) { emit_call_puts_str "." }
    emit_serial_dec_byte_from_abs32 (0x3002A8 + $oct) $COM1
}
emit_call_puts_str "`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: dhcp ---
emit_cmd_check "dhcp"
emit_call_puts_str "DHCP Discover...`r`n"

# Build DHCP Discover packet at 0x630000
# Ethernet: dst=FF:FF:FF:FF:FF:FF, src=52:54:00:12:34:56, type=0x0800 (IP)
buf_emit 0xBF; buf_emit32 0x630000
# dst MAC broadcast
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0xFFFFFFFF
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit16 0xFFFF
# src MAC
buf_emit 0xC7; buf_emit 0x47; buf_emit 6; buf_emit32 0x12005452
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 10; buf_emit16 0x5634
# EtherType: 0x0800 (IPv4)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit16 0x0008

# IPv4 header at offset 14 (20 bytes, no options)
# version=4, IHL=5, TOS=0, total_len=328 (20+8+300)
buf_emit 0xC6; buf_emit 0x47; buf_emit 14; buf_emit 0x45  # ver+IHL
buf_emit 0xC6; buf_emit 0x47; buf_emit 15; buf_emit 0     # TOS
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 16; buf_emit16 0x4801  # total_len=328 BE=0x0148
# ID=0, flags=0, frag=0
buf_emit 0xC7; buf_emit 0x47; buf_emit 18; buf_emit32 0   # ID+flags+frag
# TTL=64, protocol=17(UDP), IP checksum precomputed for 0.0.0.0→255.255.255.255
buf_emit 0xC6; buf_emit 0x47; buf_emit 22; buf_emit 64    # TTL
buf_emit 0xC6; buf_emit 0x47; buf_emit 23; buf_emit 17    # UDP
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 24; buf_emit16 0xA679  # checksum=0x79A6 BE
# src IP: 0.0.0.0
buf_emit 0xC7; buf_emit 0x47; buf_emit 26; buf_emit32 0
# dst IP: 255.255.255.255
buf_emit 0xC7; buf_emit 0x47; buf_emit 30; buf_emit32 0xFFFFFFFF

# UDP header at offset 34 (8 bytes)
# src port=68 (DHCP client), dst port=67 (DHCP server)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 34; buf_emit16 0x4400  # port 68 BE
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 36; buf_emit16 0x4300  # port 67 BE
# length=308 (8+300), checksum=0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 38; buf_emit16 0x3401  # 308 BE=0x0134
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 40; buf_emit16 0      # checksum=0

# DHCP payload at offset 42 (300 bytes)
# First zero the DHCP area (300 bytes = 75 dwords)
buf_emit 0x48; buf_emit 0x8D; buf_emit 0x7F; buf_emit 42  # lea rdi, [rdi+42]
buf_emit 0x31; buf_emit 0xC0; buf_emit 0xB9; buf_emit32 75; emit_cld; buf_emit 0xF3; buf_emit 0xAB
buf_emit 0xBF; buf_emit32 0x630000  # reload base

# op=1(BOOTREQUEST), htype=1(Ethernet), hlen=6, hops=0
buf_emit 0xC7; buf_emit 0x47; buf_emit 42; buf_emit32 0x00060101  # 01 01 06 00 LE
# xid=0x12345678 (transaction ID)
buf_emit 0xC7; buf_emit 0x47; buf_emit 46; buf_emit32 0x78563412
# flags=0x8000 (broadcast)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 52; buf_emit16 0x0080  # 80 00 BE
# chaddr (client MAC) at offset 42+28 = 70
buf_emit 0xC7; buf_emit 0x47; buf_emit 70; buf_emit32 0x12005452
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 74; buf_emit16 0x5634
# Magic cookie at offset 42+236 = 278: 99.130.83.99 = 0x63825363 (mod=10 disp32)
buf_emit 0xC7; buf_emit 0x87; buf_emit32 278; buf_emit32 0x63538263
# DHCP options at 42+240 = 282:
# 35 01 01 FF = opt53(Discover) + END
buf_emit 0xC6; buf_emit 0x87; buf_emit32 282; buf_emit 53  # option 53
buf_emit 0xC6; buf_emit 0x87; buf_emit32 283; buf_emit 1   # length 1
buf_emit 0xC6; buf_emit 0x87; buf_emit32 284; buf_emit 1   # DISCOVER
buf_emit 0xC6; buf_emit 0x87; buf_emit32 285; buf_emit 255 # END

# Send DHCP Discover: total = 14 (eth) + 20 (ip) + 8 (udp) + 300 (dhcp) = 342 bytes
buf_emit 0x41; buf_emit 0xC7; buf_emit 0xC0; buf_emit32 342  # mov r8d, 342
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x630000  # mov r9, packet
buf_emit 0xE8; buf_emit32_signed ($net_send_off - (buf_len) - 4)

emit_call_puts_str "Waiting for DHCP Offer...`r`n"

# Poll for DHCP reply (up to 3 seconds = 300 ticks at 100Hz)
buf_emit 0xB9; buf_emit32 300  # timeout counter
$dhcp_poll_loop = buf_len
buf_emit 0x51  # push rcx

# Inline RX check: compute RX used_base, check used->idx
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xD1; buf_emit 0xE0; buf_emit 0x83; buf_emit 0xC0; buf_emit 6
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xC1; buf_emit 0xE7; buf_emit 4
buf_emit 0x81; buf_emit 0xC7; buf_emit32 0x600000
buf_emit 0x01; buf_emit 0xF8; buf_emit 0x05; buf_emit32 0xFFF
buf_emit 0x25; buf_emit32 0xFFFFF000
buf_emit 0x89; buf_emit 0xC7  # edi = used_base
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 2  # eax = used->idx
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0
buf_emit 0x39; buf_emit 0xC8  # cmp eax, ecx
$jle_no_pkt = buf_len
buf_emit 0x0F; buf_emit 0x8E; buf_emit32 0  # jle no_packet (near)

# Got a packet! Check EtherType at offset 10+12=22 from buffer base
# First: determine which buffer was used. Read used ring entry for last_rx_used.
# used entry = used_base + 4 + (last_rx_used % qsize) * 8 → gives (desc_id, len)
buf_emit 0x89; buf_emit 0xC8  # mov eax, ecx (last_rx_used)
buf_emit 0x8B; buf_emit 0x14; buf_emit 0x25; buf_emit32 0x300288  # rx_qsize
buf_emit 0xFF; buf_emit 0xCA; buf_emit 0x21; buf_emit 0xD0  # dec edx; and eax, edx
buf_emit 0xC1; buf_emit 0xE0; buf_emit 3; buf_emit 0x83; buf_emit 0xC0; buf_emit 4  # *8+4
# desc_id = dword [edi+eax]
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x07  # mov eax, [rdi+rax] = desc_id
# Buffer addr = 0x620000 + desc_id * 2048
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11  # shl eax, 11 (* 2048)
buf_emit 0x05; buf_emit32 0x620000  # add 0x620000
buf_emit 0x89; buf_emit 0xC6  # mov esi, eax (buffer addr)

# Check EtherType at [esi+22]: should be 08 00 = IP (BE: stored as 00 08 in LE)
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x46; buf_emit 22  # movzx eax, word [rsi+22]
buf_emit 0x3D; buf_emit32 0x0008  # cmp eax, 0x0008 (IP in LE)
$jne_skip_pkt = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # jne skip (not IP, discard)

# It's an IP packet! Check it's UDP(17) at IP protocol offset [esi+33]
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x46; buf_emit 33  # movzx eax, byte [rsi+33]
buf_emit 0x3C; buf_emit 17  # cmp al, 17 (UDP)
$jne_skip_pkt2 = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0  # jne skip (not UDP)

# It's UDP! This should be the DHCP Offer. Extract yiaddr.
# DHCP yiaddr at [esi + 10 + 14 + 20 + 8 + 16] = [esi + 68]
buf_emit 0x8B; buf_emit 0x46; buf_emit 68  # mov eax, [rsi+68]
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002A8  # store IP

# Advance last_rx_used
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0
buf_emit 0xFF; buf_emit 0xC1
buf_emit 0x66; buf_emit 0x89; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0

buf_emit 0x59  # pop rcx
$jmp_dhcp_got = buf_len
buf_emit 0xE9; buf_emit32 0  # jmp got_reply (patched)

# skip_pkt: discard non-IP/non-UDP packet, advance last_rx_used, continue
$skip_pkt_off = buf_len
foreach ($p in @($jne_skip_pkt, $jne_skip_pkt2)) {
    $rel = $skip_pkt_off - $p - 6
    $b = [System.BitConverter]::GetBytes([int32]$rel)
    buf_set ($p + 2) $b[0]; buf_set ($p + 3) $b[1]; buf_set ($p + 4) $b[2]; buf_set ($p + 5) $b[3]
}
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0
buf_emit 0xFF; buf_emit 0xC1
buf_emit 0x66; buf_emit 0x89; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0

# no_packet: (also target for jle when no packet available)
$no_pkt_off = buf_len
$rel_np = $no_pkt_off - $jle_no_pkt - 6
$b_np = [System.BitConverter]::GetBytes([int32]$rel_np)
buf_set ($jle_no_pkt + 2) $b_np[0]; buf_set ($jle_no_pkt + 3) $b_np[1]
buf_set ($jle_no_pkt + 4) $b_np[2]; buf_set ($jle_no_pkt + 5) $b_np[3]

buf_emit 0x59  # pop rcx
emit_hlt
buf_emit 0xFF; buf_emit 0xC9  # dec ecx
buf_emit 0x0F; buf_emit 0x85
buf_emit32_signed ($dhcp_poll_loop - (buf_len) - 4)
# Timeout
emit_call_puts_str "DHCP timeout`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)

# got_reply: IP is already stored at [0x3002A8] by poll loop
$dhcp_got_off = buf_len
# Patch the jmp from poll loop
$rel_dg = $dhcp_got_off - $jmp_dhcp_got - 5
$b_dg = [System.BitConverter]::GetBytes([int32]$rel_dg)
buf_set ($jmp_dhcp_got + 1) $b_dg[0]; buf_set ($jmp_dhcp_got + 2) $b_dg[1]
buf_set ($jmp_dhcp_got + 3) $b_dg[2]; buf_set ($jmp_dhcp_got + 4) $b_dg[3]

emit_call_puts_str "DHCP: IP acquired "
# Print IP octets
for ($oct = 0; $oct -lt 4; $oct++) {
    if ($oct -gt 0) { emit_call_puts_str "." }
    emit_serial_dec_byte_from_abs32 (0x3002A8 + $oct) $COM1
}
emit_call_puts_str " (simplified, single offer)`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: ping ---
# Send ICMP Echo Request to 10.0.2.2 (QEMU gateway), wait for reply
emit_cmd_check "ping"

# Check if we have an IP
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002A8
buf_emit 0x85; buf_emit 0xC0
$jnz_ping_has_ip = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0
emit_call_puts_str "No IP. Run 'dhcp' first.`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
$ping_ip_off = buf_len
$rel_pi = $ping_ip_off - $jnz_ping_has_ip - 6
$b_pi = [System.BitConverter]::GetBytes([int32]$rel_pi)
buf_set ($jnz_ping_has_ip + 2) $b_pi[0]; buf_set ($jnz_ping_has_ip + 3) $b_pi[1]
buf_set ($jnz_ping_has_ip + 4) $b_pi[2]; buf_set ($jnz_ping_has_ip + 5) $b_pi[3]

emit_call_puts_str "PING 10.0.2.2: "

# First: send ARP request to refresh SLIRP's ARP table (same format as boot ARP)
buf_emit 0xBF; buf_emit32 0x630000
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0xFFFFFFFF
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit16 0xFFFF
buf_emit 0xC7; buf_emit 0x47; buf_emit 6; buf_emit32 0x12005452
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 10; buf_emit16 0x5634
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit16 0x0608
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 14; buf_emit16 0x0100
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 16; buf_emit16 0x0008
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 18; buf_emit16 0x0406
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 20; buf_emit16 0x0100  # OPER=1 request
buf_emit 0xC7; buf_emit 0x47; buf_emit 22; buf_emit32 0x12005452
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 26; buf_emit16 0x5634
# SPA = our IP from DHCP
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002A8
buf_emit 0x89; buf_emit 0x47; buf_emit 28
buf_emit 0xC7; buf_emit 0x47; buf_emit 32; buf_emit32 0x00000000
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 36; buf_emit16 0x0000
buf_emit 0xC7; buf_emit 0x47; buf_emit 38; buf_emit32 0x0202000A  # TPA=10.0.2.2
buf_emit 0x41; buf_emit 0xC7; buf_emit 0xC0; buf_emit32 42
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x630000
buf_emit 0xE8; buf_emit32_signed ($net_send_off - (buf_len) - 4)
# Wait 500ms for ARP reply to arrive
buf_emit 0xB9; buf_emit32 50
$arp_wait = buf_len
emit_hlt; buf_emit 0xFF; buf_emit 0xC9
buf_emit 0x75; buf_emit ([byte](($arp_wait - (buf_len) - 1) -band 0xFF))

# Build ICMP packet using memcpy from template + patch src IP + IP checksum
# Store 74-byte ICMP template at 0x630100 (static area, built once)
buf_emit 0x53  # push rbx (save)
buf_emit 0xBF; buf_emit32 0x630100  # template at 0x630100

# Ethernet dst: SLIRP gateway 52:55:0A:00:02:02
buf_emit 0xC7; buf_emit 0x07; buf_emit32 0x000A5552
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 4; buf_emit16 0x0202
# Ethernet src: 52:54:00:12:34:56
buf_emit 0xC7; buf_emit 0x47; buf_emit 6; buf_emit32 0x12005452
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 10; buf_emit16 0x5634
# EtherType: 0x0800 (IPv4)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 12; buf_emit16 0x0008
# IP header: 45 00 00 3C 00 00 00 00 40 01 [cksum] [src] 0A 00 02 02
buf_emit 0xC6; buf_emit 0x47; buf_emit 14; buf_emit 0x45
buf_emit 0xC6; buf_emit 0x47; buf_emit 15; buf_emit 0
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 16; buf_emit16 0x3C00
buf_emit 0xC7; buf_emit 0x47; buf_emit 18; buf_emit32 0
buf_emit 0xC6; buf_emit 0x47; buf_emit 22; buf_emit 64
buf_emit 0xC6; buf_emit 0x47; buf_emit 23; buf_emit 1
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 24; buf_emit16 0  # checksum=0 initially
# src IP from DHCP
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002A8
buf_emit 0x89; buf_emit 0x47; buf_emit 26
# dst IP: 10.0.2.2
buf_emit 0xC7; buf_emit 0x47; buf_emit 30; buf_emit32 0x0202000A

# ICMP: type=8, code=0, cksum=E6F0(BE), id=1234, seq=1
buf_emit 0xC7; buf_emit 0x47; buf_emit 34; buf_emit32 0xF0E60008  # 08 00 E6 F0
buf_emit 0xC7; buf_emit 0x47; buf_emit 38; buf_emit32 0x01003412  # bytes: 12 34 00 01
# Data: "HicOS!" + zeros
buf_emit 0xC7; buf_emit 0x47; buf_emit 42; buf_emit32 0x4F636948  # bytes: 48 69 63 4F = "HicO"
buf_emit 0xC7; buf_emit 0x47; buf_emit 46; buf_emit32 0x00002153
# bytes 50-73 = 0 (24 bytes)
buf_emit 0xC7; buf_emit 0x47; buf_emit 50; buf_emit32 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 54; buf_emit32 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 58; buf_emit32 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 62; buf_emit32 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 66; buf_emit32 0
buf_emit 0xC7; buf_emit 0x47; buf_emit 70; buf_emit32 0

# Compute IP checksum: sum 10 words at [rdi+14..33], fold, complement
buf_emit 0x31; buf_emit 0xDB  # xor ebx, ebx (sum)
for ($w = 0; $w -lt 10; $w++) {
    $off = 14 + $w * 2
    # movzx eax, word [rdi+off]
    buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit ([byte]$off)
    buf_emit 0x01; buf_emit 0xC3  # add ebx, eax
}
# Fold carry
buf_emit 0x89; buf_emit 0xD8  # mov eax, ebx
buf_emit 0xC1; buf_emit 0xE8; buf_emit 16  # shr eax, 16
buf_emit 0x01; buf_emit 0xC3  # add ebx, eax
buf_emit 0x89; buf_emit 0xD8; buf_emit 0xC1; buf_emit 0xE8; buf_emit 16; buf_emit 0x01; buf_emit 0xC3
buf_emit 0xF7; buf_emit 0xD3  # not ebx
buf_emit 0x66; buf_emit 0x89; buf_emit 0x5F; buf_emit 24  # mov [rdi+24], bx

# Copy 74 bytes from template (0x630100) to TX buffer (0x630000)
buf_emit 0xBE; buf_emit32 0x630100  # mov esi, 0x630100
buf_emit 0xBF; buf_emit32 0x630000  # mov edi, 0x630000
buf_emit 0xB9; buf_emit32 74
emit_cld; buf_emit 0xF3; buf_emit 0xA4  # rep movsb

buf_emit 0x5B  # pop rbx

# Send: 74 bytes from 0x630000
buf_emit 0x41; buf_emit 0xC7; buf_emit 0xC0; buf_emit32 74
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x630000
buf_emit 0xE8; buf_emit32_signed ($net_send_off - (buf_len) - 4)

# Poll for ICMP Echo Reply
buf_emit 0xB9; buf_emit32 300
$ping_poll = buf_len
buf_emit 0x51  # push rcx
# Compute RX used_base
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xD1; buf_emit 0xE0; buf_emit 0x83; buf_emit 0xC0; buf_emit 6
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xC1; buf_emit 0xE7; buf_emit 4
buf_emit 0x81; buf_emit 0xC7; buf_emit32 0x600000
buf_emit 0x01; buf_emit 0xF8; buf_emit 0x05; buf_emit32 0xFFF
buf_emit 0x25; buf_emit32 0xFFFFF000
buf_emit 0x89; buf_emit 0xC7
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 2  # used->idx
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0
buf_emit 0x39; buf_emit 0xC8
$jle_ping_no = buf_len
buf_emit 0x0F; buf_emit 0x8E; buf_emit32 0  # jle no_packet

# Got packet - check if ICMP reply (EtherType=IP, Protocol=ICMP)
# Determine buffer addr from desc_id in used ring
buf_emit 0x89; buf_emit 0xC8  # mov eax, ecx (last_rx_used)
buf_emit 0x8B; buf_emit 0x14; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xFF; buf_emit 0xCA; buf_emit 0x21; buf_emit 0xD0
buf_emit 0xC1; buf_emit 0xE0; buf_emit 3; buf_emit 0x83; buf_emit 0xC0; buf_emit 4
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x07  # desc_id
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11; buf_emit 0x05; buf_emit32 0x620000
buf_emit 0x89; buf_emit 0xC6  # esi = buffer

# Advance last_rx_used unconditionally (consume the packet)
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0
buf_emit 0xFF; buf_emit 0xC1
buf_emit 0x66; buf_emit 0x89; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0

# Check EtherType at [esi+22] == 0x0008 (IP) AND Protocol at [esi+33] == 1 (ICMP)
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x46; buf_emit 22  # EtherType
buf_emit 0x3D; buf_emit32 0x0008
$jne_ping_skip = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x46; buf_emit 33  # IP protocol
buf_emit 0x3C; buf_emit 1  # ICMP
$jne_ping_skip2 = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0

# It's an ICMP packet - accept it as reply
buf_emit 0x59  # pop rcx
$jmp_ping_got = buf_len
buf_emit 0xE9; buf_emit32 0  # jmp ping_got (patched)

# skip/no_packet:
$ping_skip_off = buf_len
foreach ($p in @($jne_ping_skip, $jne_ping_skip2)) {
    $rel = $ping_skip_off - $p - 6
    $b = [System.BitConverter]::GetBytes([int32]$rel)
    buf_set ($p + 2) $b[0]; buf_set ($p + 3) $b[1]; buf_set ($p + 4) $b[2]; buf_set ($p + 5) $b[3]
}
$ping_no_off = buf_len
$rel_pn = $ping_no_off - $jle_ping_no - 6
$b_pn = [System.BitConverter]::GetBytes([int32]$rel_pn)
buf_set ($jle_ping_no + 2) $b_pn[0]; buf_set ($jle_ping_no + 3) $b_pn[1]
buf_set ($jle_ping_no + 4) $b_pn[2]; buf_set ($jle_ping_no + 5) $b_pn[3]
buf_emit 0x59  # pop rcx
emit_hlt
buf_emit 0xFF; buf_emit 0xC9
buf_emit 0x0F; buf_emit 0x85
buf_emit32_signed ($ping_poll - (buf_len) - 4)
emit_call_puts_str "timeout`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)

$ping_got_off = buf_len
$rel_pg2 = $ping_got_off - $jmp_ping_got - 5
$b_pg2 = [System.BitConverter]::GetBytes([int32]$rel_pg2)
buf_set ($jmp_ping_got + 1) $b_pg2[0]; buf_set ($jmp_ping_got + 2) $b_pg2[1]
buf_set ($jmp_ping_got + 3) $b_pg2[2]; buf_set ($jmp_ping_got + 4) $b_pg2[3]

emit_call_puts_str "reply received`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: nslookup ---
# DNS A-record query for "example.com" via QEMU SLIRP DNS (10.0.2.3:53)
emit_cmd_check "nslookup"

# Check IP
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002A8
buf_emit 0x85; buf_emit 0xC0
$jnz_dns_ip = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0
emit_call_puts_str "No IP. Run 'dhcp' first.`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
$dns_ip_off = buf_len
$rel_di = $dns_ip_off - $jnz_dns_ip - 6
$b_di = [System.BitConverter]::GetBytes([int32]$rel_di)
buf_set ($jnz_dns_ip + 2) $b_di[0]; buf_set ($jnz_dns_ip + 3) $b_di[1]
buf_set ($jnz_dns_ip + 4) $b_di[2]; buf_set ($jnz_dns_ip + 5) $b_di[3]

emit_call_puts_str "Querying example.com...`r`n"

# Build DNS query packet at 0x630100
# DNS query for "example.com" A record:
#   Header (12B): ID=0xABCD, flags=0x0100(std query,RD), QDCOUNT=1
#   Question: 07"example"03"com"00 + QTYPE=1(A) + QCLASS=1(IN)
#   Question = 13 + 4 = 17 bytes
#   Total DNS = 12 + 17 = 29 bytes
#   UDP = 8 + 29 = 37 bytes
#   IP = 20 + 37 = 57 bytes
#   Eth = 14 + 57 = 71 bytes (pad to 74 for safety)

# Precompute all 71 raw bytes in PowerShell
$dnsPkt = [byte[]]::new(74)  # zero-padded to 74

# Ethernet dst: gateway MAC 52:55:0A:00:02:02 (SLIRP routes to DNS)
$dnsPkt[0]=0x52;$dnsPkt[1]=0x55;$dnsPkt[2]=0x0A;$dnsPkt[3]=0x00;$dnsPkt[4]=0x02;$dnsPkt[5]=0x02
# Ethernet src: 52:54:00:12:34:56
$dnsPkt[6]=0x52;$dnsPkt[7]=0x54;$dnsPkt[8]=0x00;$dnsPkt[9]=0x12;$dnsPkt[10]=0x34;$dnsPkt[11]=0x56
# EtherType: 0x0800 (IPv4)
$dnsPkt[12]=0x08;$dnsPkt[13]=0x00

# IPv4 header (20 bytes) at offset 14
$dnsPkt[14]=0x45;$dnsPkt[15]=0x00  # ver+IHL, TOS
$dnsPkt[16]=0x00;$dnsPkt[17]=57    # total_len=57 (BE)
# ID=0, flags=0, frag=0 → bytes 18-21 = 0 (already zero)
$dnsPkt[22]=64;$dnsPkt[23]=17     # TTL=64, protocol=17(UDP)
# checksum at 24-25 = 0 (compute later)
# src IP at 26-29 = patched at runtime
# dst IP = 10.0.2.3 (SLIRP DNS)
$dnsPkt[30]=0x0A;$dnsPkt[31]=0x00;$dnsPkt[32]=0x02;$dnsPkt[33]=0x03

# UDP header (8 bytes) at offset 34
$dnsPkt[34]=0x10;$dnsPkt[35]=0x00  # src port 4096 (BE)
$dnsPkt[36]=0x00;$dnsPkt[37]=53    # dst port 53 (BE)
$dnsPkt[38]=0x00;$dnsPkt[39]=37    # UDP length=37 (BE)
# UDP checksum = 0 (optional for IPv4)

# DNS header (12 bytes) at offset 42
$dnsPkt[42]=0xAB;$dnsPkt[43]=0xCD  # ID=0xABCD
$dnsPkt[44]=0x01;$dnsPkt[45]=0x00  # flags=0x0100 (std query, RD=1)
$dnsPkt[46]=0x00;$dnsPkt[47]=0x01  # QDCOUNT=1
# ANCOUNT/NSCOUNT/ARCOUNT = 0 (already zero)

# DNS Question at offset 54: 07 "example" 03 "com" 00 + type + class
$dnsPkt[54]=7  # length of "example"
$exBytes = [System.Text.Encoding]::ASCII.GetBytes("example")
for ($i=0;$i-lt 7;$i++) { $dnsPkt[55+$i] = $exBytes[$i] }
$dnsPkt[62]=3  # length of "com"
$comBytes = [System.Text.Encoding]::ASCII.GetBytes("com")
for ($i=0;$i-lt 3;$i++) { $dnsPkt[63+$i] = $comBytes[$i] }
$dnsPkt[66]=0  # root label terminator
$dnsPkt[67]=0x00;$dnsPkt[68]=0x01  # QTYPE=1 (A)
$dnsPkt[69]=0x00;$dnsPkt[70]=0x01  # QCLASS=1 (IN)

# Now compute IP checksum (over bytes 14-33, with src=0.0.0.0 placeholder)
# We'll patch src IP at runtime, so precompute partial checksum without src IP
# Actually, store the template and patch src IP + recompute checksum at runtime

# Store 74-byte template at 0x630200 using mov dword instructions
buf_emit 0xBF; buf_emit32 0x630200
for ($i = 0; $i -lt 74; $i += 4) {
    $dw = [uint32]0
    for ($j = 0; $j -lt 4 -and ($i+$j) -lt 74; $j++) {
        $dw = $dw -bor ([uint32]$dnsPkt[$i+$j] -shl ($j * 8))
    }
    $intVal = [System.BitConverter]::ToInt32([System.BitConverter]::GetBytes($dw), 0)
    if ($i -lt 128) {
        buf_emit 0xC7; buf_emit 0x47; buf_emit ([byte]$i); buf_emit32 $intVal
    }
}

# Patch src IP from [0x3002A8] into template at offset 26
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002A8  # mov eax, [our_ip]
buf_emit 0xC7; buf_emit 0xC7; buf_emit32 0x630200  # mov edi, 0x630200 (reload)
buf_emit 0x89; buf_emit 0x47; buf_emit 26  # mov [rdi+26], eax (src IP)

# Compute IP checksum: unrolled sum of 10 words at [rdi+14..33]
buf_emit 0x31; buf_emit 0xDB  # xor ebx, ebx
for ($w = 0; $w -lt 10; $w++) {
    $off = 14 + $w * 2
    buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit ([byte]$off)  # movzx eax, word [rdi+off]
    buf_emit 0x01; buf_emit 0xC3  # add ebx, eax
}
buf_emit 0x89; buf_emit 0xD8  # mov eax, ebx
buf_emit 0xC1; buf_emit 0xE8; buf_emit 16  # shr eax, 16
buf_emit 0x01; buf_emit 0xC3  # add ebx, eax
buf_emit 0x89; buf_emit 0xD8; buf_emit 0xC1; buf_emit 0xE8; buf_emit 16; buf_emit 0x01; buf_emit 0xC3
buf_emit 0xF7; buf_emit 0xD3  # not ebx
buf_emit 0x66; buf_emit 0x89; buf_emit 0x5F; buf_emit 24  # mov [rdi+24], bx (IP checksum)

# Copy template to TX buffer 0x630000
buf_emit 0xBE; buf_emit32 0x630200  # mov esi, src
buf_emit 0xBF; buf_emit32 0x630000  # mov edi, dst
buf_emit 0xB9; buf_emit32 74
emit_cld; buf_emit 0xF3; buf_emit 0xA4  # rep movsb

# Send DNS query (71 bytes, padded to 74)
buf_emit 0x41; buf_emit 0xC7; buf_emit 0xC0; buf_emit32 71  # r8d = packet len
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x630000  # r9 = buffer
buf_emit 0xE8; buf_emit32_signed ($net_send_off - (buf_len) - 4)

# Poll for DNS reply (up to 3 seconds)
buf_emit 0xB9; buf_emit32 300
$dns_poll = buf_len
buf_emit 0x51  # push rcx
# Inline RX check
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xD1; buf_emit 0xE0; buf_emit 0x83; buf_emit 0xC0; buf_emit 6
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xC1; buf_emit 0xE7; buf_emit 4
buf_emit 0x81; buf_emit 0xC7; buf_emit32 0x600000
buf_emit 0x01; buf_emit 0xF8; buf_emit 0x05; buf_emit32 0xFFF
buf_emit 0x25; buf_emit32 0xFFFFF000
buf_emit 0x89; buf_emit 0xC7
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x47; buf_emit 2  # used->idx
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0
buf_emit 0x39; buf_emit 0xC8
$jle_dns_no = buf_len
buf_emit 0x0F; buf_emit 0x8E; buf_emit32 0

# Got packet - find buffer, check if UDP reply
buf_emit 0x89; buf_emit 0xC8
buf_emit 0x8B; buf_emit 0x14; buf_emit 0x25; buf_emit32 0x300288
buf_emit 0xFF; buf_emit 0xCA; buf_emit 0x21; buf_emit 0xD0
buf_emit 0xC1; buf_emit 0xE0; buf_emit 3; buf_emit 0x83; buf_emit 0xC0; buf_emit 4
buf_emit 0x8B; buf_emit 0x04; buf_emit 0x07
buf_emit 0xC1; buf_emit 0xE0; buf_emit 11; buf_emit 0x05; buf_emit32 0x620000
buf_emit 0x89; buf_emit 0xC6  # esi = buffer

# Advance last_rx_used
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0
buf_emit 0xFF; buf_emit 0xC1
buf_emit 0x66; buf_emit 0x89; buf_emit 0x0C; buf_emit 0x25; buf_emit32 0x3002A0

# Check EtherType=IP(0x0008 LE) and Protocol=UDP(17)
buf_emit 0x0F; buf_emit 0xB7; buf_emit 0x46; buf_emit 22  # EtherType
buf_emit 0x3D; buf_emit32 0x0008
$jne_dns_skip = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x46; buf_emit 33  # IP proto
buf_emit 0x3C; buf_emit 17  # UDP
$jne_dns_skip2 = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0

# It's a UDP packet with DNS response!
# Save the 4-byte IP from DNS answer at [esi+93] to [0x3002B0] before RSI is clobbered
# DNS answer IP at buffer offset 93 (10 virtio + 14 eth + 20 ip + 8 udp + 12 dns + 17 question + 12 answer_hdr)
buf_emit 0x8B; buf_emit 0x46; buf_emit 93   # mov eax, [rsi+93] (4 bytes: IP)
buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x3002B0  # store IP at scratch

buf_emit 0x59  # pop rcx
$jmp_dns_got = buf_len
buf_emit 0xE9; buf_emit32 0  # jmp dns_got (patched)

# skip / no_packet targets
$dns_skip_off = buf_len
foreach ($p in @($jne_dns_skip, $jne_dns_skip2)) {
    $rel = $dns_skip_off - $p - 6
    $b = [System.BitConverter]::GetBytes([int32]$rel)
    buf_set ($p + 2) $b[0]; buf_set ($p + 3) $b[1]; buf_set ($p + 4) $b[2]; buf_set ($p + 5) $b[3]
}
$dns_no_off = buf_len
$rel_dn = $dns_no_off - $jle_dns_no - 6
$b_dn = [System.BitConverter]::GetBytes([int32]$rel_dn)
buf_set ($jle_dns_no + 2) $b_dn[0]; buf_set ($jle_dns_no + 3) $b_dn[1]
buf_set ($jle_dns_no + 4) $b_dn[2]; buf_set ($jle_dns_no + 5) $b_dn[3]
buf_emit 0x59  # pop rcx
emit_hlt
buf_emit 0xFF; buf_emit 0xC9
buf_emit 0x0F; buf_emit 0x85
buf_emit32_signed ($dns_poll - (buf_len) - 4)
emit_call_puts_str "DNS timeout`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)

# dns_got: print the resolved IP
$dns_got_off = buf_len
$rel_dg = $dns_got_off - $jmp_dns_got - 5
$b_dg = [System.BitConverter]::GetBytes([int32]$rel_dg)
buf_set ($jmp_dns_got + 1) $b_dg[0]; buf_set ($jmp_dns_got + 2) $b_dg[1]
buf_set ($jmp_dns_got + 3) $b_dg[2]; buf_set ($jmp_dns_got + 4) $b_dg[3]

emit_call_puts_str "example.com = "
# Print 4 octets from [0x3002B0..0x3002B3] (saved IP) as decimal
for ($oct = 0; $oct -lt 4; $oct++) {
    if ($oct -gt 0) { emit_call_puts_str "." }
    emit_serial_dec_byte_from_abs32 (0x3002B0 + $oct) $COM1
}
emit_call_puts_str "`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: vesa ---
# Fill screen with blue background + white banner "HicOS 5.0"
emit_cmd_check "vesa"

# Load framebuffer address from [0x3002B8]
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x3002B8  # mov edi, [LFB]
buf_emit 0x85; buf_emit 0xFF  # test edi, edi
$jnz_vesa_ok = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0
emit_call_puts_str "No VESA framebuffer`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
$vesa_cmd_ok = buf_len
$rel_vco = $vesa_cmd_ok - $jnz_vesa_ok - 6
$b_vco = [System.BitConverter]::GetBytes([int32]$rel_vco)
buf_set ($jnz_vesa_ok + 2) $b_vco[0]; buf_set ($jnz_vesa_ok + 3) $b_vco[1]
buf_set ($jnz_vesa_ok + 4) $b_vco[2]; buf_set ($jnz_vesa_ok + 5) $b_vco[3]

# Fill entire screen with dark blue (0x00401000 = BGRA dark blue)
# 1024*768 = 786432 pixels, each 4 bytes
buf_emit 0x53  # push rbx (save)
buf_emit 0xB8; buf_emit32 0x00401000  # mov eax, dark blue (B=0x10, G=0x40, R=0x00)
buf_emit 0xB9; buf_emit32 786432  # mov ecx, 786432 (pixel count)
emit_cld; buf_emit 0xF3; buf_emit 0xAB  # rep stosd (fill)

# Draw a white banner bar: y=280..320, x=200..824 (624×40 pixels)
# EDI is now past the framebuffer, reload
buf_emit 0x8B; buf_emit 0x3C; buf_emit 0x25; buf_emit32 0x3002B8  # mov edi, [LFB]
# Start offset: (280 * 1024 + 200) * 4 = 1147680 = 0x118020
buf_emit 0x81; buf_emit 0xC7; buf_emit32 0x118020  # add edi, offset
buf_emit 0xB8; buf_emit32 0x00FFFFFF  # mov eax, white
# Draw 40 rows of 624 white pixels
buf_emit 0xBB; buf_emit32 40  # mov ebx, 40 (row counter)
$vesa_bar_loop = buf_len
buf_emit 0xB9; buf_emit32 624  # mov ecx, 624
buf_emit 0xF3; buf_emit 0xAB  # rep stosd (624 white pixels)
# Advance to next row: skip (1024-624)*4 = 1600 bytes
buf_emit 0x81; buf_emit 0xC7; buf_emit32 1600  # add edi, (1024-624)*4
buf_emit 0xFF; buf_emit 0xCB  # dec ebx
buf_emit 0x0F; buf_emit 0x85
buf_emit32_signed ($vesa_bar_loop - (buf_len) - 4)

buf_emit 0x5B  # pop rbx

emit_call_puts_str "VESA: 1024x768x32 drawn`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: ring3 ---
# Switch to Ring3 user mode, execute user code that prints via SYSCALL, then exit
emit_cmd_check "ring3"

emit_call_puts_str "Ring3: entering user mode...`r`n"

# Save kernel return address at [0x6108] for syscall exit
$ring3_return = buf_len  # we'll patch this after the IRETQ block
buf_emit 0x48; buf_emit 0x8D; buf_emit 0x05; buf_emit32 0  # lea rax, [rip+0] (patched)
buf_emit 0x48; buf_emit 0x89; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x6108

# Place tiny user-mode program at 0x8000 (12 bytes)
# User code: syscall(1, 'U')→print 'U', syscall(1, '3')→print '3', syscall(0)→exit
# mov rax, 1; mov rdi, 'U'; syscall; mov rax, 1; mov rdi, '3'; syscall; mov rax, 0; syscall
buf_emit 0xBF; buf_emit32 0x8000  # mov edi, 0x8000
# Byte 0: mov eax, 1 (B8 01 00 00 00)
buf_emit 0xC6; buf_emit 0x07; buf_emit 0xB8
buf_emit 0xC7; buf_emit 0x47; buf_emit 1; buf_emit32 1
# Byte 5: mov edi, 'U' (BF 55 00 00 00)
buf_emit 0xC6; buf_emit 0x47; buf_emit 5; buf_emit 0xBF
buf_emit 0xC7; buf_emit 0x47; buf_emit 6; buf_emit32 0x55
# Byte 10: syscall (0F 05)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 10; buf_emit16 0x050F
# Byte 12: mov eax, 1 (B8 01 00 00 00)
buf_emit 0xC6; buf_emit 0x47; buf_emit 12; buf_emit 0xB8
buf_emit 0xC7; buf_emit 0x47; buf_emit 13; buf_emit32 1
# Byte 17: mov edi, '3' (BF 33 00 00 00)
buf_emit 0xC6; buf_emit 0x47; buf_emit 17; buf_emit 0xBF
buf_emit 0xC7; buf_emit 0x47; buf_emit 18; buf_emit32 0x33
# Byte 22: syscall (0F 05)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 22; buf_emit16 0x050F
# Byte 24: mov eax, 0 (B8 00 00 00 00)
buf_emit 0xC6; buf_emit 0x47; buf_emit 24; buf_emit 0xB8
buf_emit 0xC7; buf_emit 0x47; buf_emit 25; buf_emit32 0
# Byte 29: syscall (0F 05)
buf_emit 0x66; buf_emit 0xC7; buf_emit 0x47; buf_emit 29; buf_emit16 0x050F

# IRETQ to Ring3: push SS, RSP, RFLAGS, CS, RIP
# User SS = 0x30 | 3 = 0x33
buf_emit 0x6A; buf_emit 0x33  # push 0x33 (user SS)
buf_emit 0x68; buf_emit32 0x9000  # push 0x9000 (user RSP)
buf_emit 0x9C  # pushfq
# Set IF in pushed RFLAGS
buf_emit 0x48; buf_emit 0x81; buf_emit 0x0C; buf_emit 0x24; buf_emit32 0x200  # or [rsp], 0x200
# User CS = 0x38 | 3 = 0x3B
buf_emit 0x6A; buf_emit 0x3B  # push 0x3B (user CS)
buf_emit 0x68; buf_emit32 0x8000  # push 0x8000 (user RIP)
emit_iretq

# --- ring3_return: execution returns here after syscall(0) ---
$ring3_return_off = buf_len
# Patch the LEA offset: ring3_return_off - (ring3_return + 7) (RIP-relative)
$lea_target = 0x100000 + $ring3_return_off
$lea_src = 0x100000 + $ring3_return + 7  # RIP after the LEA instruction
$lea_rel = $lea_target - $lea_src
$b_lr = [System.BitConverter]::GetBytes([int32]$lea_rel)
buf_set ($ring3_return + 3) $b_lr[0]; buf_set ($ring3_return + 4) $b_lr[1]
buf_set ($ring3_return + 5) $b_lr[2]; buf_set ($ring3_return + 6) $b_lr[3]

emit_call_puts_str "`r`nRing3: user mode test PASSED`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: clear ---
emit_cmd_check "clear"
# Send VT100 escape sequence: ESC[2J (clear screen) + ESC[H (cursor home)
$esc = [char]27
emit_call_puts_str "${esc}[2J${esc}[H"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Command: hexdump (hex dump of disk sector 0) ---
emit_cmd_check "hexdump"
emit_call_puts_str "Sector 0 hex dump:`r`n"

# Read sector 0 into 0x510000
buf_emit 0x45; buf_emit 0x31; buf_emit 0xC0     # xor r8d, r8d (sector=0)
buf_emit 0x49; buf_emit 0xC7; buf_emit 0xC1; buf_emit32 0x510000  # mov r9, buf
buf_emit 0x41; buf_emit 0xB2; buf_emit 0        # mov r10b, 0 (READ)
buf_emit 0xE8; buf_emit32_signed ($disk_rw_off - (buf_len) - 4)

# Loop: 32 rows × 16 bytes
# R12 = byte index (0..511), RBX = buffer base
buf_emit 0x45; buf_emit 0x31; buf_emit 0xE4     # xor r12d, r12d
buf_emit 0xBB; buf_emit32 0x510000               # mov ebx, 0x510000

$hexdump_row_loop = buf_len
# Print offset as 4 hex digits: R12 value
# High byte of offset
buf_emit 0x44; buf_emit 0x89; buf_emit 0xE0     # mov eax, r12d
buf_emit 0xC1; buf_emit 0xE8; buf_emit 8        # shr eax, 8
buf_emit 0xE8; buf_emit32_signed ($serial_hex_byte_off - (buf_len) - 4)  # call serial_hex_byte
# Low byte of offset
buf_emit 0x44; buf_emit 0x89; buf_emit 0xE0     # mov eax, r12d
buf_emit 0xE8; buf_emit32_signed ($serial_hex_byte_off - (buf_len) - 4)  # call serial_hex_byte
emit_call_puts_str ": "

# Print 16 hex bytes
buf_emit 0x31; buf_emit 0xC9                     # xor ecx, ecx (byte counter 0..15)
$hexdump_byte_loop = buf_len
buf_emit 0x49; buf_emit 0x89; buf_emit 0xDD     # mov r13, rbx (save rbx)
buf_emit 0x42; buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x23  # movzx eax, byte [rbx+r12]
buf_emit 0x51                                     # push rcx (save counter)
buf_emit 0x41; buf_emit 0x54                      # push r12
buf_emit 0xE8; buf_emit32_signed ($serial_hex_byte_off - (buf_len) - 4)
buf_emit 0xE8; buf_emit32_signed ($serial_space_off - (buf_len) - 4)
buf_emit 0x41; buf_emit 0x5C                      # pop r12
buf_emit 0x59                                     # pop rcx
buf_emit 0x4C; buf_emit 0x89; buf_emit 0xEB     # mov rbx, r13 (restore)
buf_emit 0x49; buf_emit 0xFF; buf_emit 0xC4     # inc r12
buf_emit 0xFF; buf_emit 0xC1                     # inc ecx
# Extra space after 8 bytes
buf_emit 0x83; buf_emit 0xF9; buf_emit 8        # cmp ecx, 8
buf_emit 0x75; buf_emit 0                        # jne +N (skip extra space)
$jne_no_extra = buf_len - 1
buf_emit 0x51                                     # push rcx
buf_emit 0x41; buf_emit 0x54                      # push r12
buf_emit 0xE8; buf_emit32_signed ($serial_space_off - (buf_len) - 4)
buf_emit 0x41; buf_emit 0x5C                      # pop r12
buf_emit 0x59                                     # pop rcx
$after_extra_space = buf_len
buf_set $jne_no_extra ([byte](($after_extra_space - $jne_no_extra - 1) -band 0xFF))
buf_emit 0x83; buf_emit 0xF9; buf_emit 16       # cmp ecx, 16
buf_emit 0x0F; buf_emit 0x8C                     # jl hexdump_byte_loop
buf_emit32_signed ($hexdump_byte_loop - (buf_len) - 4)

# Print newline
emit_call_puts_str "`r`n"

# Check if we've done all 512 bytes
buf_emit 0x49; buf_emit 0x81; buf_emit 0xFC; buf_emit32 512  # cmp r12, 512
buf_emit 0x0F; buf_emit 0x8C                     # jl hexdump_row_loop
buf_emit32_signed ($hexdump_row_loop - (buf_len) - 4)

emit_call_puts_str "MBR signature: "
# Check bytes at 0x5101FE/FF for 0x55AA
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x5101FE
buf_emit 0x3C; buf_emit 0x55                     # cmp al, 0x55
buf_emit 0x75; buf_emit 0                        # jne .no55aa
$jne_no55aa = buf_len - 1
buf_emit 0x0F; buf_emit 0xB6; buf_emit 0x04; buf_emit 0x25; buf_emit32 0x5101FF
buf_emit 0x3C; buf_emit 0xAA
buf_emit 0x75; buf_emit 0                        # jne .no55aa2
$jne_no55aa2 = buf_len - 1
emit_call_puts_str "0x55AA (valid)`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
$no55aa_off = buf_len
buf_set $jne_no55aa ([byte](($no55aa_off - $jne_no55aa - 1) -band 0xFF))
buf_set $jne_no55aa2 ([byte](($no55aa_off - $jne_no55aa2 - 1) -band 0xFF))
emit_call_puts_str "not found`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)
patch_cmd_skip

# --- Unknown command ---
emit_call_puts_str "Unknown command. Type 'help'.`r`n"
buf_emit 0xE9; buf_emit32_signed ($cmd_return - (buf_len) - 4)

# =============================================================
# String Data Section (deferred emission, patched into code above)
# =============================================================
foreach ($si in 0..($script:str_data.Count - 1)) {
    $str_kernel_addr = 0x100000 + (buf_len)
    # Emit string bytes + null terminator
    foreach ($ch in $script:str_data[$si].ToCharArray()) {
        buf_emit ([byte][int]$ch)
    }
    buf_emit 0  # null
    # Patch all references to this string
    foreach ($patch in $script:str_patches) {
        if ($patch.idx -eq $si) {
            $addr_bytes = [System.BitConverter]::GetBytes([uint32]$str_kernel_addr)
            buf_set ($patch.loc) $addr_bytes[0]
            buf_set ($patch.loc + 1) $addr_bytes[1]
            buf_set ($patch.loc + 2) $addr_bytes[2]
            buf_set ($patch.loc + 3) $addr_bytes[3]
        }
    }
}

# === Append raw data sections (ISR stubs + IDT entries) ===
# These will be copied to their target addresses by the rep movsb code above.
# Kernel is loaded at 0x100000, so data addresses = 0x100000 + offset_in_kernel

$isr_data_offset = buf_len  # offset within kernel binary
foreach ($b in $isr_bytes) { buf_emit $b }

$idt_data_offset = buf_len
foreach ($b in $idt_data) { buf_emit $b }

# Patch the ISR copy source address: 0x100000 + isr_data_offset
$isr_data_addr = 0x100000 + $isr_data_offset
$isr_addr_bytes = [System.BitConverter]::GetBytes([uint64]$isr_data_addr)
for ($p = 0; $p -lt 8; $p++) { buf_set ($isr_copy_rsi_patch + $p) $isr_addr_bytes[$p] }

# Patch the IDT copy source address: 0x100000 + idt_data_offset
$idt_data_addr = 0x100000 + $idt_data_offset
$idt_addr_bytes = [System.BitConverter]::GetBytes([uint64]$idt_data_addr)
for ($p = 0; $p -lt 8; $p++) { buf_set ($idt_copy_rsi_patch + $p) $idt_addr_bytes[$p] }

$kern_bytes = [byte[]]$script:buf.ToArray()
$kern_sectors = [math]::Ceiling($kern_bytes.Length / 512)
Write-Host "  Kernel: $($kern_bytes.Length) bytes ($kern_sectors sectors)" -ForegroundColor White

# === Export handwritten-kernel symbol table for hl-compile-pipeline linker ===
# Sprint 36: builtin trampolines need absolute addresses of handwritten subroutines.
$kernSymTable = @{
    base       = '0x100000'
    serial_puts     = ('0x{0:X}' -f (0x100000 + $serial_puts_off))
    serial_hex_byte = ('0x{0:X}' -f (0x100000 + $serial_hex_byte_off))
}
$kernSymPath = Join-Path $PSScriptRoot '..\bare-kernel\kernel-symbols.json'
$kernSymTable | ConvertTo-Json | Set-Content -Path $kernSymPath -Encoding ASCII
Write-Host "  Symbol export: serial_puts=$($kernSymTable.serial_puts)" -ForegroundColor DarkGray

# === Append optional `kernel.bin` payload after the handwritten kernel ===
# Pad the handwritten kernel to 128 KB (0x20000), then append `kernel.bin`.
# The appended payload runs at 0x120000 (0x100000 + 0x20000).
# Note: $kernelBinPath and $kb_entry_offset were pre-read at script start
if (Test-Path $kernelBinPath) {
    $kb_data = [System.IO.File]::ReadAllBytes($kernelBinPath)
    $pad_target = 0x20000  # 128 KB
    if ($kern_bytes.Length -lt $pad_target) {
        $padded = [byte[]]::new($pad_target)
        [Array]::Copy($kern_bytes, $padded, $kern_bytes.Length)
        $kern_bytes = $padded
    }
    # Append kernel.bin
    $combined = [byte[]]::new($kern_bytes.Length + $kb_data.Length)
    [Array]::Copy($kern_bytes, $combined, $kern_bytes.Length)
    [Array]::Copy($kb_data, 0, $combined, $kern_bytes.Length, $kb_data.Length)
    $kern_bytes = $combined
    $kern_sectors = [math]::Ceiling($kern_bytes.Length / 512)
    Write-Host "  kernel.bin: $($kb_data.Length) bytes appended at 0x120000" -ForegroundColor Cyan
    Write-Host "  _start offset: $kb_entry_offset (absolute: 0x$(([int64](0x120000 + $kb_entry_offset)).ToString('X')))" -ForegroundColor Cyan
    Write-Host "  Combined kernel: $($kern_bytes.Length) bytes ($kern_sectors sectors)" -ForegroundColor Cyan
} else {
    Write-Host "  kernel.bin not found, skipping kernel.bin integration" -ForegroundColor Yellow
}

# =========================================
# Build Stage 2 (real → protected → long mode)
# =========================================
$script:buf = [System.Collections.ArrayList]::new()
$s2_origin = [uint32]0x8000

emit_cli

# === VBE Mode Setting (Real Mode) ===
# Set VESA 1024x768x32 mode via VBE BIOS INT 10h before switching to long mode.
# 1. Get VBE mode info for mode 0x118 into buffer at 0x7100
# 2. Extract LFB physical address from offset +40
# 3. Store at [0x7000] for kernel to read
# 4. Set the mode with LFB enabled (bit 14 of mode number)
# If VBE call fails, fall back to LFB=0 (kernel treats as no framebuffer).

# Get VBE mode info: AX=0x4F01, CX=mode, ES:DI=buffer
buf_emit 0x31; buf_emit 0xC0                               # xor ax, ax
buf_emit 0x8E; buf_emit 0xC0                               # mov es, ax
buf_emit 0x66; buf_emit 0xB8; buf_emit32 0x00004F01        # mov eax, 0x4F01
buf_emit 0xB9; buf_emit16 0x0118                            # mov cx, 0x0118
buf_emit 0xBF; buf_emit16 0x7100                            # mov di, 0x7100
buf_emit 0xCD; buf_emit 0x10                                # int 0x10
# Check AX == 0x004F
buf_emit 0x66; buf_emit 0x3D; buf_emit16 0x004F; buf_emit16 0x0000  # cmp eax, 0x004F
$jne_vbe_fail_patch = buf_len
buf_emit 0x0F; buf_emit 0x85; buf_emit32 0                 # jne vbe_fail (patch later)

# Save LFB address: [0x7100 + 40] = [0x7128] -> [0x7000]
buf_emit 0x66; buf_emit 0xA1; buf_emit16 0x7128            # mov eax, [0x7128]
buf_emit 0x66; buf_emit 0xA3; buf_emit16 0x7000            # mov [0x7000], eax

# Set VBE mode: AX=0x4F02, BX=mode|0x4000 (LFB bit)
buf_emit 0x66; buf_emit 0xB8; buf_emit32 0x00004F02        # mov eax, 0x4F02
buf_emit 0xBB; buf_emit16 0x4118                            # mov bx, 0x4118 (mode 0x118 + LFB)
buf_emit 0xCD; buf_emit 0x10                                # int 0x10
$jmp_vbe_done_patch = buf_len
buf_emit 0xE9; buf_emit16 0                                # jmp vbe_done (patch later)

# vbe_fail: clear LFB address (no framebuffer)
$vbe_fail_off = buf_len
buf_emit 0x66; buf_emit 0x31; buf_emit 0xC0                # xor eax, eax
buf_emit 0x66; buf_emit 0xA3; buf_emit16 0x7000            # mov [0x7000], eax

# vbe_done:
$vbe_done_off = buf_len
# Patch jump targets
$rel_fail = $vbe_fail_off - ($jne_vbe_fail_patch + 6)
buf_set ($jne_vbe_fail_patch + 2) ([byte]($rel_fail -band 0xFF))
buf_set ($jne_vbe_fail_patch + 3) ([byte](($rel_fail -shr 8) -band 0xFF))
buf_set ($jne_vbe_fail_patch + 4) ([byte](($rel_fail -shr 16) -band 0xFF))
buf_set ($jne_vbe_fail_patch + 5) ([byte](($rel_fail -shr 24) -band 0xFF))
$rel_done = $vbe_done_off - ($jmp_vbe_done_patch + 3)
buf_set ($jmp_vbe_done_patch + 1) ([byte]($rel_done -band 0xFF))
buf_set ($jmp_vbe_done_patch + 2) ([byte](($rel_done -shr 8) -band 0xFF))

# === Load kernel after Stage2 (real mode, BIOS CHS one-sector loop) ===
# QEMU BIOS exposes a 63-sector, 16-head geometry for this small image, so the
# kernel still fits in cylinder 0 and can be loaded with a compact CHS loop.
$stage2KernelLoader = emit_stage2_kernel_read_chs_loop ([uint16]$kern_sectors)
$s2_kernel_lba_patch = [int]$stage2KernelLoader.KernelLbaPatch
$s2_kernel_seg_patch = [int]$stage2KernelLoader.LoadSegPatch

# LGDT placeholder (patch later)
$lgdt_patch = (buf_len) + 3
emit_lgdt_imm16 0

# Enable PE
emit_mov_eax_cr0
buf_emit 0x66; buf_emit 0x83; buf_emit 0xC8; buf_emit 0x01  # or eax, 1
emit_mov_cr0_eax

# Far JMP to 32-bit: 0x66 prefix + EA offset32 seg16
buf_emit 0x66  # operand-size override: force 32-bit offset in 16-bit mode
$j32_patch = (buf_len) + 1
emit_jmp_far32 8 0

# 32-bit code
$code32_off = buf_len
$addr32 = $s2_origin + $code32_off
buf_set $j32_patch ([byte]($addr32 -band 0xFF))
buf_set ($j32_patch + 1) ([byte](($addr32 -shr 8) -band 0xFF))
buf_set ($j32_patch + 2) ([byte](($addr32 -shr 16) -band 0xFF))
buf_set ($j32_patch + 3) ([byte](($addr32 -shr 24) -band 0xFF))

# Data segments = 0x10
emit_mov_ax_imm16_32; emit_mov_ds_ax; emit_mov_es_ax; emit_mov_ss_ax

# Identity paging: clear 16KB at 0x1000 (PML4+PDPT+PD0+PD3)
emit_mov_edi_imm32 0x1000; emit_mov_ecx_imm32 4096; emit_xor_eax_eax; emit_rep_stosd
# PML4[0] → PDPT (P+R/W+U/S)
emit_mov_edi_imm32 0x1000; emit_mov_eax_imm32 0x2007; emit_mov_mem_edi_eax
# PDPT[0] → PD at 0x3000 (P+R/W+U/S, covers 0-1GB)
emit_mov_edi_imm32 0x2000; emit_mov_eax_imm32 0x3007; emit_mov_mem_edi_eax
# PDPT[3] → PD at 0x4000 (covers 3GB-4GB, for VESA framebuffer)
emit_mov_edi_imm32 0x2018; emit_mov_eax_imm32 0x4003; emit_mov_mem_edi_eax
# PD[0] → 2MB page at 0 (P+R/W+U/S+PS — user code/stack live here)
emit_mov_edi_imm32 0x3000; emit_mov_eax_imm32 0x87; emit_mov_mem_edi_eax
# PD[1] → 2MB page at 2MB
emit_mov_edi_imm32 0x3008; emit_mov_eax_imm32 0x200083; emit_mov_mem_edi_eax
# PD[2] → 2MB page at 4MB (for virtqueue at 0x400000)
emit_mov_edi_imm32 0x3010; emit_mov_eax_imm32 0x400083; emit_mov_mem_edi_eax
# PD[3] → 2MB page at 6MB (for request buffers at 0x500000+)
emit_mov_edi_imm32 0x3018; emit_mov_eax_imm32 0x600083; emit_mov_mem_edi_eax
# PD3[488] → 2MB page at 0xFD000000 (VESA LFB, first 2MB)
emit_mov_edi_imm32 0x4F40
buf_emit 0xB8; buf_emit32 0xFD000083; emit_mov_mem_edi_eax
# PD3[489] → 2MB page at 0xFD200000 (VESA LFB, second 2MB)
emit_mov_edi_imm32 0x4F48
buf_emit 0xB8; buf_emit32 0xFD200083; emit_mov_mem_edi_eax

# CR3 = PML4
emit_mov_eax_imm32 0x1000; emit_mov_cr3_eax
# Enable PAE
emit_mov_eax_cr4; emit_bts_eax 5; emit_mov_cr4_eax
# IA-32e via EFER MSR (LME=bit8 + SCE=bit0 for SYSCALL)
emit_mov_ecx_imm32 0xC0000080; emit_rdmsr; emit_bts_eax 8; emit_bts_eax 0; emit_wrmsr
# Enable paging
emit_mov_eax_cr0; emit_bts_eax 31; emit_mov_cr0_eax

# Far JMP to 64-bit
$j64_patch = (buf_len) + 1
emit_jmp_far32 24 0

$code64_off = buf_len
$addr64 = $s2_origin + $code64_off
buf_set $j64_patch ([byte]($addr64 -band 0xFF))
buf_set ($j64_patch + 1) ([byte](($addr64 -shr 8) -band 0xFF))
buf_set ($j64_patch + 2) ([byte](($addr64 -shr 16) -band 0xFF))
buf_set ($j64_patch + 3) ([byte](($addr64 -shr 24) -band 0xFF))

# 64-bit: copy kernel from temp load address to 0x100000
emit_mov_rsp_imm64 0x70000
emit_cld

# Copy kernel: src = 0x8000 + s2_sectors*512, dst = 0x100000, len = kern_bytes.Length
# Use rep movsb: RSI=src, RDI=dst, RCX=count
# Note: $s2_sectors not yet known here; emit placeholder imm64, patch after Stage 2 finalized
# mov rsi, <kern_src placeholder>
buf_emit 0x48; buf_emit 0xBE  # REX.W MOV RSI, imm64
$kern_src_patch_off = buf_len  # save offset of imm64 bytes for patching
buf_emit32 0; buf_emit32 0    # placeholder (patched below after $s2_sectors is computed)
# mov rdi, 0x100000
buf_emit 0x48; buf_emit 0xBF  # REX.W MOV RDI, imm64
buf_emit32 0x100000; buf_emit32 0
# mov rcx, kern_bytes.Length
buf_emit 0x48; buf_emit 0xB9  # REX.W MOV RCX, imm64
buf_emit32 ([int64]$kern_bytes.Length); buf_emit32 0
# rep movsb (F3 A4)
buf_emit 0xF3; buf_emit 0xA4

# JMP to kernel at 0x100000
emit_mov_rax_imm64 0x100000
emit_jmp_rax

# GDT (null, code32, data32, code64, data64, user_compat, user_data64, user_code64, TSS)
$gdt_off = buf_len
buf_emit32 0; buf_emit32 0                              # [0x00] null
buf_emit32 0x0000FFFF; buf_emit32 0x00CF9A00            # [0x08] code32 (DPL=0)
buf_emit32 0x0000FFFF; buf_emit32 0x00CF9200            # [0x10] data32 (DPL=0)
buf_emit32 0x0000FFFF; buf_emit32 0x00AF9A00            # [0x18] code64 (DPL=0, L=1) — kernel CS
buf_emit32 0x0000FFFF; buf_emit32 0x00CF9200            # [0x20] data64 (DPL=0) — kernel SS
buf_emit32 0x0000FFFF; buf_emit32 0x00CFFA00            # [0x28] user compat (DPL=3) — SYSRET base
buf_emit32 0x0000FFFF; buf_emit32 0x00CFF200            # [0x30] user data64 (DPL=3) — user SS
buf_emit32 0x0000FFFF; buf_emit32 0x00AFFA00            # [0x38] user code64 (DPL=3, L=1) — user CS
# TSS64 descriptor at [0x40]: base=0x6000, limit=103
buf_emit32 0x60000067  # limit_low=0x67, base_low=0x6000
buf_emit32 0x00008900  # base_mid=0, type=0x89(avail TSS64), base_high=0
buf_emit32 0; buf_emit32 0  # base[63:32]=0, reserved

# GDTR
$gdtr_off = buf_len
buf_emit16 (10 * 8 - 1)                                   # limit = 79
buf_emit32 ($s2_origin + $gdt_off)                         # base

# Patch LGDT address
$gdtr_addr = $s2_origin + $gdtr_off
buf_set $lgdt_patch ([byte]($gdtr_addr -band 0xFF))
buf_set ($lgdt_patch + 1) ([byte](($gdtr_addr -shr 8) -band 0xFF))

$s2_bytes = [byte[]]$script:buf.ToArray()
$s2_sectors = [math]::Ceiling($s2_bytes.Length / 512)
Write-Host "  Stage2: $($s2_bytes.Length) bytes ($s2_sectors sectors)" -ForegroundColor White

# Patch kern_src in Stage 2 code (was placeholder, now $s2_sectors is known)
# Stage1 loads from LBA 1 to 0x8000, so Stage2 starts at 0x8000 and the kernel
# begins immediately after the Stage2 sectors.
$kern_src = [uint64]($s2_origin + $s2_sectors * 512)
$ks_bytes = [System.BitConverter]::GetBytes([uint64]$kern_src)
for ($p = 0; $p -lt 8; $p++) { $s2_bytes[$kern_src_patch_off + $p] = $ks_bytes[$p] }
$s2_kernel_lba = [uint16](1 + $s2_sectors)
$s2_load_seg = [uint16](0x0800 + ($s2_sectors * 32))
$s2_bytes[$s2_kernel_lba_patch] = [byte]($s2_kernel_lba -band 0xFF)
$s2_bytes[$s2_kernel_lba_patch + 1] = [byte](($s2_kernel_lba -shr 8) -band 0xFF)
$s2_bytes[$s2_kernel_seg_patch] = [byte]($s2_load_seg -band 0xFF)
$s2_bytes[$s2_kernel_seg_patch + 1] = [byte](($s2_load_seg -shr 8) -band 0xFF)
Write-Host "  Patched kern_src = 0x$([Convert]::ToString([int64]$kern_src, 16).ToUpper()) in Stage2" -ForegroundColor DarkGray

# =========================================
# Build Stage 1 (MBR)
# =========================================
$read_sectors = $s2_sectors
$script:buf = [System.Collections.ArrayList]::new()

emit_cli; emit_xor_ax_ax; emit_mov_ds_ax; emit_mov_es_ax; emit_mov_ss_ax
emit_mov_sp_imm16 0x7C00
emit_sti

# INT 13h CHS read: load Stage2 only (sectors 2..)
emit_stage1_load_stage2_chs ([byte]$s2_sectors) 0x8000

# A20
emit_in_al_imm8 0x92; emit_or_al_imm8 2; emit_out_imm8_al 0x92

# JMP to Stage2
emit_jmp_far16 0 0x8000

# Pad + boot signature
buf_pad_to 510
buf_emit 0x55; buf_emit 0xAA

$s1_bytes = [byte[]]$script:buf.ToArray()
Write-Host "  Stage1: $($s1_bytes.Length) bytes (MBR, reads $read_sectors sectors)" -ForegroundColor White

# =========================================
# Assemble final image
# =========================================
$total_sectors = 1 + $s2_sectors + $kern_sectors
$img_size = $total_sectors * 512
$img = [byte[]]::new($img_size)

# Copy Stage 1
[Array]::Copy($s1_bytes, 0, $img, 0, $s1_bytes.Length)
# Copy Stage 2
[Array]::Copy($s2_bytes, 0, $img, 512, $s2_bytes.Length)
# Copy Kernel
$kern_start = (1 + $s2_sectors) * 512
[Array]::Copy($kern_bytes, 0, $img, $kern_start, $kern_bytes.Length)

# Write image
[System.IO.File]::WriteAllBytes((Join-Path $repoRoot 'hicos-hl.img'), $img)
Write-Host '' -ForegroundColor White
Write-Host "  Total: $img_size bytes ($total_sectors sectors)" -ForegroundColor Green
Write-Host "  Stage1: sector 0 (MBR, reads $read_sectors sectors to 0x8000)" -ForegroundColor White
Write-Host "  Stage2: sectors 1-$s2_sectors (real->long mode)" -ForegroundColor White
Write-Host "  Kernel: sectors $($s2_sectors+1)-$($total_sectors-1) (loaded at 0x100000)" -ForegroundColor White
Write-Host "  Written: hicos-hl.img" -ForegroundColor Green
