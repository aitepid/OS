# HicOS Architecture

## Overview

HicOS is no longer a single-layer execution OS; it has evolved into a three-layer system:

| Layer | Medium | Current Role |
|---|---|---|
| A | `scripts/rebuild-image.ps1` → `hicos-hl.img` | Generates and maintains the current bootable BIOS image path |
| B | `hl-bootstrap.hl` | Bootstraps the compiler, interpreter, and the image/compiler toolchain source |
| C | `bare-kernel/hl/*.hl` | Contains the kernel source, module logic, and `kernel.bin` compilation inputs |

These layers have merged but not completely vanished as a single path:
- Image construction still relies on `rebuild-image.ps1`
- The compilation entry point now prioritizes `hl-bootstrap-build-test.ps1`
- `kernel.bin` is integrated into the imaging process and its functionality is continually being expanded

## Boot Chain

### BIOS Path

```text
stage1 / MBR
→ stage2
→ long mode
→ handwritten/bootstrap-assisted kernel path
→ CALL kernel.bin _start
→ kernel_entry.hl
→ shell / subsystem commands
```

### UEFI Path

```text
OVMF
→ GPT + ESP
→ BOOTX64.EFI
→ UEFI启动输出与镜像链路验证
```

## Current Key Source Locations

- `bare-kernel/hl/kernel_entry.hl`
  - `_start`
  - Interrupt initialization
  - Command dispatch for `kernel.bin`
  - Recently integrated environment variable and signal handling commands
- `bare-kernel/hl/kernel_init.hl`
  - Layer C initialization sequence definitions
- `bare-kernel/hl/shell.hl`
  - Layer C serial Shell, currently with `56` commands as per comments
- `scripts/hl-compile-pipeline.ps1`
  - Current H-L compilation pipeline script entry
- `scripts/rebuild-image.ps1`
  - BIOS image rebuilder
- `scripts/hl-bootstrap-build-test.ps1`
  - Currently recommended unified build/verification entry point

## Recently Confirmed Architectural Facts

- The `kill` command in `shell.hl` has switched to signal semantics
- `kernel_entry.hl` has incorporated iterations 73/74:
  - Environment variables: `env` / `setenv` / `echo`
  - Signal handling: `kill`, pending/blocked bitmask, enhanced `ps` signal list
- Current codebase size:
  - `176` active `.hl` files
  - `114` kernel modules
  - `19` `scripts/*.ps1` files

## Verification Criteria

This document synchronization only retains the conclusions that have been reviewed in this round:
- `hl-bootstrap-build-test.ps1` passed
- `boot-readiness.ps1` passed
- `runtime-path-readiness.ps1` passed
- `image-layout-readiness.ps1` passed
- `release-validate.ps1` passed

Historical data that has not been completely re-verified in this round will no longer be presented as "latest facts" in this document.
