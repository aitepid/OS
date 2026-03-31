# HicOS Changelog

## Current Snapshot

- `.hl` 文件：`198`（68 根目录 + 130 内核模块）
- H-L 总行数：`46,499`（根 10,044 + 内核 36,455）
- 内核模块：`130`（编译产出 1,700 函数 / 2,003 符号）
- `kernel_entry.hl`：`9,428` 行
- `hl-bootstrap.hl`：`4,306` 行，`208` 函数
- `stdlib.hl`：`1,385` 行，`143` 函数
- `kinterp.hl`：`1,245` 行
- Shell 命令（`shell.hl` if cmd ==）：`68`
- `scripts/*.ps1`：`28`（9,729 行）
- 构建/测试主入口：`hl-bootstrap.cmd test`
- 最近完成功能迭代：`130`（系统监控 + Toast 通知 + UI Server IPC 完善）

## Iteration 130 — 系统监控 + Toast 通知 + UI Server IPC 完善

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





