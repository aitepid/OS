# HicOS Architecture

## Overview

HicOS is a three-layer experimental x86_64 OS written entirely in Hilbert-Lang (H-L).

| Layer | Medium | Role |
|---|---|---|
| A | `scripts/rebuild-image.ps1` (190 KB PowerShell) | Emits raw x86_64 machine code → `hicos-hl.img` (MBR + Stage 2 + kernel) |
| B | `hl-bootstrap.hl` (4,572 lines, 208 fn) | Self-hosting compiler / interpreter / linker / REPL |
| C | `bare-kernel/hl/*.hl` (470 modules, incl. 47 GUI scaffold) | Kernel modules — subsystems, drivers, protocol stacks, algorithms, GUI |

Layer A is the only non-H-L code in the repo. It exists because no H-L bootstrap is available before the kernel comes up — once the kernel runs, the H-L interpreter takes over and all further code is H-L.

## Boot Chain

### BIOS path

```
MBR (sector 0, 512 B)              ; Stage 1 — emitted by Layer A
  └─ reads Stage 2 to 0x8000
Stage 2 (sector 1)                  ; real → protected → long mode + VBE 1024×768×32
  └─ jumps to kernel at 0x100000
kernel.bin (sectors 2+)             ; native x86_64 entry
  └─ kernel_entry.hl                ; serial init, IDT, PIC/PIT, PS-2, PCI scan
      └─ kernel_init.hl             ; subsystem init across 423 modules
          └─ shell.hl                ; serial shell (1,800 commands)
```

### UEFI path

```
OVMF firmware → GPT → ESP → BOOTX64.EFI → UEFI boot
```

## Codebase Metrics

| Metric | Value |
|---|---:|
| Total `.hl` files | 539 |
| Root `.hl` files | 69 |
| `bare-kernel/hl/` modules | 470 |
| Total H-L lines | ~165,000 |
| `kernel_entry.hl` | 10,435 lines, 307 fn |
| `hl-bootstrap.hl` | 4,572 lines, 208 fn |
| `stdlib.hl` | 1,545 lines, 143 fn |
| `scripts/*.ps1` | 32 scripts, ~11,500 lines |
| Shell commands | 1,800 |
| `HicOS_*.hl` subsystem modules | 27 |
| GUI scaffold modules (Sprint G1) | 47 |

## Key Source Locations

- `bare-kernel/hl/kernel_entry.hl` — kernel entry, interrupt init, command dispatch
- `bare-kernel/hl/kernel_init.hl` — subsystem initialization sequence
- `bare-kernel/hl/shell.hl` — serial shell (1,800 commands, pipes, history)
- `bare-kernel/hl/kinterp.hl` — kernel interpreter (tree-walk + IR VM dual-engine)
- `bare-kernel/hl/kmod.hl` — kernel module hot-patching (64 slots, 256 trampolines)
- `bare-kernel/hl/virtio_blk.hl` — VirtIO-blk legacy driver (descriptor chain, used ring)
- `hl-bootstrap.hl` — self-hosting toolchain
- `stdlib.hl` — H-L standard library
- `scripts/rebuild-image.ps1` — BIOS image emitter (raw machine code)
- `scripts/build-uefi-image.ps1` — UEFI image builder
- `scripts/qemu-visual-test.ps1` — interactive QEMU launcher (serial console)
- `scripts/full-gate.ps1` — full validation gate

## Memory Layout

### Bootstrap-fixed regions

| Address | Size | Purpose |
|---|---|---|
| 0x7C00 | 512 B | MBR / Stage 1 load address |
| 0x8000 | 512 B | Stage 2 load address |
| 0x100000 | ~30 KB | Kernel load address |
| 0x300000–0x3000FF | 256 B | virtio queue area base |
| 0x400000 | 4 KB | VirtIO descriptor base |
| 0x500000 | 16 B | VirtIO request header |
| 0x500010 | 512 B | VirtIO data buffer |
| 0x500210 | 1 B | VirtIO status byte |
| 0xFD000000 | LFB | VESA linear framebuffer (typical) |

### Per-module H-L buffer addresses (Phase 7)

Each high-level module has a dedicated buffer at a deterministic offset:

| Range | Modules |
|---|---|
| 0x1DC0000–0x1DE0000 | package_manager / pkg_registry / pkg_build |
| 0x1DF0000–0x1E10000 | hldoc / hltest / hlbench |
| 0x1E20000–0x1E40000 | lsp_server / syntax_highlight / code_complete |
| 0x1E50000–0x1E70000 | debugger / gdb_stub / breakpoint |
| 0x1E80000–0x1EA0000 | hl_repl / hl_fmt / hl_lint2 |
| 0x1EB0000–0x1ED0000 | posix_compat / musl_shim / linux_syscall |
| 0x1EE0000–0x1EF0000 | wasm_runtime / wasm_jit |

## Iteration History (Layer C growth)

| Phase | Iterations | Module count | Theme |
|---|---|---:|---|
| 1–5 | 81–107 | → 27 | Memory / network / multicore / scheduling / isolation kernel upgrades |
| 6 | 109–130 | → 130 | Runtime + bare-metal install + graphical desktop framework |
| 7–8 | 131–246 | → 232 | Protocol & format expansion (HTTP/WS/MQTT/LZ4/AES/PNG/…) |
| 9 | 247–339 | → 325 | Distributed / probabilistic / tree / graph / string / number-theoretic / geometry algorithms |
| 10 | 340–360 | → 346 | Algorithm library completion ✦ **M1** |
| 11 | 361–375 | → 361 | Compiler depth: SSA passes, regalloc, generics, ELF linker, DWARF ✦ **M2** |
| 12 | 376–385 | → 371 | Storage engine: B-Tree / WAL / MVCC / query plan ✦ **M3** |
| 13 | 386–395 | → 381 | Network depth: WireGuard / TLS 1.3 / HTTP/3 / DoH / gRPC / OpenTelemetry |
| 14 | 396–405 | → 391 | ML framework: CNN / RNN / LSTM / autograd / optimizer ✦ **M4** |
| 15 | 406–420 | → 406 | Stability: CFS / NUMA / ftrace / kprobe / hotpatch / hypervisor ✦ **M5** |
| 16 | 421–440 | → 426 | Ecosystem: pkg manager / LSP / debugger / POSIX / WASM ✦ **M6** |

## Quality & Hardening (Sprint 1–31)

After milestone M6, the codebase went through 31 sprints of systematic quality work:

| Sprint range | Focus | Files touched |
|---|---|---|
| 1–17 | H-L grammar compliance, naming conflicts, scalar-as-array fixes, `let mut` completion, `continue` removal | 400+ files, 10,379 syntactic corrections |
| 26 | QEMU stress test round 1 — BUG-001 to BUG-006 (P0/P1: shell scancode, gdb_stub bounds, TLS AES-GCM, random seed, JWT verify) | 6 files |
| 27 | QEMU stress test round 1 — BUG-007 to BUG-025 (x509 parsing, DNS callback, socket dispatch, QUIC protect, JIT ops, ext4 extent tree, linker forward stubs, PTY FD base, CBOR tags, ABI bounds, lsp/debug/syntax/complete) | 19 files |
| 28 | QEMU stress test round 2 — BUG-026 to BUG-040 (15 issues) | 15 files |
| 29 | QEMU stress test round 3 — BUG-041 to BUG-055 (ext4 block_size shadowing, lz4 lit_nibble shadow, aes_gcm push, QUIC nonce XOR, TLS handshake length, UDP/DHCP validation, VirtIO desc terminator, mmap phys, ICMP ARP constant, etc.) | 13 files |
| 30 | QEMU stress test round 4 — BUG-056 to BUG-060 (broken_profile_dp pow2, trie pool exhaustion, FileEncryption error path, bmp bounds, attention pos-enc bounds) | 5 files |
| 31 | Investigated pre-existing disk-write flake (host-side virtio timing); documented as non-blocking | 0 fixes |

Total: 60 unique BUG entries, all fixed except 1 known QEMU-host timing flake (data correctness verified externally).

## Codegen Sprints (Sprint 35–38)

After Phase 2 codegen integration, four sprints addressed compilation-pipeline correctness:

| Sprint | Date | Focus |
|---|---|---|
| 35 | 2026-05-20 | Phase 2 codegen reconnaissance — identified `_start` empty-body and `IR_PRINT` no-op |
| 36 | 2026-05-20 | First codegen cut — `IR_PRINT` direct `call` to `serial_puts`; handwritten kernel symbol export `bare-kernel/kernel-symbols.json` |
| 37 | 2026-05-20 | **Root cause: IR-LowerStmt array-wrapper bug** — `p_block` returned `,$stmts` (single-element wrapper); IR-Lower iterated once and dropped tail statements. Fix: `IR-StmtBody` helper unwraps the `[wrapper [ArrayList]]` shape. IR ×9.4, live IR ×12.6, x86 .text ×3.6, kernel.bin 110 KB → 386 KB. |
| 38 | 2026-05-20 | String-literal pool + `abs64` reloc kind. `IR_STR_CONST` now emits `mov reg, imm64 0` placeholder + per-module `__str$<mod>$<idx>` symbol; Pass-2 appends UTF-8 string pools. +61 symbols, +61 abs64 relocs, kernel.bin 386 → 388 KB. |

Open thread: `_ke_putc(int)` calling-convention / `IR_PARAM` lowering — to be addressed in Sprint 39.

## GUI Initiative (Sprint G1, scaffolding)

Parallel to the codegen sprints, Sprint G1 stands up the scaffolding to evolve HicOS from a serial-console OS to a Windows-11-Fluent-style adaptive graphical OS. 47 modules added under `bare-kernel/hl/`, organized into the Layer 0–7 stack defined in [`GUI_DESIGN.md`](GUI_DESIGN.md):

- **Graphics (L0–2)**: `gfx_backbuffer`, `gfx_aa`, `gfx_path`, `gfx_blur`, `gfx_shadow`, `gfx_anim`, `gfx_hidpi`, `compositor`, `font_atlas`
- **Window manager (L3)**: `wm_snap`, `vdesktop`, `mission_control`, `display_topology`
- **Widget toolkit (L4)**: `widget_core`, `widget_button`, `widget_input`, `widget_select`, `widget_list`, `widget_nav`, `widget_container`, `widget_feedback`
- **Adaptive layout (L5)**: `adaptive_layout`
- **Shell (L6)**: `shell_topbar`, `shell_dock`, `shell_startmenu`, `shell_spotlight`, `shell_controlcenter`, `shell_notification`, `shell_lockscreen`, `shell_wallpaper`, `shell_themes`, `shell_form`
- **Apps (L7)**: `app_files`, `app_settings`, `app_terminal`, `app_texteditor`, `app_sysmon`
- **Input**: `input_pointer`, `input_gesture`, `input_touch`, `input_pen`
- **Services**: `dnd`, `ime`, `a11y`, `eyecare`, `anim_tuning`, `visual_audit`

Three new audit scripts (`scripts/gui-lex-audit.ps1`, `gui-ast-audit.ps1`, `gui-symbol-audit.ps1`) gate GUI-module quality.

## Verification

All gates pass on the current baseline:

- `hl-bootstrap-build-test.ps1` — full toolchain build + self-test
- `full-gate.ps1` — workspace + runtime + release validation
- `release-validate.ps1` — 18/18 release checks
- `qemu-smoke.ps1` — automated boot smoke test
- `qemu-visual-test.ps1` — interactive serial-console boot (10/10 stable)

## Milestone Summary

| Milestone | Iteration | Achievement |
|---|---|---|
| M1 | 360 | Competition-grade algorithm library (300+ algorithms, Shell >1,200) |
| M2 | 375 | Self-hosting compiler (HM type inference + optimization passes + full linker) |
| M3 | 385 | Storage engine (B+Tree + WAL + MVCC + relational DB) |
| M4 | 405 | ML framework (CNN + RNN + LSTM + Transformer + autograd) |
| M5 | 420 | Production stability (CFS + NUMA + hotpatch + crash report + hypervisor) |
| M6 | 440 | Full ecosystem (package manager + LSP + debugger + POSIX + WASM, Shell 1,800) |
