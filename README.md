# HicOS

A bare-metal experimental x86_64 operating system written entirely in **Hilbert-Lang (H-L)**, a self-designed language. Zero external dependencies — no C, no Rust, no JSON/YAML/npm. The toolchain (compiler, linker, interpreter) is self-hosted in H-L; the kernel modules are H-L; only the boot image emitter (`scripts/rebuild-image.ps1`) is PowerShell raw machine code.

Boots on QEMU (BIOS + UEFI), runs a serial-console shell with 1,800+ commands.

---

## Snapshot

| Metric | Value |
|---|---:|
| Total `.hl` files | **539** |
| Kernel modules (`bare-kernel/hl/`) | **470** |
| Shell commands | **1,800** |
| H-L total LOC | **~165,000** |
| External dependencies | **0** |
| Boot image (BIOS, `hicos-hl.img`) | 58,368 B (114 sectors) |
| Boot image (UEFI, `hicos-uefi.img`) | 34,603,008 B |
| QEMU boot stability (10 runs) | **10/10 boot complete** |
| Milestones M1–M6 | All ✦ achieved |
| Bug-fix sprints | **1–31** |
| GUI scaffolding sprint | **G1** (47 modules added, see [GUI_DESIGN.md](GUI_DESIGN.md)) |
| Codegen sprints | **35–38** (string-pool / abs64 reloc / IR-Lower fix) |

## Milestones

- **M1** (iter 360) Competition-grade algorithm library (300+ algorithms)
- **M2** (iter 375) Self-hosting compiler (HM type inference + ELF linker)
- **M3** (iter 385) Storage engine (B+Tree, WAL, MVCC, query plan)
- **M4** (iter 405) ML inference framework (CNN, RNN/LSTM, Transformer, autograd)
- **M5** (iter 420) Production stability (CFS, NUMA, hotpatch, hypervisor/VMX)
- **M6** (iter 440) Ecosystem (package manager, LSP, debugger, POSIX shim, WASM JIT)

---

## Build & Run

### Build the BIOS image

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\rebuild-image.ps1
```

Produces `hicos-hl.img` (~58 KB).

### Boot in QEMU (serial console, recommended)

HicOS is a **serial-console OS** — the framebuffer is initialized via VBE but the shell renders on serial only. Use `-display none` and route the shell to stdio:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\qemu-visual-test.ps1
```

Or directly:

```bash
qemu-system-x86_64 \
  -drive format=raw,file=hicos-hl.img \
  -device virtio-blk-pci,drive=disk0,disable-modern=on \
  -drive id=disk0,file=hicos-disk.img,format=raw,if=none \
  -m 128 -serial stdio -display none -no-reboot -no-shutdown
```

Press `Ctrl+A X` to quit QEMU.

### Other entry points

```powershell
.\hl-bootstrap.cmd test                              # build + run H-L self-tests
.\scripts\full-gate.ps1                              # full validation gate
.\scripts\release-validate.ps1                       # 18-point release checklist
.\scripts\qemu-smoke.ps1                             # automated boot smoke test
```

---

## Repository Layout

```
HicOS/
├─ bare-kernel/hl/        # 470 kernel modules (~140,000 lines of H-L, incl. 47 new GUI modules)
├─ scripts/               # 32 PowerShell build/test/QEMU/audit scripts
├─ IP-Protection/         # IP / patent documentation
├─ hl-bootstrap.hl        # self-hosting compiler (4,572 lines, 208 fn)
├─ stdlib.hl              # H-L standard library (1,545 lines, 143 fn)
├─ manifest.hl            # single source of truth for project metadata
├─ HicOS_*.hl             # 27 high-level subsystem modules
├─ hicos-hl.img           # BIOS boot image (raw, 114 sectors)
├─ hicos-uefi.img         # UEFI boot image (GPT + ESP + BOOTX64.EFI)
├─ README.md              # this file
├─ ARCHITECTURE.md        # three-layer architecture + boot chain
├─ HILBERT_LANG_BNF.md    # H-L grammar specification
├─ GUI_DESIGN.md          # Win11 Fluent GUI design + multi-form-factor plan
└─ CHANGELOG.md           # iteration & sprint history
```

---

## Kernel Capability Surface

### Platform

- **Console**: serial COM1 (38400 8N1) + VGA text fallback
- **Hardware**: PIC/PIT/IDT/LAPIC, SMP (INIT-SIPI-SIPI), PS/2 keyboard, PCI scan
- **Storage**: VirtIO-blk (legacy), AHCI, NVMe, USB, ATA PIO
- **Display**: VBE 1024×768×32 LFB
- **Memory**: buddy allocator + size-class freelist, demand paging + COW, swap, block cache, NUMA allocator
- **Scheduling**: MLFQ (4 priority bands), CFS, SMP per-CPU runqueues
- **Isolation**: futex / epoll (edge-triggered) / cgroup / seccomp / namespaces / container runtime
- **Observability**: ftrace, kprobe, memory profiler, heap checker, crash reporter, core dump (ELF)
- **Live update**: hotpatch (trampolines), livepatch (function-level swap)
- **Virtualization**: hypervisor framework, VMX/VT-x support

### File Systems

FAT16, ext2/ext4, NTFS, VFS, devfs, procfs, sysfs, ramfs, tmpfs, OverlayFS, iNotify, block cache, B-Tree index, WAL, MVCC.

### Network Stack

| Layer | Protocols |
|---|---|
| L2 | Ethernet, ARP, VLAN |
| L3 | IPv4, IPv6, ICMP |
| L4 | TCP (Reno), UDP |
| L7 | HTTP/1.1/2/3, WebSocket, TLS 1.3, QUIC, DNS/DoH, DHCP, NTP, SMTP, POP3, IMAP, FTP, IRC, MQTT, SIP, RTSP, RTP, STUN, SOCKS5, LDAP, RADIUS, gRPC, WireGuard |

### Crypto

AES-GCM, ChaCha20-Poly1305, SM4 · RSA, Ed25519, Curve25519 · SHA-256, SM3, BLAKE2, xxHash, SipHash · HMAC, PBKDF2, scrypt, Argon2, bcrypt · X.509, PEM, JWT, ASN.1 DER · RDRAND + timer-jitter entropy.

### Algorithm Library (~180 modules)

Data structures (Treap/Splay/LCT/Skip List/Bloom/HLL/CMS/Cuckoo/t-Digest), graph (Dijkstra/Dinic/Tarjan/Hopcroft-Karp/Hungarian), string (KMP/SAM/Manacher/Eertree/BWT/Aho-Corasick), math (Miller-Rabin/Pollard-Rho/NTT/poly), geometry (convex hull/rotating calipers/half-plane intersection), DP (bitmask/digit/broken-profile/Knuth/divide-and-conquer).

### Machine Learning

conv2d + pooling, RNN + LSTM, Transformer (multi-head self-attention, sinusoidal positional encoding, layer norm, FFN), autograd, SGD/Adam, BPE tokenizer, embedding, model serialization, GPU inference path.

### Compiler Toolchain

x86_64 native backend (126 instructions), IR + SSA (37 opcodes), linear-scan register allocator, GVN/LICM/DCE passes, full type system (Hindley-Milner inference, generics monomorphization), ELF64 linker, DWARF debug info, JIT stub.

### Storage Engine

B-Tree, B+Tree, LSM memtable, WAL, MVCC, transaction API, hash + B-Tree indexes, query planner — a complete relational engine.

### Ecosystem (Phase 7)

Package manager (install/remove/registry), build system, doc generator, unit-test + benchmark frameworks, LSP server, syntax highlighter, code completion, debugger + GDB remote stub, H-L REPL, formatter, lint, POSIX compat layer, musl libc shim, Linux syscall layer, WASM MVP interpreter + JIT.

---

## QEMU Stress Test Status

Sprint 26–31 ran six rounds of QEMU stress testing. Across 10 boot iterations on the current image:

| Subsystem | Pass rate |
|---|---:|
| Serial / PIC / PIT / IDT / PS-2 scancode / Timer | 10/10 |
| PCI scan / VirtIO-blk init / VirtIO-net init | 10/10 |
| Memory / VESA / SYSCALL / Module loading | 10/10 |
| Boot Complete | **10/10** |
| Scheduler heartbeat (task A↔B alternation) | 10/10 |
| Disk write+readback verify | 9/10 (see note) |

> **Note**: 1/10 disk-write failure is a known, non-blocking diagnostic flake from QEMU host-side virtio used-ring vs. status-byte timing. `xxd` independently confirms the data was written correctly. Documented under Sprint 31 in `CHANGELOG.md`.

No PANIC / page fault / triple-fault across all 10 runs.

---

## Technical Highlights

- **Zero external dependencies.** No C, no Rust, no third-party crates. The PowerShell scripts only emit raw machine code for the MBR / Stage 2 bootloader.
- **Self-hosting.** Compiler, linker, interpreter, REPL, formatter, lint, debugger — all written in H-L.
- **Bare metal.** Runs directly on x86_64, BIOS and UEFI dual-boot.
- **Modular.** 470 kernel modules, each ~300–500 lines, single-responsibility.
- **Three-layer architecture.** Image build (Layer A) → bootstrap toolchain (Layer B) → kernel modules (Layer C). See `ARCHITECTURE.md`.

## GUI Initiative (Sprint G1, in progress)

Sprint G1 lays the scaffolding for evolving HicOS from a serial-console OS to a Windows-11-Fluent-style adaptive graphical OS (desktop / laptop / tablet / mobile / kiosk form factors, multi-display, touch + pen + mouse + keyboard).

47 new modules added under `bare-kernel/hl/`, organized into:

| Tier | Modules |
|---|---|
| Graphics (Layer 0–2) | `gfx_backbuffer`, `gfx_aa`, `gfx_path`, `gfx_blur`, `gfx_shadow`, `gfx_anim`, `gfx_hidpi`, `compositor`, `font_atlas` |
| Window manager (Layer 3) | `wm_snap`, `vdesktop`, `mission_control`, `display_topology` |
| Widget toolkit (Layer 4) | `widget_core`, `widget_button`, `widget_input`, `widget_select`, `widget_list`, `widget_nav`, `widget_container`, `widget_feedback` |
| Adaptive layout (Layer 5) | `adaptive_layout` |
| Shell (Layer 6) | `shell_topbar`, `shell_dock`, `shell_startmenu`, `shell_spotlight`, `shell_controlcenter`, `shell_notification`, `shell_lockscreen`, `shell_wallpaper`, `shell_themes`, `shell_form` |
| Apps (Layer 7) | `app_files`, `app_settings`, `app_terminal`, `app_texteditor`, `app_sysmon` |
| Input | `input_pointer`, `input_gesture`, `input_touch`, `input_pen` |
| Services | `dnd`, `ime`, `a11y`, `eyecare`, `anim_tuning`, `visual_audit` |

3 new audit scripts under `scripts/`: `gui-lex-audit.ps1`, `gui-ast-audit.ps1`, `gui-symbol-audit.ps1`.

See [`GUI_DESIGN.md`](GUI_DESIGN.md) for full design (Mica/Acrylic, eye-care LUT, breakpoint grid, density tiers, gesture model).

## Related Documents

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — three-layer architecture, boot chain, milestone history.
- [`HILBERT_LANG_BNF.md`](HILBERT_LANG_BNF.md) — H-L grammar specification.
- [`GUI_DESIGN.md`](GUI_DESIGN.md) — Win11 Fluent GUI design + multi-form-factor plan.
- [`CHANGELOG.md`](CHANGELOG.md) — iteration log + Sprint 1–38 history (bug-fix + codegen + GUI scaffold).

## License

Educational and research use. All source code is written in self-designed Hilbert-Lang.
