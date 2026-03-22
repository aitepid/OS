# HicOS Changelog

## Current Snapshot

- 活跃 `.hl` 文件：`176`
- 内核模块：`114`
- 构建/测试主入口：`scripts/hl-bootstrap-build-test.ps1`
- 本轮已复核：`hl-bootstrap-build-test`、`boot-readiness`、`runtime-path-readiness`、`image-layout-readiness`、`release-validate`

## Iteration 74 — POSIX Signal Handling

- `kernel_entry.hl` 增加信号位掩码与发送逻辑
- 新增：
  - `_ke_sig_bit(signum)`
  - `_ke_signal_send(tid, signum)`
  - `_ke_signal_pending(tid)`
  - `_ke_signal_block(tid, signum)`
  - `_ke_signal_unblock(tid, signum)`
  - `_ke_signal_deliver(tid)`
  - `_ke_sig_name(signum)`
  - `_ke_cmd_kill(buf_addr, buf_len)`
- `kill <pid> [sig]` 接入 `kernel.bin` 命令分发
- `ps` 输出增加信号相关信息
- `shell.hl` 中 `kill` 默认改为发送 `SIGTERM`

## Iteration 73 — Environment Variables + echo

- 新增环境变量初始化与查找/设置逻辑
- 接入 `env` / `setenv` / `echo`
- `_start()` 中增加环境初始化阶段
- `kernel.bin` 命令分发补齐 `adduser` / `service` / `wifi` / `msg`

## Documentation Sync

本轮同时清理并重写：
- `README.md`
- `ARCHITECTURE.md`
- `ROADMAP.md`
- `PROJECT_STATUS.md`
- `THREE_SYSTEM_COMPARISON.md`
- `FIVE_OS_COMPARISON.md`
- `PROJECT_ADVANCEMENT_PLAN.hl`

原则：
- 删除乱码与失真统计
- 删除未经本轮复核的“最新通过”口径
- 统一为当前仓库可证明状态





