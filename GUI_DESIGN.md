# HicOS GUI Design Outline

> 目标：将 HicOS 从串口控制台 OS 演进为具备 **Windows 11 Fluent Design** 视觉与交互品质，并**自适应桌面 / 平板 / 手机 / 嵌入屏**多形态的图形操作系统。
> 基础：复用已有的 25 个 UI 模块（`vesa.hl` / `wm.hl` / `font.hl` / `mouse.hl` / `ui_*.hl`），补齐合成器、动画、毛玻璃、响应式布局、触控、多显示器、护眼模式、IME 等关键基础设施。

## 已确认的设计决策

| # | 决策 | 选择 |
|---|---|---|
| 1 | 视觉风格 | **Win11 Fluent**（任务栏居中 + 开始菜单 + Snap Layouts） |
| 2 | 主题特性 | **必含护眼模式**（低蓝光 + 暖色温调节 4500 K ↔ 6500 K） |
| 3 | 字体方案 | **自绘位图字体**（13/15/17/22 px × ASCII + 3500 CJK），无外部 TTF 依赖 |
| 4 | 材质 | **启用毛玻璃**（Mica/Acrylic 双层，QEMU 性能不足时自动降级为半透明纯色） |
| 5 | 形态 | **多形态自适应**：桌面 / 平板 / 手机 / 嵌入屏统一代码、响应式布局；**支持多显示器** |
| 6 | 输入 | **多态输入**：鼠标 + 键盘 + 触控（单指/多指手势）+ 触控笔 + 串口（回退） |

---

## 0. 现状盘点（不要重复造轮子）

| 已有模块 | 行数 | 当前能力 |
|---|---:|---|
| `vesa.hl` | 347 | VBE 1024×768×32 LFB 初始化，单层脏矩形跟踪 |
| `wm.hl` | 782 | 窗口注册、Z-order、焦点、最小化/最大化、装饰栏 |
| `mouse.hl` | 159 | PS/2 鼠标解析（3字节包），未做指针绘制/加速曲线 |
| `font.hl` | 257 | 8×16 位图字体，单字号，无抗锯齿 |
| `ui_theme.hl` | 362 | 颜色 token、间距、圆角常量 |
| `ui_controls.hl` | 311 | 按钮、复选框、文本框、滚动条 |
| `ui_dialog.hl` | 284 | 模态对话框、按钮组合 |
| `ui_notify.hl` | — | 通知中心骨架 |
| `ui_desktop.hl` | 377 | 顶栏 + Dock + 应用启动 |
| `ui_terminal.hl`、`ui_files.hl`、`ui_settings.hl`、`ui_sysmon.hl`、`ui_taskman.hl`、`ui_text_editor.hl`、`ui_browser.hl`、`ui_calculator.hl`、`ui_calendar.hl`、`ui_clock.hl`、`ui_paint.hl`、`ui_image.hl`、`ui_hexedit.hl`、`ui_installer.hl`、`ui_notepad.hl` | — | 14 个应用模块（功能粗糙） |

**结论：** 骨架完整，但每个模块均为"能跑通"级，距商用级别还差：合成、双缓冲、动画、阴影、毛玻璃、矢量字体、HiDPI、辅助功能、IME、剪贴板服务、拖放、多显示器等。

---

## 1. 设计原则（Win11 Fluent 主线）

| 维度 | Win11 Fluent | HicOS 选择 |
|---|---|---|
| 圆角 | 窗口 8 px / 控件 4 px | **窗口 8 px / 控件 4 px**（Win11 一致） |
| 材质 | Mica（窗口背景）/ Acrylic（弹层） | **HicMica + HicAcrylic** 双层 |
| 阴影 | 投影 16 px, 黑 12%，三层级 | **16/24/32 px** 三档阴影 |
| 动画曲线 | Fluent Easing（cubic-bezier(0.2, 0, 0, 1)） | **同 Win11**，时长 167/250/333 ms |
| 字体 | Segoe UI Variable | **HicSans（自绘位图）** 13/15/17/22 px |
| 间距栅格 | 4 px | 4 px |
| 暗色模式 | 系统级 + 强调色 | **明 / 暗 / 护眼**（三主题）+ 7 种强调色 |
| 触感反馈 | 微缩放 0.96× + 涟漪 | **缩放 0.96× + Reveal 高光**（鼠标悬停跟随光环） |
| 模态语义 | ContentDialog 中心放大 | **ContentDialog 中心 + 200 ms 弹入** |
| 任务栏 | 居中应用图标 + 右托盘 | **同 Win11**（手机形态下变为底栏） |

### 1.1 护眼模式（必含）

| 项 | 设计 |
|---|---|
| **色温滑块** | 4500 K（暖）↔ 6500 K（中性）↔ 7500 K（冷），用户在设置中调节 |
| **定时启用** | 日落自动开启 / 自定义时间段（18:00–06:00） |
| **蓝光衰减** | 全屏 LUT 后处理：B 通道 ×0.6~0.9 系数（按色温映射） |
| **亮度联动** | 夜间亮度下调 20%，与色温联动 |
| **阅读专用** | 文本应用单独可启用纸质化（背景 #F5F0E6） |
| **实现层** | 合成器最终输出前的 **post-process LUT pass**（256 项 RGB 查表） |

---

## 2. 架构分层（含多形态自适应）

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 7 — Applications（一套代码，多形态自适应）                  │
│ Files / Settings / Terminal / Editor / Sysmon / 12+ apps         │
├─────────────────────────────────────────────────────────────────┤
│ Layer 6 — Shell（按 FormFactor 切换）                            │
│ Desktop Shell（任务栏+开始）│ Tablet Shell │ Mobile Shell        │
├─────────────────────────────────────────────────────────────────┤
│ Layer 5 — Adaptive Layout Engine                                 │
│ Breakpoint · Stack/Grid/Flex · ResponsiveContainer · Density     │
├─────────────────────────────────────────────────────────────────┤
│ Layer 4 — Widget Toolkit（与形态无关）                            │
│ Button/Label/TextField/List/Tree/Menu/Tabs/Sheet/Toast           │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3 — Window Manager（含多显示器、虚拟桌面）                  │
│ Window/Z-order/Focus/Snap/Workspaces/Display Topology            │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2 — Compositor                                             │
│ Surface/Layer/Damage/Blend/Effects(Mica/Acrylic/Shadow)/LUT      │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1 — Graphics Engine                                        │
│ Bitmap/Blit/Line/Curve/Font/AA/Alpha/Gradient                    │
├─────────────────────────────────────────────────────────────────┤
│ Layer 0 — Display & Input HAL                                    │
│ FB (VESA/多 head) · Mouse · KBD · Touch · Pen · Sensor           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2A. 多形态自适应系统（HarmonyOS 级能力，本次新增）

### 2A.1 FormFactor 检测

启动时探测硬件特征，归类为五种形态：

| 形态 | 屏幕尺寸 | 主输入 | DPI | Shell |
|---|---|---|---|---|
| `desktop` | ≥ 1024×768 | 鼠标+键盘 | 96–120 | DesktopShell（任务栏+开始） |
| `laptop` | 1280×800–1920×1200 | 触控板+键盘 | 120–160 | DesktopShell + 手势 |
| `tablet` | 768×1024–1280×800 | 触控+笔 | 160–220 | TabletShell（全屏应用 + 手势） |
| `mobile` | < 768×1024 | 触控 | 220–440 | MobileShell（底栏 + 单列） |
| `embedded` | 任意小屏 | 触控/按键 | 96–200 | KioskShell（单应用全屏） |

**检测逻辑：** 屏幕宽度 + 触控设备存在性 + DPI + 用户配置覆盖（设置中可强制）。

### 2A.2 Breakpoint 栅格（响应式断点）

```
xs   < 480   px   — 手机竖屏
sm   480–767      — 手机横屏 / 小平板
md   768–1023     — 平板
lg   1024–1439    — 桌面 / 笔记本
xl   1440–1919    — 大桌面
2xl  ≥ 1920       — 超大显示器
```

每个 widget 接受 `responsive` 属性：

```hl
widget_panel({
  layout: {
    xs: "stack",       // 手机：纵向堆叠
    md: "grid_2col",   // 平板：双列
    lg: "grid_3col"    // 桌面：三列
  },
  padding: { xs: 8, md: 16, lg: 24 }
})
```

### 2A.3 密度（Density）

| Density | 控件最小尺寸 | 字号基准 | 触发条件 |
|---|---|---|---|
| `compact` | 28 px | 13 px | desktop + 设置开启 |
| `comfortable` | 36 px | 15 px | desktop/laptop 默认 |
| `spacious` | 44 px | 17 px | tablet 默认 |
| `touch` | 48 px | 17 px | mobile / 触控主输入 |

**Apple HIG / Material 共识：** 触控目标 ≥ 44 px。HicOS 自动按 FormFactor 选择 density。

### 2A.4 Shell 形态切换示意

| Shell | 任务栏/导航 | 开始/启动器 | 多窗口 |
|---|---|---|---|
| **DesktopShell** | 底部居中任务栏（Win11 风） | Start Menu 弹窗（带搜索） | 自由窗口 + Snap |
| **TabletShell** | 底部 Dock + 手势条 | 全屏 Launchpad（App 图标网格） | 分屏 1+1 或 1+2 |
| **MobileShell** | 底部 5 项 TabBar | App Drawer（向上滑） | 单应用全屏 + 后台栈 |
| **KioskShell** | 隐藏 | 无 | 单应用 |

**核心约束：** Shell 是 **轻代理层** — 应用代码完全不感知 Shell，由 Adaptive Layout 自动适配。

### 2A.5 输入抽象（统一事件模型）

所有输入归一化为 `PointerEvent`：

```hl
PointerEvent {
  type: "down" | "move" | "up" | "cancel"
  pointer_id: int       // 多指触控区分
  source: "mouse" | "touch" | "pen" | "trackpad"
  x, y: int             // 逻辑坐标（已应用 scale）
  pressure: int         // 笔压 0-1023（鼠标=512）
  tilt_x, tilt_y: int   // 笔倾斜
  buttons: bitmask
  modifiers: bitmask    // Shift/Ctrl/Alt/Meta
  timestamp: u64
}
```

手势识别器（GestureRecognizer）订阅 PointerEvent 流：

- **Tap** / **DoubleTap** / **LongPress**
- **Pan** / **Swipe**（四方向）
- **Pinch**（双指捏合缩放）
- **Rotate**（双指旋转）
- **EdgeSwipe**（边缘划入 → Mobile/Tablet 返回手势）
- **PenHover** / **PenDraw**

**新增模块：** `input_pointer.hl`、`input_gesture.hl`、`input_touch.hl`、`input_pen.hl`（4 模块，~1200 行）

---

## 3. 关键基础设施缺口与计划

### 3.1 Layer 0 — Framebuffer 增强

| 缺口 | 设计 |
|---|---|
| 单缓冲撕裂 | **双缓冲**：后台 buf @ 0x2000000（4 MB），原子翻页（页表 PTE 重映射 LFB） |
| 全屏刷新浪费 | **细粒度脏矩形**：4×4 tile 网格，bitmap 标记，每帧仅拷贝脏 tile |
| VSync 缺失 | **PIT 60 Hz 触发 + LFB 拷贝**（短期），后续改 LAPIC 定时器 |
| HiDPI 支持 | **scale_factor** 全局变量（1×/1.5×/2×），所有几何按 logical → physical 转换 |

**新增模块：** `gfx_backbuffer.hl`（~250 行）

### 3.2 Layer 1 — 矢量图形与字体

| 缺口 | 设计 |
|---|---|
| 仅位图字体 | **多档位图字体 + Sub-pixel rendering**：13/15/17/22 px 各预渲染 ASCII + CJK 常用 3500 字 |
| 无抗锯齿 | **Wu's algorithm** 直线 AA；圆角矩形用 **distance field**（4 角预计算） |
| 无 alpha 混合 | **32-bit RGBA premultiplied** 全栈，`blit_alpha` 内联汇编加速 |
| 无渐变 | **线性 / 径向渐变** 函数，2-stop 起步 |
| 无图形矢量 | **路径渲染**（M/L/Q/C/Z），扫描线填充 |

**新增模块：** `gfx_aa.hl`、`gfx_path.hl`、`gfx_gradient.hl`、`font_atlas.hl`（4 模块，~1000 行）  
**扩展：** `font.hl` → 增加字号选择、字距、行高

### 3.3 Layer 2 — 合成器（关键缺口）

当前 `wm.hl` 直接绘制到 LFB，无合成层。商用 OS 必备合成器：

| 子系统 | 设计 |
|---|---|
| **Surface** | 每个窗口拥有独立 RGBA 后备 buffer，应用绘制到 surface 而非 LFB |
| **Layer 树** | Surface 组成 layer 树，支持嵌套（窗口 > 装饰 > 内容 > 控件） |
| **Damage 传播** | Layer 局部脏 → 向上传播到父 → 合成器仅重绘脏区域 |
| **效果链** | Layer 上可挂载效果：`blur(8px)`、`shadow(20px, 15%)`、`opacity(0.95)` |
| **毛玻璃材质** | 取窗口背后内容 → box-blur → 与窗口色混合 = HicGlass |
| **动画** | Layer 属性（位置、透明度、缩放）插值器，每帧 tick |

**新增模块：** `compositor.hl`（~600 行）、`gfx_blur.hl`（~200 行）、`gfx_shadow.hl`（~150 行）、`gfx_anim.hl`（~250 行）

### 3.4 Layer 3 — 窗口管理升级

`wm.hl` 已有基础，需对标 Win11/macOS 升级：

| 缺口 | 设计 |
|---|---|
| 装饰栏过时 | **标题栏**：左侧 macOS 风三圆点（红黄绿）+ 居中标题 + 右侧菜单按钮 |
| 无 Snap | **窗口贴边**：拖拽到边缘高亮虚框，松手 1/2 屏；上侧 = 全屏；快捷键 `Win+←/→` |
| 无工作区 | **虚拟桌面**：4 个工作区，`Ctrl+1..4` 切换，`Ctrl+→` 滑入动画 |
| 无 Mission Control | **窗口总览**：F3 触发，所有窗口缩放 0.4× 平铺，鼠标悬停高亮 |
| 焦点环不明显 | **焦点环**：失焦窗口标题栏灰化 + 内容降低对比度 5% |
| 拖拽无幽灵 | **拖拽预览**：窗口半透明跟随光标，松手回弹动画 |

**扩展：** `wm.hl` +~400 行  
**新增模块：** `wm_snap.hl`、`wm_workspaces.hl`、`wm_overview.hl`

### 3.5 Layer 4 — 控件工具包扩展

当前 `ui_controls.hl` 只有 4 个基础控件。商用 OS 需要完整套件：

| 类别 | 控件 |
|---|---|
| **输入** | 文本框（含占位符、密码、多行）、SearchField、SpinBox、Slider、Stepper |
| **选择** | Button（实心/边框/文本）、Toggle（开关）、Checkbox、Radio、SegmentedControl、ComboBox、DatePicker、ColorPicker |
| **容器** | GroupBox、Tabs、ScrollView、SplitView、Accordion、Sidebar |
| **数据展示** | Label、Image、Avatar、Badge、ProgressBar、Spinner、Tooltip、Popover |
| **列表** | List（单/多选）、Tree、Table（列排序/调宽）、Grid、Carousel |
| **导航** | Menu、MenuBar、ContextMenu、Toolbar、TabBar、Breadcrumb |
| **反馈** | Toast、AlertSheet、Dialog（信息/确认/输入）、ProgressSheet |

**新增模块：** `widget_*.hl` 共 ~25 个（每个 100–300 行）

### 3.6 Layer 5 — Shell（桌面环境）

| 组件 | 对标 | 设计 |
|---|---|---|
| **TopBar** | macOS 顶栏 | 高 24 px，左 Apple/HicOS Logo + 当前 app 菜单；右 状态指示器（音量/电池/Wi-Fi/时钟） |
| **Dock** | macOS Dock | 底部居中，固定 12 个常驻 + 运行中应用，悬停放大 1.3×，左键启动/聚焦，右键菜单 |
| **TaskBar 模式** | Win11 | 设置中可切换为 Win11 风：底部全宽，左居中应用 + 右托盘 |
| **StartMenu** | Win11 开始 / Spotlight | 按 `Win` 或 `Cmd+空格` 触发，居中弹窗，搜索 + 推荐应用 + 文件 + 命令 |
| **NotificationCenter** | 二者通用 | 右上滑入面板，分组通知（应用/时间），可清除/操作按钮 |
| **ControlCenter** | macOS Sonoma | 右上角点击图标弹出：亮度/音量/Wi-Fi/勿扰/录屏/快速设置 |
| **Wallpaper** | 二者通用 | 默认 4 张内置（深/浅 ×2），用户可选 BMP/PNG 自定义；支持时间变化壁纸 |
| **Lock Screen** | 二者通用 | 时钟大字号 + 日期 + 通知预览，向上滑入解锁 |
| **Spotlight 搜索** | macOS | `Cmd+空格`，模糊匹配应用/文件/系统设置/算术运算 |
| **Mission Control** | macOS | F3 总览所有窗口 + 工作区切换器 |
| **Snap Layouts** | Win11 | 鼠标悬停最大化按钮，弹出 4 种布局选择 |

**新增模块：** `shell_topbar.hl`、`shell_dock.hl`、`shell_startmenu.hl`、`shell_spotlight.hl`、`shell_controlcenter.hl`、`shell_lockscreen.hl`、`shell_wallpaper.hl`、`shell_notification.hl`（8 模块，~3000 行）

### 3.7 Layer 6 — 应用品质拔高

现有 14 个 ui_app 仅功能性骨架。商用化需统一 UX：

| 应用 | 当前 | 升级目标（对标） |
|---|---|---|
| **Files** | 列表 | macOS Finder：侧栏（收藏/位置）、面包屑、4 种视图（图标/列表/列/画廊）、Quick Look 预览 |
| **Settings** | 选项列表 | macOS System Settings：左侧分类导航 + 右侧详情，搜索 |
| **Terminal** | 文本输出 | iTerm2 风：标签页、分屏、ANSI 真彩色、半透明背景、字体抗锯齿 |
| **TextEditor** | 编辑 | Notes/记事本：富文本、行号、语法高亮（H-L）、自动保存 |
| **Calculator** | 数字 | 基础+科学+程序员三模式，历史记录 |
| **Sysmon** | 进程列表 | 活动监视器：CPU/内存/磁盘/网络图表，进程树，可结束 |
| **Browser** | 占位 | 简易渲染（HTML 子集），地址栏，历史 |
| **Paint** | 占位 | 笔刷、形状、橡皮、撤销栈 |
| **Calendar** | 占位 | 月/周/日视图，事件 CRUD |
| **Clock** | 占位 | 世界时钟、计时器、闹钟、秒表 |

新增建议应用：**System Information**（关于本机）、**Activity Monitor**（合并 Sysmon）、**Disk Utility**、**Screenshot Tool**、**Color Meter**。

---

## 4. 输入与交互

### 4.1 鼠标

| 缺口 | 设计 |
|---|---|
| 无指针图像 | 11 种系统指针（箭头/手形/I 形/调整/等待/不可用 等），32×32 RGBA |
| 无加速曲线 | **指数加速**：移动距离 < 5 → 1×，> 30 → 3×，中间插值 |
| 无双击 | 300 ms 内同位置二次点击 = 双击事件 |
| 无拖拽阈值 | 按下后移动 > 4 px 才触发 drag |
| 无滚轮平滑 | 滚轮事件累积 200 ms，输出平滑插值 |

### 4.2 键盘

| 缺口 | 设计 |
|---|---|
| 仅扫描码 → ASCII | **快捷键路由**：`Ctrl/Alt/Shift/Win/Cmd` 修饰符 + 字母键全局注册表 |
| 无 IME | **拼音 IME**：基于 3500 字常用表 + 双拼/全拼，Ctrl+空格切换 |
| 无文本输入焦点 | 全局 `focused_input` 指针，键盘事件直送 |

### 4.3 剪贴板

`clipboard.hl` 新建：文本/位图/文件路径三种类型，跨应用共享，历史 10 条。

### 4.4 拖放

`dnd.hl` 新建：源应用 → 创建 DragSession（携带数据）→ 鼠标移动绘制幽灵 → 目标应用 hit-test → drop 触发回调。

---

## 5. 设计令牌（Design Tokens）

`ui_theme.hl` 升级为完整 token 系统：

```
颜色（Light/Dark 双套）
  bg.window         #FFFFFF / #1E1E1E
  bg.surface        #F5F5F7 / #2C2C2E
  bg.elevated       #FFFFFF / #3A3A3C
  bg.glass          rgba(255,255,255,0.7) / rgba(30,30,30,0.6)
  fg.primary        #1D1D1F / #F5F5F7
  fg.secondary      #6E6E73 / #98989D
  fg.disabled       #C7C7CC / #48484A
  accent.blue       #007AFF (default)
  accent.{red,orange,yellow,green,teal,purple,pink}  ← 7 种强调色

字号
  caption  11 px
  body     13 px
  subhead  15 px
  headline 17 px
  title    22 px
  largeTitle 34 px

圆角
  radius.xs  2px
  radius.sm  4px
  radius.md  6px
  radius.lg  10px
  radius.xl  16px

间距（4 px 栅格）
  space.1=4  space.2=8  space.3=12  space.4=16  space.5=20  space.6=24  space.8=32  space.12=48

阴影
  shadow.sm  0 1px 2px rgba(0,0,0,0.05)
  shadow.md  0 4px 8px rgba(0,0,0,0.10)
  shadow.lg  0 12px 24px rgba(0,0,0,0.15)
  shadow.xl  0 24px 48px rgba(0,0,0,0.20)

动画
  duration.fast    150ms
  duration.normal  200ms
  duration.slow    300ms
  easing.out       cubic-bezier(0.2, 0, 0, 1)
  easing.spring    spring(0.5, 0.8)
```

---

## 6. 国际化与辅助功能

| 维度 | 设计 |
|---|---|
| **CJK 支持** | 3500 常用汉字位图字体，所有控件按字符宽度（非字节宽）布局 |
| **多语言** | `i18n.hl` 字符串表（key → {en, zh-CN, zh-TW, ja}），系统设置切换 |
| **高对比度** | `ui_theme.hl` 新增 hc-light / hc-dark token 集，提升对比度至 7:1 |
| **缩放** | 100%/125%/150%/175%/200%，全局 scale_factor 影响所有几何 |
| **VoiceOver hook** | 控件 `aria-label` 属性 + 焦点遍历，预留串口输出位置（屏幕阅读器后续接入） |
| **减少动效** | 设置中开关，禁用所有 > 0 ms 动画 |

---

## 7. 性能预算（1024×768×32 @ 60 fps）

| 阶段 | 预算 | 备注 |
|---|---:|---|
| 帧 budget | 16.6 ms | 60 fps |
| 全屏拷贝 | 3.0 MB | 后台 → LFB；目标 ≤ 4 ms |
| 单窗口重绘 | ≤ 2 ms | 平均尺寸 600×400 |
| 合成（10 层） | ≤ 6 ms | blur/shadow 仅在 invalidate 时重算并缓存 |
| 动画 tick | ≤ 1 ms | 最多 5 个活动动画 |
| 输入处理 | ≤ 0.5 ms | 鼠标/键盘事件分发 |
| **冗余预算** | ≥ 3 ms | 留给应用绘制 |

实测目标：拖动窗口、滚动列表、动画过场 — 视觉无卡顿。

---

## 8. 阶段化实施计划（建议 7 个 Sprint）

| Sprint | 名称 | 关键交付 | 估时 |
|---|---|---|---|
| **G1** | 双缓冲 + 矢量图形基础 | `gfx_backbuffer.hl`、`gfx_aa.hl`、`gfx_path.hl`、`font_atlas.hl`；演示：圆角抗锯齿矩形 + 多字号文字 | 1 |
| **G2** | 合成器 + 毛玻璃 | `compositor.hl`、`gfx_blur.hl`、`gfx_shadow.hl`、`gfx_anim.hl`、护眼 LUT pass；演示：Mica/Acrylic + 阴影 + 色温滑块 | 1 |
| **G3** | 多形态输入 + WM 升级 | `input_pointer.hl`、`input_gesture.hl`、`input_touch.hl`、`input_pen.hl`、`wm.hl` 重写、`wm_snap.hl`、`clipboard.hl`、`dnd.hl`；演示：触控/鼠标统一事件 + 贴边 | 1.5 |
| **G4** | 响应式布局 + 控件库 | `adaptive_layout.hl`、`breakpoint.hl`、25 个 `widget_*.hl`；演示：控件画廊在 480/768/1280 三种宽度自适应 | 2 |
| **G5** | Shell 多形态 | DesktopShell（`shell_*` 8 模块）+ TabletShell + MobileShell + KioskShell；演示：FormFactor 切换 | 2 |
| **G6** | 应用品质拔高 | Files / Settings / Terminal / TextEditor / Sysmon 五大核心应用重写（响应式） | 1.5 |
| **G7** | 多显示器 + IME | `display_topology.hl`、`ime.hl`、虚拟桌面、Mission Control | 1 |
| **G8** | 抛光 + 对标 | HiDPI、辅助功能、动画微调、4 套主题壁纸、视觉走查对标 Win11 | 1 |

总计：**~11 个 Sprint**（多形态自适应 + 多输入显著扩大了原 9-Sprint 估算）。每个 Sprint 末做 QEMU 视觉验证 + 截图对比 Win11。

---

## 9. 验收标准（每阶段必过）

| 类别 | 检查 |
|---|---|
| **稳定性** | QEMU 10 次启动全部进入桌面；连续运行 10 分钟无崩溃 |
| **响应** | 鼠标点击到视觉反馈 ≤ 100 ms；窗口拖动跟手（无 > 33 ms 延迟帧） |
| **视觉** | 与 Win11 / macOS 截图横向对比：圆角、间距、字体、颜色无明显廉价感 |
| **完整** | 14 个原应用全部可用；Dock/StartMenu/NotificationCenter/ControlCenter 全通 |
| **辅助** | 高对比度模式、缩放、IME 输入中文 — 至少 1 个完整闭环 |
| **代码质量** | 每个新模块 ≤ 600 行，通过 H-L 静态检查零违规 |

---

## 10. 决策记录（已确认，开工即用）

| # | 议题 | 决定 | 备注 |
|---|---|---|---|
| 1 | 视觉风格 | **Win11 Fluent**（任务栏居中 + 开始菜单 + Snap） | 不做 macOS 风可切换 |
| 2 | 强调色默认 | **Win11 蓝 #0078D4** + 6 种备选 | 设置中可切换 |
| 3 | 字体方案 | **自绘位图字体**（13/15/17/22 px × ASCII + 3500 CJK） | 零外部依赖，无 TTF |
| 4 | 毛玻璃 | **启用**，QEMU 检测性能不足自动降级为半透明纯色 | 运行时探测 |
| 5 | 多形态 | **纳入**：桌面 / 笔记本 / 平板 / 手机 / 嵌入屏统一代码 | 含多显示器 |
| 6 | 输入 | **多态**：鼠标 + 键盘 + 触控（多指）+ 触控笔 + 串口回退 | 统一 PointerEvent |

---

## 附录 A — 模块清单（新增 / 大改）

**新增（~40 模块）：**
- Layer 0–2：`gfx_backbuffer`、`gfx_aa`、`gfx_path`、`gfx_gradient`、`gfx_blur`、`gfx_shadow`、`gfx_anim`、`compositor`、`font_atlas`
- Layer 3：`wm_snap`、`wm_workspaces`、`wm_overview`
- Layer 4：25 个 `widget_*`
- Layer 5：`shell_topbar`、`shell_dock`、`shell_startmenu`、`shell_spotlight`、`shell_controlcenter`、`shell_lockscreen`、`shell_wallpaper`、`shell_notification`
- 服务：`clipboard`、`dnd`、`ime`、`i18n`、`a11y`

**大改（≥ 50% 重写）：**
- `vesa.hl`（接入双缓冲）
- `wm.hl`（接入合成器 + 装饰新设计）
- `mouse.hl`（指针图像 + 加速）
- `font.hl`（多字号 + 子像素）
- `ui_theme.hl`（完整 token 系统）
- `ui_controls.hl`（拆分到 widget_* 后废弃）
- `ui_desktop.hl`（拆分到 shell_* 后废弃）

总新增代码估算：**~18,000 行 H-L**。

---

## 附录 B — Sprint G1 落地状态（2026-05-20）

Sprint G1 完成 **脚手架** 阶段：47 个新模块全部入库（`bare-kernel/hl/`），数据结构与公共 API 定义就位，渲染 / 输入 / 合成的具体实现将在 G2–G8 逐步接通。

| 模块 | 层 | 状态 |
|---|---|---|
| `gfx_backbuffer` / `gfx_aa` / `gfx_path` / `gfx_blur` / `gfx_shadow` / `gfx_anim` / `gfx_hidpi` | L0–2 | 脚手架 ✅ |
| `compositor` / `font_atlas` | L2 | 脚手架 ✅ |
| `wm_snap` / `vdesktop` / `mission_control` / `display_topology` | L3 | 脚手架 ✅ |
| `widget_core` / `widget_button` / `widget_input` / `widget_select` / `widget_list` / `widget_nav` / `widget_container` / `widget_feedback` | L4 | 脚手架 ✅（8 个，对应原计划 25 个的 1/3） |
| `adaptive_layout` | L5 | 脚手架 ✅ |
| `shell_topbar` / `shell_dock` / `shell_startmenu` / `shell_spotlight` / `shell_controlcenter` / `shell_notification` / `shell_lockscreen` / `shell_wallpaper` / `shell_themes` / `shell_form` | L6 | 脚手架 ✅（10 个，含原计划 8 个 + `shell_themes` + `shell_form`） |
| `app_files` / `app_settings` / `app_terminal` / `app_texteditor` / `app_sysmon` | L7 | 脚手架 ✅（5 个，覆盖原 14 个 ui_app 的核心 5 个，其余继续沿用 ui_*） |
| `input_pointer` / `input_gesture` / `input_touch` / `input_pen` | 输入 | 脚手架 ✅（统一 PointerEvent） |
| `dnd` / `ime` / `a11y` / `eyecare` / `anim_tuning` / `visual_audit` | 服务 | 脚手架 ✅ |

**未启动**：`gfx_gradient`、`wm_workspaces`（合并入 `vdesktop`）、`wm_overview`（合并入 `mission_control`）、`clipboard`（沿用既有）、`i18n`（沿用既有）、剩余 ~17 个 `widget_*`。

**审计脚本**：`scripts/gui-lex-audit.ps1` / `gui-ast-audit.ps1` / `gui-symbol-audit.ps1` 落地，作为 GUI 模块进入 codegen 流水线前的硬门。

**对编译流水线影响**：47 GUI 模块尚未接入 `kernel_init.hl`，启动链路与 QEMU 10/10 稳定性不变。下一步（G2）开始让 `gfx_backbuffer` 和 `compositor` 进入 codegen 联调，同步 codegen Sprint 39 处理 `_ke_putc` 调用约定。
