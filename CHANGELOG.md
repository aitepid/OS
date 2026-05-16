# HicOS Changelog

## Current Snapshot

- `.hl` 文件：`226`（69 根目录 + 157 内核模块）
- H-L 总行数：`~67,000`
- 内核模块：`157`
- Shell 命令：`223`
- 最近完成功能迭代：`171`（sqlite + diff + ui_clock）

## Iteration 171 — ui_clock.hl：数字时钟小部件

- **`bare-kernel/hl/ui_clock.hl`** 新增（~230 行）
  - 浮动窗口 200×80，右上角定位（UICLOCK_X=984，UICLOCK_Y=40）
  - 大字 HH:MM:SS 时间行（`ntp_get_time()` → `_uiclock_decode`）+ 日期行 YYYY-MM-DD
  - 状态栏：`[h]24h` 切换 + 闹钟显示
  - 'h' 键切换 12h/24h 模式；Esc 关闭
  - `uiclock_tick()` 由 wm compositor 每帧调用，秒变化时自动 redraw
  - `uiclock_set_alarm(h, m)`：整点触发 `notify_show` + klog
  - `_uiclock_decode(unix)`：unix 时间戳 → [y,m,d,h,min,sec]，完整闰年支持
- **`bare-kernel/hl/wm.hl`** 接入：draw+tick / key / click
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 12 号图标 `UIDSK_APP_CLOCK`，标签 "Clock"
- **`bare-kernel/hl/shell.hl`** 新增 4 条命令：
  - `clock` / `clock close` / `clock time` / `clock alarm <HH> <MM>`

## Iteration 170 — diff.hl：LCS 统一差异算法

- **`bare-kernel/hl/diff.hl`** 新增（~280 行）
  - LCS 动态规划（128×128 表，16KB，展平 1-D HL 数组）
  - 反向追踪生成编辑序列（" " context / "-" remove / "+" add）
  - 分块输出：`@@ -A,B +C,D @@` hunk 格式，3 行上下文
  - DIFF_BUF_A=0xDFA000（64 KB）+ DIFF_BUF_B=0xE0A000（64 KB）读文件缓冲
  - 每文件最多 128 行（`DIFF_MAX_LINES`）
  - `diff_files(path_a, path_b)` / `diff_strings(a, b)` / `diff_stat(a, b)`
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`diff_init()`
- **`bare-kernel/hl/shell.hl`** 新增 3 条命令：
  - `diff <pathA> <pathB>` / `diffstat <pathA> <pathB>` / `diffstr <textA> <textB>`

## Iteration 169 — sqlite.hl：嵌入式内存关系数据库

- **`bare-kernel/hl/sqlite.hl`** 新增（~300 行）
  - DB_MAX_TABLES=8；并行平坦数组（db_active/names/schemas/data/counts）
  - 行格式：Tab 分隔字段；行间换行符分隔
  - `_db_split(s, delim)` 通用字符串分割 → HL 数组
  - `_db_col_idx(schema, col)` / `_db_row_val(row, idx)` 字段定位
  - 完整 CRUD：`db_create` / `db_drop` / `db_insert` / `db_select_all`
    / `db_select_where` / `db_delete_where` / `db_update_where`
    / `db_count` / `db_schema` / `db_list`
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`db_init()`
- **`bare-kernel/hl/shell.hl`** 新增 9 条命令：
  - `db list` / `db create <name> <schema>` / `db insert <name> <row>`
  - `db select <name>` / `db where <name> <col> <val>`
  - `db delete <name> <col> <val>` / `db drop <name>` / `db schema <name>` / `db count <name>`



- **`bare-kernel/hl/compress.hl`** 新增（~260 行）
  - 双算法：RLE（逃逸字节 0xFF）+ LZSS（256 字节滑动窗口）
  - 缓冲区：COMP_IN_BUF=0xDE8000（64 KB）+ COMP_OUT_BUF=0xDF8000（64 KB）
  - RLE：run ≥ 3 时编码为 `0xFF count byte`；0xFF 字面量编码为 `0xFF 0xFF`
  - LZSS：每 8 个 token 一个 flag 字节；bit=0=literal，bit=1=back-ref（offset u8 + length u8）
  - `compress_stat(path)`：统计原始大小 + RLE 估计压缩率
  - `_comp_read_file/write_file`：VFS I/O 封装
- **`bare-kernel/hl/shell.hl`** 新增 3 条命令：
  - `compress <rle|lz> <src> <dst>` / `decompress <rle|lz> <src> <dst>` / `compstat <path>`

## Iteration 167 — ui_calendar.hl：月历应用

- **`bare-kernel/hl/ui_calendar.hl`** 新增（~310 行）
  - 440×380 窗口，7 列 × 6 行网格（Zeller 公式计算首日星期）
  - 工具栏：← Prev | 月名年份 | Next →
  - 今日高亮（accent 色，由 `ntp_get_time()` 获取）
  - 事件存储：最多 32 条（day/month/year/text），有事件日期显示小圆点
  - 点击日期格 → 选中；底部面板显示当天事件列表
  - 键盘：Esc=关闭，←/→=换月，'t'=跳回今日
  - 闰年支持（4/100/400 规则）；`_uical_dow_first` 用 Zeller 变换
- **`bare-kernel/hl/wm.hl`** 接入：draw / key / click
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 11 号图标 `UIDSK_APP_CALENDAR`，标签 "Cal"
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `calendar` / `cal` / `cal next` / `cal prev` / `cal today`
  - `cal add <day> <text>` / `cal goto <month> <year>`

## Iteration 166 — irc.hl：IRC 客户端（RFC 1459）

- **`bare-kernel/hl/irc.hl`** 新增（~230 行）
  - IRC_MAX=4 并发会话，默认端口 6667
  - 5 个会话状态：FREE → CONN → REGISTERED → JOINED → ERR
  - IRC 消息解析器：`_irc_get_command/trailing/params` + `_irc_prefix_nick`
  - 自动响应 PING：检测到 `PING` 立即发送 `PONG :<server>`
  - 001 响应 → 状态升级至 REGISTERED
  - PRIVMSG 接收 → 格式化 `<nick> text` 并写入 `irc_last_msg[id]` + klog
  - JOIN 确认 → 状态升级至 JOINED，记录频道名
  - `_irc_process_resp` 按 `\r\n` 分割多行批量处理
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`irc_init()`
- **`bare-kernel/hl/shell.hl`** 新增 7 条命令：
  - `irc` / `irc connect <host> [port]` / `irc reg <id> <nick> <user>`
  - `irc join <id> <#chan>` / `irc say <id> <target> <msg>` / `irc recv <id>`
  - `irc part <id>` / `irc quit <id>` / `irc status <id>`



## Iteration 165 — pop3.hl：POP3 邮件接收客户端（RFC 1939）

- **`bare-kernel/hl/pop3.hl`** 新增（~220 行）
  - POP3_MAX=4 并发会话，POP3_BUF=0xDE0000（8 KB/会话响应缓冲）
  - 6 个会话状态：FREE → CONN → AUTH → READY → BUSY → ERR
  - `pop3_connect(host, port)`：DNS 解析 + TCP 连接
  - `pop3_auth(id, user, pass)`：USER + PASS 命令序列
  - `pop3_stat(id)` → `[count, total_bytes]`：解析 "+OK N M" 响应
  - `pop3_list(id)`：LIST 命令 → 邮件编号+大小列表
  - `pop3_retr(id, n)`：RETR n → 剥离 "+OK" 前缀 + ".\r\n" 尾
  - `pop3_dele(id, n)`：DELE 标记删除
  - `pop3_tick()`：轮询待处理响应，错误写入 klog(WARN)
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`pop3_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `pop3` / `pop3 connect <host> <port>` / `pop3 auth <id> <user> <pass>`
  - `pop3 list <id>` / `pop3 get <id> <n>` / `pop3 quit <id>`

## Iteration 164 — ui_hexedit.hl：十六进制编辑器

- **`bare-kernel/hl/ui_hexedit.hl`** 新增（~320 行）
  - 620×440 窗口，22 行 × 16 字节/行 = 352 字节可见
  - 布局：8 位偏移 | 16 对十六进制 | 16 字符 ASCII 列
  - VFS 文件加载：4 KB 页面至 HEXED_BUF=0xDD0400
  - 导航：方向键（±1 字节）/ PgUp/PgDn（±352 字节）/ Home/End（行首/尾）
  - 编辑模式：Tab 切换 view/edit；半字节输入（高/低 nibble）；Ctrl+S 保存到 VFS
  - 工具栏：Open / Save / Close / Edit（active 高亮）；未保存指示
  - 点击内容区：按行列坐标移动光标
- **`bare-kernel/hl/wm.hl`** 接入：draw / key / click
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 10 号图标 `UIDSK_APP_HEXEDIT`，标签 "Hex"
- **`bare-kernel/hl/shell.hl`** 新增 2 条命令：`hexedit` / `hexedit <path>`

## Iteration 163 — ntp.hl 完整实现 + tar.hl：TAR 归档读取

- **`bare-kernel/hl/ntp.hl`** 升级（stub → 完整 SNTP 实现）
  - 删除注释存根，改用 HL 字节数组构建 48 字节 NTP 请求
  - `_ntp_build_request()`：LI=0, VN=4, Mode=3 → 0x23 + 44 字节零
  - `ntp_on_recv(data)`：UDP 回调，设置 `ntp_resp_ready + ntp_resp_data`
  - `ntp_sync(host)`：dns_resolve → udp_bind → udp_send → 轮询回调 → 解析 offset 40 大端 u32
  - `ntp_format_time(unix)`：Unix 时间戳 → "YYYY-MM-DD HH:MM:SS"（含闰年处理）
  - `ntp_get_time()`：`last_unix + (get_ticks() - last_tick) / 100`
- **`bare-kernel/hl/tar.hl`** 新增（~260 行）
  - POSIX ustar 格式；512 字节块；一次读取一块（VFS + TAR_BUF=0xDD0000）
  - `_tar_oct(addr, len)`：八进制 ASCII 字段解析
  - `_tar_is_ustar(addr)`：验证 offset 257 "ustar" 魔数
  - `_tar_fullname(addr)`：合并 prefix[155] + "/" + name[100]
  - `tar_list(path)` / `tar_cat(tar_path, filename)` / `tar_extract(tar_path, dest)` / `tar_info(path)`
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`ntp_init()`（已含 pop3_init）
- **`bare-kernel/hl/shell.hl`** 新增 3+4=7 条命令：
  - `ntp sync <host>` / `ntp time` / `ntp status`
  - `tar list <path>` / `tar cat <path> <file>` / `tar extract <path> <dest>` / `tar info <path>`



## Iteration 162 — ui_image.hl：BMP 图像查看器

- **`bare-kernel/hl/ui_image.hl`** 新增（~343 行）
  - 480×380 图形窗口，图像区 448×320，工具栏 32px，状态栏 16px
  - BMP 格式解析：小端 u16/u32/i32 读取；"BM" 签名校验；仅支持 24/32-bit 无压缩
  - 行 stride = `ceil(bpp*width/32)*4`；正 height → 底部优先行顺序
  - `_bmp_pixel(x,y)` 返回 0xFFRRGGBB；zoom=1 → `vesa_putpixel`，zoom=2 → `vesa_fill_rect` 2×2
  - 加载缓冲：UIIMG_LOAD_BUF=0x9D0000（4 MB），通过 `vfs_read` 一次性读入
  - 工具栏按钮：Open / Close / 1x（active 高亮）/ 2x（active 高亮）
  - 键盘：Esc=关闭，'1'=1x zoom，'2'=2x zoom
  - 公开 API：`uiimg_open/close/draw/key/click/load/is_open`
- **`bare-kernel/hl/wm.hl`** 接入：`wm_draw_all` + `wm_key_dispatch` + `wm_mouse_click`
- **`bare-kernel/hl/ui_desktop.hl`** dock 第 9 号图标 `UIDSK_APP_IMAGE`，标签 "Img"
- **`bare-kernel/hl/shell.hl`** 新增 2 条命令：
  - `imgview <path.bmp>`：打开查看器并加载 BMP
  - `imgview zoom <1|2>`：切换缩放级别

## Iteration 161 — cron.hl：内核定时任务调度器

- **`bare-kernel/hl/cron.hl`** 新增（~220 行）
  - CRON_MAX=16 槽位，100 Hz tick 时间基准（interval_secs × 100 = ticks）
  - 每槽位 7 个状态数组：active / enabled / repeat / interval / next / cmd / fire_cnt
  - `cron_tick()`：遍历所有槽位，`get_ticks() >= cron_next[i]` 时调用 `shell_handle(cmd)`
  - 一次性任务：触发后自动移除；周期任务：重新设定 `now + interval`
  - `cron_setup_system_jobs()`：注册 4 个系统任务（date 30s / dmesg 60s / ws tick 120s / telnet tick 60s）
  - 便捷包装：`cron_add_secs(cmd, secs, repeat)` → `cron_add(cmd, secs*100, repeat)`
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`cron_init()` + `cron_setup_system_jobs()`
- **`bare-kernel/hl/shell.hl`** 新增 6 条命令：
  - `cron` / `cron add <secs> <cmd>` / `cron once <secs> <cmd>`
  - `cron rm <id>` / `cron en <id>` / `cron dis <id>`

## Iteration 160 — smtp.hl：SMTP 邮件客户端（RFC 5321）

- **`bare-kernel/hl/smtp.hl`** 新增（~257 行）
  - SMTP_MAX=4 并发会话，SMTP_BUF=0x9C0000（16 KB 响应缓冲）
  - 9 个会话状态：FREE→CONN→READY→AUTH→MAIL→RCPT→DATA→DONE→ERR
  - `smtp_b64_encode(s)`：三字节组 → 6-bit 索引 → BASE64 字符，支持 = 填充
  - `smtp_send_email(id,from,to,subj,body)`：完整 MAIL FROM + RCPT TO + DATA + RFC 5322 头 + body + `\r\n.\r\n`
  - `smtp_auth(id,user,pass)`：AUTH LOGIN + base64 用户名/密码
  - `smtp_tick()`：轮询 TCB RX 缓冲，响应码 ≥500 时写入 klog(ERROR)
  - `smtp_status/list`：格式化会话状态字符串
- **`bare-kernel/hl/kernel_init.hl`** Phase 7：`smtp_init()`
- **`bare-kernel/hl/shell.hl`** 新增 5 条命令：
  - `smtp` / `smtp connect <host> <port>` / `smtp auth <id> <user> <pass>`
  - `smtp send <id> <from> <to> <subj> <body>` / `smtp quit <id>`


- H-L 总行数：`~47,800`（根 10,044 + 内核 ~37,756）
- 内核模块：`130`（编译产出 1,700+ 函数 / 2,003+ 符号）
- `kernel_entry.hl`：`9,428` 行
- `hl-bootstrap.hl`：`4,306` 行，`208` 函数
- `stdlib.hl`：`1,385` 行，`143` 函数
- `kinterp.hl`：`~1,280` 行
- Shell 命令（`shell.hl` if cmd ==）：`75`
- `scripts/*.ps1`：`28`（9,729 行）
- 构建/测试主入口：`hl-bootstrap.cmd test`
- 最近完成功能迭代：`133`（ext4真实读路径 + GPU桥接 + 词法器修复 + 字体光标）

## Iteration 140 — kernel_init修正+signal集成+mmap真实分发+WM启动终端窗口+sched_tick

- **`kernel_init.hl`**: 全面修正 + 新增初始化
  - 模块计数 130→132
  - Phase 2: `mmap_init()` 新增（demand paging COW mmap）
  - Phase 4: `mlfq_init()` + `signal_init_subsystem()` 新增（MLFQ调度器 + 信号子系统）
  - Phase 6: `wm_init()` 新增（窗口管理器 + 桌面chrome）
  - Phase 9: `syscall_msr_setup(0)` 新增（STAR/LSTAR/FMASK MSR配置）
  - 汇总字符串 130→132
  - 启动后: `wm_open_terminal_window()` 打开图形终端窗口
- **`signal.hl`**: 新增两个关键函数
  - `signal_init_subsystem()`: 清零 64*512=32768 字节处理器表
  - `signal_check_task(task_idx)`: 调度tick调用，处理SIGKILL/SIGTERM默认行为
- **`syscall.hl`**: 修复 + 新增
  - `SYS_MMAP(16)`: 从 `page_alloc()` 改为 `sys_mmap()` (lazy, COW-capable)
  - `SYS_MUNMAP(17)`: 改为 `sys_munmap()` (properly frees region table entry)
  - 新增: `SYS_MPROTECT(19)` → `sys_mprotect()`
  - 新增: `SYS_SIGNAL(85)/SYS_SIGRETURN(86)/SYS_SIGBLOCK(87)/SYS_SIGUNBLOCK(88)`
- **`sched.hl`**: 新增 `sched_tick(task_idx)`
  - 调用 `mlfq_tick` → 按需 `mlfq_demote`
  - 调用 `mlfq_check_boost`
  - 调用 `signal_check_task` — 信号与调度器集成
- **`wm.hl`**: 新增 `wm_open_terminal_window()`
  - 在桌面顶栏下方创建 640×400 终端窗口
  - 调用 `uiterm_open()` 并初始渲染



- **`syscall.hl`**: 全面增强系统调用分发
  - `SYS_WRITE(33)`: fd=1/2→serial; fd>2→`vfs_write(fd, str, len)`
  - `SYS_READ(32)`: fd=0→键盘中断; fd>0→`vfs_read(fd, buf, len)`
  - 新增: `SYS_LSEEK(62)`→`vfs_seek`, `SYS_FSTAT(63)`→fd表stat写入用户缓冲
  - 新增: `SYS_SOCKET(68)/SYS_BIND/SYS_CONNECT/SYS_ACCEPT/SYS_SENDTO/SYS_RECVFROM` → socket.hl
  - 新增: `SYS_GETUID(10)/SYS_GETGID(11)/SYS_SETUID(12)` → current_uid/gid
  - 新增: `SYS_INOTIFY_INIT(90)/ADD_WATCH(91)/RM_WATCH(92)/READ(93)/CLOSE(94)` → inotify.hl
- **`pty.hl`**: 新增高层函数
  - `pty_exec_input(id)`: 从master-to-slave缓冲读取行, 调用`shell_handle_ext()`, 回写结果
  - `pty_open_pair()`: 分配PTY对并绑定当前任务, 返回 [mfd, sfd, id]
- **`kinterp.hl`**: 改进错误报告
  - `ki_call_fn()`: 参数数量不足时 `klog()` 警告（不再默默补0）
  - `ki_parse_primary()` 未知函数: `klog()` 记录函数名而非静默返回0
- **`shell.hl`**: 新增4条命令（87 total）
  - `pty`: 显示PTY状态
  - `pty alloc`: 分配新PTY对
  - `pty info <id>`: 显示指定PTY信息
  - help中 FS Events 行增加pty命令



- **`vfs.hl`**: inotify事件钩子接入
  - `vfs_open()`: 末尾调用 `inotify_emit(path, IN_OPEN=32, path)`
  - `vfs_write()`: 写入成功后调用 `inotify_emit(path, IN_MODIFY=2, path)`
  - `vfs_mkdir()`: 创建成功后调用 `inotify_emit(path, IN_CREATE=256, path)`
  - `vfs_unlink()`: 删除成功后调用 `inotify_emit(path, IN_DELETE=512, path)`
  - `vfs_mkdir`/`vfs_unlink` 重构为先计算再返回（捕获结果判断是否需要emit）
- **`kernel_init.hl`**: Phase 5 增加 `inotify_init_subsystem()` 调用
- **`kinterp.hl`** ki_call_builtin 新增17个内置函数:
  - `vfs_read(fd,buf,len)`, `vfs_write(fd,data,len)`, `vfs_seek(fd,off,whence)`
  - `klog(level,sub,msg)`, `pipe_create()`, `pipe_write/read/available`
  - `mem_copy(src,dst,len)`, `mem_read_string(addr,max)`, `mem_write_string(addr,s)`
  - `task_count()`, `task_count_active()`, `task_list_all()`
  - `random_u32()`, `serial_readline()`, `serial_readline_noecho()`
  - `inotify_emit(path,mask,name)`, `str_len(s)`
- **`shell.hl`**: 新增4条命令（83 total）
  - `echo <text> > <file>`: O_CREAT|O_WRONLY 打开文件，vfs_write写入，vfs_close
  - `inotify`: 显示 instances/watches/queued_events 计数
  - `watch <path>`: sys_inotify_init+add_watch, 10轮轮询输出事件
  - help 更新增 FS Events 行和echo重定向说明



- **`kinterp.hl`**: else-if死码清理
  - 删除错误的 `ki_pos = ki_pos - 1`（修改了错误变量）
  - 删除无用的 `tt2`/`tv2` 变量赋值
  - 递归 `ki_exec_stmt()` 直接复用已正确指向 "if" 的 `ki_tok_idx`
- **`syslog.hl`**: 修复 + 增强
  - `klog()`: `ticks` 未定义 → `get_ticks()`
  - `dmesg()`: 解除注释，读取真实日志条目（时间戳 + 级别 + 消息）
  - `syslog_init()`: 新增初始化函数（清空缓冲区 + 首条日志记录）
- **`serial.hl`**: 新增字符串行读取函数
  - `serial_readline()`: 阻塞读一行字符串（带回显）
  - `serial_readline_noecho()`: 阻塞读一行字符串（无回显，用于密码）
- **`login.hl`**: 修复 + 启用真实输入
  - `let attempts` → `let mut attempts`（修复不可变赋值 bug）
  - 启用 `serial_readline()` / `serial_readline_noecho()` 真实读取
- **`kernel_init.hl`**: 模块数 + 登录 + 新初始化
  - 模块计数 122 → 130
  - Phase 0 新增 `syslog_init()` 调用
  - Phase 7 新增 `netfilter_init()` 调用
  - Summary 后新增 `login_prompt()` → 验证用户再进 shell
- **`netfilter.hl` + `net.hl`**: 防火墙钩子集成
  - `net_input()`: 解析 src/dst IP + port，调用 `nf_match(NF_CHAIN_INPUT,...)`
  - DROP / REJECT 提前 return 0，丢弃数据包
  - TCP UDP ICMP 均受 netfilter 过滤保护
- **`shell.hl`**: 防火墙管理命令
  - `fw`: nf_status() 快速状态
  - `firewall`: 详细规则列表（链/端口/动作/命中次数）
  - `fw allow <port>`: INPUT ACCEPT tcp dport
  - `fw block <port>`: INPUT DROP tcp dport
  - `fw flush`: 重置所有规则
  - `fw policy input|output drop|accept`: 设置默认策略
  - help 新增 Firewall 行

## Iteration 136 — task/arp/tcp补全函数 + kinterp else-if链 + shell ps/proc/mount增强

- **`task.hl`**: 新增 `task_count_active()` / `task_name(idx)` / `task_list_all()`
  - `task_count_active()`: 统计非 FREE 任务数（用于 /proc/stat）
  - `task_name(idx)`: 从 name_ptr 读取任务名，回退为 "task<N>"
  - `task_list_all()`: 返回 [[pid, state_name, name], ...] 列表
- **`arp.hl`**: 新增 `arp_table_snapshot()`
  - 遍历 `_arp_valid[]` 数组，导出所有有效条目为 [ip_str, mac_str] 列表
  - IP 转点分十进制，MAC 转 hex colon 格式
- **`tcp.hl`**: 新增 `tcp_connections_summary()`
  - 扫描 TCP_TABLE，跳过 TCP_CLOSED，格式化为多行字符串
  - 含本地/远端 ip:port、状态名、cwnd 值
- **`kinterp.hl`**: 新增 else-if 链解析
  - `if cond { } else if cond { } else { }` 完整支持
  - 条件为真时循环跳过后续所有 else-if/else 分支
  - 条件为假时检测 `else if`，递归调用 `ki_exec_stmt()` 继续判断
- **`shell.hl`**: ps/mount/proc 命令增强
  - `ps`: 改用 `task_list_all()` 格式化 PID/STATE/NAME 表格
  - `mount`: 改用 `procfs_read("/proc/mounts")` 动态显示挂载点
  - `proc`: 无参数时 `vfs_readdir("/proc")` 列目录
  - `proc <arg>`: 读取 /proc/<arg> 或绝对路径

## Iteration 135 — procfs VFS集成 + shell管道 + terminal窗口渲染

- **`procfs.hl`**: 完整重写
  - `procfs_init()`: 调用 `vfs_mount_procfs("/proc")` 真实注册为 fs_type=4 挂载点
  - `procfs_read("/proc/version")`: 版本修正 → "HicOS 6.0 (130 modules)"
  - `procfs_read("/proc/meminfo")`: 改用 `page_count_free()` 动态查实时内存
  - `procfs_read("/proc/cpuinfo")`: 循环生成每 CPU 条目（支持 SMP）
  - `procfs_read("/proc/mounts")`: 遍历 VFS mount_count/MOUNT_TABLE 动态生成
  - `procfs_read("/proc/stat")`: 读 get_ticks() + task_count_active()
  - `procfs_read("/proc/net/arp")`: 调用 arp_table_snapshot() 真实 ARP 表
  - `procfs_read("/proc/net/tcp")`: 调用 tcp_connections_summary()
  - `procfs_read("/proc/<pid>/status")`: 解析 PID → task_addr() 查内存
- **`vfs.hl`**: procfs (fs_type=4) 全面集成
  - `vfs_mount_procfs(path)`: 新增挂载函数
  - `vfs_open()`: fs_type=4 分支存路径到 fd+48 供 read 使用
  - `vfs_read()`: fs_type=4 调用 procfs_read(stored_path) 返回内容
  - `vfs_stat()`: fs_type=4 区分目录(/proc, /proc/net, /proc/self)和文件
  - `vfs_readdir()`: fs_type=4 返回 /proc 静态目录列表 + /proc/net/ + /proc/self/
  - `vfs_mkdir/unlink`: fs_type=4 返回-1（只读）
- **`vesa.hl`**: 新增 `vesa_line_addr(y)` 返回扫描行起始字节地址（terminal滚动需要）
- **`terminal.hl`**: 取消所有注释，接入真实渲染
  - `term_init()`: 调用 `wm_create_window(50,50,w,h,"Terminal",0)` 创建真实窗口
  - `term_clear()`: `vesa_fill_rect_fast` 填充窗口内容区
  - `term_putchar()`: `font_putchar(ch, px, py, fg, bg)` 逐字符渲染
  - `term_scroll_up()`: `mem_copy` 逐扫描行上移像素，清最后一行
- **`shell.hl`**: 管道操作符 + 多处修正
  - `shell_handle_pipe(pipeline)`: `|` 分割，执行左侧，对右侧 `grep/wc/head/tail` 处理
  - `_str_contains(haystack, needle)`: 子串搜索辅助函数
  - `shell_main()`: 检测 ` | ` 后分流到 `shell_handle_pipe()`
  - `cat /proc/...`: 新增 fs_type=4 分支调用 `procfs_read()` 直接返回
  - `ver` 命令: 114 → 130 模块
  - `help` 新增 Pipe: 行和 Proc: 行
  - 命令计数更新: 75 → 79 commands + pipe(|)
- **`kernel_init.hl`**: Phase 5 增加 `procfs_init()` 调用



- **`vfs.hl`**: ext4 (fs_type=3) 全面集成
  - `vfs_mount_ext4(path, ahci_port)`: 调用 ext4_init 后注册为 fs_type=3 挂载点
  - `vfs_open()`: ext4路径下解析inode号存入fd表，读取inode得文件大小
  - `vfs_read()`: fs_type=3 分支调用 ext4_read_file，读入EXT4_BLOCK_BUF返回字节数
  - `vfs_stat()`: ext4路径下读inode mode字段判断文件/目录，返回[size,type,ino,0]
  - `vfs_readdir()`: ext4路径下调用 ext4_list_dir，过滤 "." / ".."，返回名称数组
  - `vfs_mkdir()` / `vfs_unlink()`: ext4分支返回-1（只读）
- **`kinterp.hl`**: 解释器全面增强
  - `while` 循环: 移除10000次迭代硬限制，改用 `loop_running` flag，支持无限循环
  - 数组下标赋值: `arr[i] = v` 语句 (`set_at` + 变量回写) 完整实现
  - `ki_call_builtin` 扩充至 35 个内置函数:
    - 新增: `serial_print, parse_int, set_at, str_sub, str_char_at, str_from_code`
    - 新增: `str_starts_with, str_ends_with, format_hex, abs, min, max`
    - 新增: `mem_read/write_u16/u64, mem_zero, uptime_secs`
    - 新增: `vfs_open, vfs_close, vfs_stat, vfs_readdir, ext4_resolve, ext4_list_dir`
- **`shell.hl`**: 文件命令增强
  - `ls`: 改为调用 `vfs_readdir("/")` 输出文件名列表（原为 fs_list 条目计数）
  - `ls /path`: 新增带路径参数，支持列出任意目录
  - `cat /path`: ext4路径下直接调用 ext4_read_path，从EXT4_BLOCK_BUF构建字符串输出
- **`kernel_init.hl`**: Phase 7 改为调用 `vfs_mount_ext4("/", 0)` 而非直接 ext4_init



- **`ext4.hl`**: 完整实现真实磁盘读路径（原全为注释/空桩）
  - `ext4_init(ahci_port)`: 读超级块(LBA 2)、校验EF53魔数、提取block_size/inode_size/ipg/feature_incompat
  - `ext4_read_inode(inode_num)`: 读BGDT → 找inode表块 → 计算LBA → `ahci_read()` → 返回EXT4_INODE_BUF地址
  - `ext4_parse_extents(inode_addr)`: 解析extent header(魔数0xF30A) + 叶节点extent列表
  - `ext4_read_file(inode_num, max_size)`: 循环读extent → 写入EXT4_BLOCK_BUF → 返回字节数
  - `ext4_list_dir(inode_num)`: 解析线性dir entry(ino+rec_len+name_len+type+name) → 返回[name,ino,type]数组
  - `ext4_resolve(path)`: 分段解析路径 → 递归ext4_list_dir → 返回inode号
  - `ext4_read_path(path, max_size)`: 快捷接口，path→inode→file read
  - 新增固定缓冲区: 0x930000(SB) / 0x932000(BGDT) / 0x934000(inode) / 0x938000(block)
- **`kinterp.hl`**: 修复词法器关键Bug（数字+标识符扫描器）
  - 原实现: `ki_pos = ki_source_len + 1` break后 `ki_pos - ki_source_len - 1 + start = start`，扫描结束后ki_pos回到token起始位置，导致无限重扫
  - 修复: 改用独立 `scan_num`/`scan_id` flag控制的 while 循环，`ki_pos` 正确停在第一个非法字符
- **`vesa.hl`**: 新增GPU桥接 + 快速填充
  - `vesa_fill_rect_fast(x,y,w,h,color)`: 每行用 `mem_set32()` 整行写入，替代逐像素循环
  - `vesa_gpu_mode(gpu_fb_addr, gpu_w, gpu_h)`: 将 vesa_fb_addr 指向 GPU_FB_ADDR，一行完成 GPU/VESA 桥接
  - `vesa_hline()` 改为调用 `vesa_fill_rect_fast()`（性能优化）
- **`wm.hl`**: `wm_draw_all()` 末尾增加 `if gpu_initialized == 1 { gpu_flip(); }`，所有帧自动推送到VirtIO-GPU显示
- **`font.hl`**: 新增文本光标 + 终端输出接口
  - `font_sync_fb()`: 从当前vesa全局变量同步字体渲染器参数
  - `font_cur_col/row`, `font_fg/bg` 全局光标状态
  - `font_putc(ch)`: 单字符输出 + 光标推进 + 自动换行 + 自动滚屏
  - `font_print(s)` / `font_println(s)`: 字符串输出至光标位置
  - `font_scroll_up()`: 全屏上滚一行 + 清底行
- **`kernel_init.hl`**: 初始化序列升级
  - Phase 6 后增加 `font_sync_fb()`
  - Phase 7 增加: VirtIO-GPU检测/初始化/桥接序列 + `ext4_init(0)` 挂载根文件系统
  - GPU init成功后额外调用 `font_sync_fb()` 重绑字体到GPU帧缓冲
- **`shell.hl`**: 新增 `gpu`（显示GPU状态）和 `ext4`（列出根目录）命令 → 75条命令



- **`gpu.hl`**: 完整实现 VirtIO-GPU 2D命令提交管线
  - `gpu_detect()`: PCI扫描找到 VirtIO-GPU (0x1AF4:0x1050)
  - `gpu_init()`: VirtIO设备初始化 → GET_DISPLAY_INFO → resource → backing → scanout → flush
  - `gpu_write_hdr/gpu_submit()`: 底层virtqueue提交（双描述符 cmd+resp，spin-wait）
  - `gpu_create_resource/attach_backing/set_scanout/transfer/flush`: 完整2D命令链
  - `gpu_blit(x,y,w,h)` / `gpu_flip()`: 高层 dirty-region / 全屏刷新接口
  - `gpu_fb_base()`: 0xA00000 guest framebuffer; `gpu_ctx_create/submit_3d` virgl 3D命令
- **`ui_settings.hl`**: 新建设置中心窗口 (~270行)
  - Display / Audio / Network / About 四标签页
  - Audio: 音量进度条 + 键盘 +/- 调节 + Apply → `mixer_set_master_volume()`
  - Network: IP / MAC / 网关实时显示; About: 版本/架构/运行时间
- **`wm.hl`**: 键盘分发 + 新辅助函数
  - `wm_key_dispatch(key)`: 键盘事件路由到焦点模块
  - `wm_win_x/y/w/h()`, `wm_destroy_window()`: 新增窗口坐标/销毁辅助
  - `wm_draw_all()` / `wm_mouse_click()`: 集成 ui_files + ui_settings 渲染与点击
- **`shell.hl`**: 新增 `settings` 命令 → 73条命令



## Iteration 131 — IR→x86 Native Backend + Audio Fix + File Manager

- **`codegen.hl`**: 实现 `ir_emit_x86` — 将所有 37 条 IR 指令翻译为 x86_64 机器码
  - 新增辅助函数：`ir_cg_init / ir_cg_phys / ir_cg_load / ir_cg_load_into / ir_cg_store`
  - 新增标签/跳转回填：`ir_cg_define_label / ir_cg_add_patch / ir_cg_patch_labels`
  - `compile_native()` Phase 4 注释代码已激活，原生编译管线完整通路打通
- **`mixer.hl`**: 修复 `mixer_mix()` 关键 Bug
  - 新增 `mixer_clamp(v, lo, hi)` 辅助函数
  - 解注并修正变量定义（`sample / left_vol / right_vol / out_off / cur_l / cur_r`）
  - 用 `stream_done` 标志替换非法 `break` 语句
  - 将注释的 `ac97_submit_buffer` 替换为正确的 `ac97_play()` 调用
- **`linker.hl`**: 扩充 `linker_register_builtins()` 内置符号列表
  - 新增 38 个缺失符号（`clamp / mem_read_* / mem_write_* / port_in_* / port_out_* / serial_print` 等）
  - 解决剩余 1 个未解析重定位
- **`ui_files.hl`**: 新建 — 文件管理器窗口（228 行）
  - `uifiles_open / close / render / tick / navigate / handle_key`
  - 支持目录导航（Enter 进入，Backspace 返回，Escape 关闭）
  - 滚动条、选中高亮、状态栏（文件大小信息）
- **`shell.hl`**: 新增 3 条命令（总计 72 条）
  - `sysmon` → 打开系统监控窗口
  - `files` → 打开文件管理器
  - `audiotest` → 440 Hz 蜂鸣测试



- **`ui_sysmon.hl`**: 新建 — 系统监控窗口
  - 实时显示：运行时间、RTC 时钟、内存使用率（进度条）
  - 任务计数：Running / Ready / Blocked / Dead
  - 窗口状态：打开数 / 当前焦点
  - 每 2 秒自动刷新
- **`ui_notify.hl`**: 新建 — Toast 通知系统
  - 4 种类型：info / success / warning / error
  - 最多 4 条同时显示，屏幕右上角堆叠
  - 自动消失（TTL 3 秒）
  - FIFO 队列，满时循环替换最早一条
  - 左侧彩色强调条 + 边框 + 阴影
- **`wm.hl`**: 集成系统监控和通知渲染
- **`ui_desktop.hl`**: 监控器启动器现打开真实系统监控窗口
  - 桌面 tick 驱动监控器和通知计时器
- **`HicOS_UIServer.hl`**: IPC 消息处理完善
  - 新增 CREATE_WIN / DESTROY_WIN / SET_TITLE 消息处理
  - 合成后向焦点客户端发送 FOCUS_EVENT
  - 统计信息新增通知计数

## Iteration 129 — 窗口标题文字 + 图形安装器

- **`wm.hl`**: 窗口标题文字渲染
  - 新增 `wm_titles[]` 并行数组存储窗口标题字符串
  - `wm_get_title()` / `wm_set_title()`: 读写窗口标题
  - 标题栏现渲染窗口名称文字（自动截断防溢出）
  - 内容区点击路由到安装器模块
  - 安装器窗口内容渲染集成
- **`ui_installer.hl`**: 新建 — 图形安装器多步向导
  - 5 步驤：Welcome → Detect → Confirm → Install → Complete
  - 每步独立渲染：标签 / 分隔线 / 徽章 / 进度条 / 按钮
  - 磁盘检测：自动识别 ATA/AHCI/VirtIO 后端
  - 容量校验 + 危险警告
  - 实际磁盘写入 + MBR 修正 + 0x55AA 校验
  - 进度条实时显示安装状态
  - Back / Next / Install / Close 导航按钮
- **`ui_desktop.hl`**: 任务栏窗口按钮现显示窗口标题而非索引
  - Installer 启动器现打开图形安装器窗口
- **`build.hl`**: 新增 `ui_installer.hl` 到编译序列

## Iteration 128 — 桌面编排层 + 模态对话框 + UI Server 集成

- **`ui_desktop.hl`**: 新建 — 桌面编排层
  - 顶部栏：品牌文字 + RTC 实时时钟 + 窗口计数指示器
  - 底部 dock：应用启动器按钮（Terminal / Installer / Monitor）
  - dock 窗口按钮带编号标签
  - 应用启动器与窗口按钮间分隔线
  - `uidsk_launch_app()`: 点击 Terminal 启动图形终端
  - `uidsk_tick()`: 每秒更新时钟显示
  - 路由键盘/鼠标事件到对话框和启动器
- **`ui_dialog.hl`**: 新建 — 模态对话框系统
  - 4 种对话框：INFO / CONFIRM / WARNING / ERROR
  - 键盘导航：Tab 切换、Enter 确认、Esc 取消
  - 鼠标点击按钮
  - 半透明遮罩覆盖
  - 标题栏颜色按对话框类型变化（蓝/黄/红）
  - 便捷包装：`ui_dialog_info/confirm/warn/error()`
- **`wm.hl`**: 集成桌面层和对话框
  - `wm_draw_all()` 现委托 `uidsk_draw_chrome()` 绘制桌面
  - `wm_draw_all()` 渲染结束后绘制图形终端内容和对话框覆盖
  - `wm_mouse_click()` 优先路由对话框和桌面启动器
- **`HicOS_UIServer.hl`**: 集成桌面层
  - `uis_init()` 现调用 `uidsk_init()` 初始化桌面
  - `uis_tick()` 现调用 `uidsk_tick()` 更新时钟
  - `uis_dispatch_key()` 优先路由键盘事件到对话框
- **`build.hl`**: 新增 `ui_dialog.hl` 和 `ui_desktop.hl` 到编译序列

## Iteration 127 — UI 控件系统 + 任务栏 + 图形终端

- **`ui_controls.hl`**: 新建 — 基础控件系统
  - `ui_draw_char()` / `ui_draw_text()`: 8×16 位图字体文字绘制
  - `ui_label()` / `ui_label_colored()`: 静态文字标签
  - `ui_button()` / `ui_button_active()` / `ui_button_hit()`: 可点击矩形按钮
  - `ui_progress_bar()`: 水平进度条（百分比文字居中）
  - `ui_separator_h()` / `ui_separator_v()`: 水平/垂直分隔线
  - `ui_badge_ok()` / `ui_badge_warn()` / `ui_badge_err()`: 状态徽章
- **`ui_terminal.hl`**: 新建 — 图形终端窗口
  - 80×25 字符网格内嵌 wm 窗口
  - 64 行滚动缓冲区（cell buffer at 0x900000）
  - 逐行滚屏 + VGA 16 色 ARGB 调色板
  - 光标闪烁渲染
  - `uiterm_open()` / `uiterm_close()` / `uiterm_write()` / `uiterm_render()` 完整生命周期
- **`wm.hl`**: 任务栏与最小化
  - 新增最小化按钮（标题栏关闭按钮左侧）
  - `wm_minimize_window()` / `wm_restore_window()`
  - 底部 dock 任务栏绘制窗口按钮（聚焦高亮 / 普通灰色）
  - 任务栏点击：聚焦 / 最小化 / 恢复窗口
  - 顶部栏 "HicOS" 品牌文字绘制
- **`build.hl`**: 新增 `ui_controls.hl` 与 `ui_terminal.hl` 到编译序列

## Iteration 126 — 窗口交互基础完善

- **`wm.hl`**: 窗口管理器从静态绘制推进到可交互基础设施
  - 新增窗口 flags 辅助：可见 / 聚焦 / 最小化
  - 新增 `wm_focus_window()` 与 `wm_raise_window()`
  - 新增窗口、标题栏、关闭按钮命中测试
  - 鼠标点击现支持：聚焦、置顶、标题栏拖动、关闭窗口
  - 拖动过程加入屏幕边界和桌面顶栏/底栏约束
  - 修复主题接入后旧 `WM_TITLE_HEIGHT` 常量残留
  - `wm_create_window()` 现记录 `title_ptr` 并自动聚焦新窗口
- **`HicOS_WindowManager.hl`**: `hicos_wm_focus()` 改为直接调用 `wm_focus_window()`
- **`HicOS_UIServer.hl`**: 创建窗口时向 `wm_create_window()` 透传 owner PID

## Iteration 125 — UI 主题基线 + 窗口管理器接入

- **`ui_theme.hl`**: 新建 — HicOS UI 主题模块
  - 统一桌面、面板、边框、标题栏、阴影、成功/警告/错误色
  - 统一标题栏高度、顶栏高度、底栏高度、阴影偏移等基础度量
- **`wm.hl`**: 接入统一主题
  - 桌面背景改为从 `ui_theme` 读取
  - 新增桌面顶部栏/底部栏基础 chrome
  - 窗口接入统一边框/标题栏/阴影/内容区颜色
  - 关闭按钮颜色接入主题错误色
- **`build.hl`**: 新增 `ui_theme.hl` 到图形/UI 模块编译序列

## Iteration 124 — 完整当前镜像裸机安装

- **`self_image.hl`**: 自映像写盘路径从“回读目标盘”升级为“从内存重建完整启动镜像”
  - `self_image_read_sector(lba, buf_addr)`: 按 LBA 重建当前运行镜像
    - `LBA0` → `0x7C00` stage1/MBR
    - `LBA1` → `0x8000` stage2
    - `LBA2+` → `0x100000` kernel payload
  - `self_install_to_disk()`: 逐扇区将当前启动镜像直接写入目标磁盘
  - 默认镜像元数据同步到最新构建：`161280` bytes / `315` sectors
- **`installer.hl`**: 安装器主流程升级为真实裸机安装闭环
  - `[3/7]` 检查当前运行镜像
  - `[4/7]` 校验目标磁盘容量是否足够容纳完整镜像
  - `[5/7]` 执行 raw boot image 全盘写入
  - `[6/7]` Legacy BIOS 路径补写/修正 MBR 分区元数据
  - `[7/7]` 回读校验 `0x55AA` 启动签名
  - 移除文件加载时自动执行 `installer_main()` 的危险行为
- **`kernel_entry.hl`**: 原生 `install` 命令改为直接委托 `installer_main()`
  - 不再使用旧的 VirtIO-only 假安装流程
  - 现在走 ATA PIO / AHCI / VirtIO 三后端统一安装器
- **`manifest.hl`**: `BOOT_IMAGE_BYTES` 同步为 `161280`





