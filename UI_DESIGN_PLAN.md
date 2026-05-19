# HicOS UI 设计策划案 · 商用级标准

> 版本：2.0  
> 基准：Windows 11 Fluent Design System / macOS Human Interface Guidelines  
> 目标：在裸机 x86_64 环境中实现与 Windows OS、macOS 同等商用等级的视觉质量与交互体验  
> 适用模块：`ui_theme.hl` `ui_controls.hl` `ui_desktop.hl` `wm.hl` 及全部 `ui_*.hl`

---

## 一、设计哲学

### 1.1 商用级 UI 的核心定义

| 维度 | Windows 11 / macOS 达成的标准 | HicOS 目标 |
|------|-------------------------------|-----------|
| 视觉一致性 | 每个像素都在设计系统约束内 | 全局 Design Token 驱动，零手动硬编码 |
| 交互响应速度 | ≤16ms 帧时间，操作无卡顿感 | Dirty-rect 增量渲染 + 软件合成器 |
| 焦点与无障碍 | 任意控件均可键盘访问，高对比度模式 | 完整 Focus Ring 系统 + 高对比主题 |
| 动效品质 | 缓动曲线精确，过渡自然不突兀 | 全局缓动函数库，支持减少动效模式 |
| 排版层级 | 字体尺寸/权重层级严格分级 | 8 级字体标度，位图字体覆盖全部层级 |
| 错误体验 | 错误有上下文、原因、修复建议 | 三段式错误卡片（标题/说明/操作） |
| 系统安全感 | 危险操作有确认、可撤销 | 确认对话框 + Toast 撤销时间窗 |

### 1.2 设计三原则

**① 精确（Precision）**  
每个控件的位置、尺寸、间距均来自 Token 系统，不允许"差不多"。容器内边距、按钮高度、图标尺寸全部基于 4px 基础网格的整数倍。

**② 层次（Hierarchy）**  
视觉层次由海拔（Elevation）、色彩对比度、字重三个维度共同决定。用户视线应从最重要的元素出发，沿设计意图流动。

**③ 呼吸（Breathing Room）**  
充足的留白是商用 UI 与业余 UI 最显著的区别。所有容器必须预留最小内边距，文字行间距不低于字体尺寸的 1.5 倍。

---

## 二、设计令牌系统（Design Tokens）

> Design Token 是设计系统的原子单位。所有 UI 代码只允许引用 Token，禁止直接写入裸色值或像素数值。

### 2.1 基础网格

```
基础单元（Base Unit） = 4px

间距标度（Spacing Scale）：
  space-1   =  4px
  space-2   =  8px
  space-3   = 12px
  space-4   = 16px
  space-5   = 20px
  space-6   = 24px
  space-8   = 32px
  space-10  = 40px
  space-12  = 48px
  space-16  = 64px
```

### 2.2 色彩系统

#### 基础色板（Primitives）— 不直接使用，供语义色引用

```
Gray
  gray-50   #F8FAFC
  gray-100  #F1F5F9
  gray-200  #E2E8F0
  gray-300  #CBD5E1
  gray-400  #94A3B8
  gray-500  #64748B
  gray-600  #475569
  gray-700  #334155
  gray-800  #1E293B
  gray-900  #0F172A
  gray-950  #080F1A

Blue（品牌主色）
  blue-300  #93C5FD
  blue-400  #60A5FA
  blue-500  #3B82F6
  blue-600  #2563EB
  blue-700  #1D4ED8

Cyan（强调）
  cyan-400  #22D3EE
  cyan-500  #06B6D4

Green（成功）
  green-400 #4ADE80
  green-500 #22C55E
  green-600 #16A34A

Yellow（警告）
  yellow-400 #FACC15
  yellow-500 #EAB308

Red（错误/危险）
  red-400   #F87171
  red-500   #EF4444
  red-600   #DC2626

Purple（次强调）
  purple-400 #C084FC
  purple-500 #A855F7
```

#### 语义色令牌（Dark Mode — 默认主题）

```
背景层
  bg-base          gray-950   #080F1A   ← 最底层（桌面/系统背景）
  bg-surface       gray-900   #0F172A   ← 应用窗口背景
  bg-elevated      gray-800   #1E293B   ← 浮层、卡片、侧边栏
  bg-overlay       gray-700   #334155   ← 下拉菜单、工具提示
  bg-input         gray-800   #1E293B   ← 输入框内部
  bg-hover         gray-700/40           ← 悬停态半透明蒙层
  bg-pressed       gray-700/60           ← 按下态蒙层
  bg-selected      blue-600/30           ← 选中高亮蒙层

前景（文字）
  text-primary     gray-50    #F8FAFC   ← 正文、标题
  text-secondary   gray-400   #94A3B8   ← 副文本、占位符
  text-disabled    gray-600   #475569   ← 禁用态文字
  text-inverse     gray-950   #080F1A   ← 浅色背景上的文字
  text-link        blue-400   #60A5FA   ← 超链接
  text-danger      red-400    #F87171   ← 错误提示
  text-success     green-400  #4ADE80   ← 成功提示
  text-warning     yellow-400 #FACC15   ← 警告提示

边框
  border-subtle    gray-700/50           ← 轻描边（分割线）
  border-default   gray-600   #475569   ← 常规边框
  border-strong    gray-400   #94A3B8   ← 强调边框（焦点）
  border-focus     blue-500   #3B82F6   ← 焦点环

品牌/交互
  accent-primary   blue-500   #3B82F6
  accent-hover     blue-400   #60A5FA
  accent-pressed   blue-600   #2563EB
  accent-muted     blue-600/20

状态色
  status-success   green-500  #22C55E
  status-warning   yellow-500 #EAB308
  status-error     red-500    #EF4444
  status-info      cyan-500   #06B6D4
```

#### 语义色令牌（Light Mode — 浅色主题）

```
bg-base          gray-100   #F1F5F9
bg-surface       #FFFFFF
bg-elevated      gray-50    #F8FAFC
bg-overlay       gray-100   #F1F5F9
bg-input         #FFFFFF
bg-hover         gray-200/60
bg-selected      blue-500/15

text-primary     gray-900   #0F172A
text-secondary   gray-500   #64748B
text-disabled    gray-400   #94A3B8

border-subtle    gray-200   #E2E8F0
border-default   gray-300   #CBD5E1
border-strong    gray-500   #64748B
border-focus     blue-500   #3B82F6
```

### 2.3 字体标度

HicOS 在裸机环境中使用位图字体，但字体分级规范必须与商用系统对齐：

```
字体家族优先级：
  HicOS Bitmap Sans（自研）→ 8×16 Latin / 16×16 CJK
  HicOS Mono（等宽）→ 终端、代码编辑器专用

字体标度（Type Scale）：
  display-xl   32px / weight-700 / line-height 1.2  ← 启动大标题
  display-lg   24px / weight-700 / line-height 1.2  ← 对话框主标题
  heading-xl   20px / weight-600 / line-height 1.3  ← 窗口标题
  heading-lg   18px / weight-600 / line-height 1.3  ← 侧边栏区块标题
  heading-md   16px / weight-600 / line-height 1.4  ← 卡片标题
  body-lg      16px / weight-400 / line-height 1.5  ← 正文大号
  body-md      14px / weight-400 / line-height 1.5  ← 正文常规（默认）
  body-sm      12px / weight-400 / line-height 1.5  ← 辅助说明、状态栏
  label        12px / weight-500 / line-height 1.4  ← 按钮标签、图标说明
  code         14px / weight-400 / line-height 1.6  ← 代码、终端输出
  mono-sm      12px / weight-400 / line-height 1.6  ← 路径、数值显示

字符间距（Letter Spacing）：
  heading: -0.01em（紧凑）
  body:     0em（默认）
  label:    0.02em（略宽，提升可读性）
  all-caps: 0.08em（全大写标签）
```

### 2.4 海拔系统（Elevation）

海拔通过阴影深度表达层级关系（软件渲染模拟）：

```
elevation-0   无阴影           ← 内嵌控件（输入框凹陷）
elevation-1   0 1px 2px rgba(0,0,0,0.4)   ← 基础卡片、面板
elevation-2   0 2px 8px rgba(0,0,0,0.5)   ← 悬浮控件、下拉菜单
elevation-3   0 4px 16px rgba(0,0,0,0.6)  ← 模态对话框、抽屉
elevation-4   0 8px 32px rgba(0,0,0,0.7)  ← 全局遮罩上方的浮层
elevation-5   0 16px 48px rgba(0,0,0,0.8) ← 通知 Toast、右键菜单

注：裸机软件渲染中，阴影以半透明边框像素近似实现。
亮色主题中阴影颜色改为 rgba(15,23,42,0.12)~rgba(15,23,42,0.30)。
```

### 2.5 圆角系统（Border Radius）

```
radius-none    0px    ← 截图、像素级精准边界
radius-sm      2px    ← 微型角（徽章、标签）
radius-md      4px    ← 按钮、输入框、列表项
radius-lg      6px    ← 卡片、面板
radius-xl      8px    ← 窗口、大卡片
radius-2xl    12px    ← 对话框、侧抽屉
radius-full   9999px  ← 胶囊形按钮、开关、头像
```

### 2.6 动效系统（Motion Tokens）

```
缓动函数（Easing）：
  ease-standard   cubic-bezier(0.2, 0.0, 0.0, 1.0)   ← 元素进入
  ease-decel      cubic-bezier(0.0, 0.0, 0.2, 1.0)   ← 元素离开
  ease-accel      cubic-bezier(0.4, 0.0, 1.0, 1.0)   ← 快速消失
  ease-spring     cubic-bezier(0.34, 1.56, 0.64, 1.0) ← 弹性弹出

持续时间（Duration）：
  duration-instant   0ms    ← 无需动效（立即响应）
  duration-fast     100ms   ← 微交互（按钮按下）
  duration-normal   200ms   ← 常规过渡（面板展开）
  duration-slow     300ms   ← 页面级切换
  duration-xslow    400ms   ← 模态框入场

减少动效模式（Reduced Motion）：
  所有非必要动效时长压缩为 0ms 或使用淡入替代位移。
```

---

## 三、窗口系统规范

### 3.1 窗口结构

```
┌──────────────────────────────────────────────────────────────┐
│ ██ [•][−][□]  窗口标题（heading-xl）          [搜索] [菜单]  │  ← 标题栏 32px
├──────────────────────────────────────────────────────────────┤
│ ┌──────────┐                                                  │
│ │          │  主内容区                                        │  ← 内容区
│ │  侧边栏  │                                                  │
│ │  (可选)  │                                                  │
│ └──────────┘                                                  │
├──────────────────────────────────────────────────────────────┤
│  状态信息 ·················· 进度 ─────── 项目数量           │  ← 状态栏 22px
└──────────────────────────────────────────────────────────────┘
```

### 3.2 标题栏规范

| 属性 | 规格 |
|------|------|
| 高度 | 32px（macOS 风格紧凑）|
| 背景 | `bg-elevated` |
| 左侧控制按钮组 | 关闭（红 #FF5F57）最小化（黄 #FEBC2E）最大化（绿 #28C840），尺寸 12px，间距 6px |
| 标题文字 | `body-md weight-600 text-primary`，水平居中 |
| 右侧工具区 | 应用自定义按钮（24×24px 图标按钮） |
| 拖拽区域 | 标题栏全宽可拖动（控制按钮区除外） |
| 双击行为 | 最大化/还原窗口 |
| 非焦点态 | 标题文字变为 `text-secondary`，控制按钮变为纯灰色 |

### 3.3 窗口层级（Z-Order）

```
Z 层级定义（从低到高）：
  z-desktop         0    ← 桌面壁纸
  z-window          10   ← 普通窗口
  z-window-focused  11   ← 当前激活窗口（同级中最高）
  z-always-on-top   20   ← 置顶窗口
  z-dock            30   ← Dock/任务栏（始终可见）
  z-menubar         31   ← 顶部菜单栏
  z-dropdown        40   ← 下拉菜单
  z-tooltip         50   ← 工具提示
  z-notification    60   ← 系统通知 Toast
  z-modal-backdrop  70   ← 模态遮罩
  z-modal           71   ← 模态对话框
  z-context-menu    80   ← 右键菜单
  z-system-alert    90   ← 系统级强制弹窗（权限、错误）
```

### 3.4 窗口状态机

```
状态：Normal ↔ Maximized ↔ Minimized ↔ Fullscreen

Normal → Maximized：   动效 duration-slow ease-standard（展开至全屏）
Maximized → Normal：  动效 duration-slow ease-decel（收缩至原位）
Normal → Minimized：   动效 duration-normal（缩小并飞入 Dock）
Minimized → Normal：  动效 duration-normal ease-spring（从 Dock 弹出）

拖拽行为：
  - 拖至屏幕左/右边缘：触发贴靠（Snap）至半屏
  - 拖至屏幕顶部：触发最大化预览
  - 贴靠预览：半透明蓝色覆盖层 accent-muted

窗口阴影：
  焦点窗口：elevation-3
  非焦点窗口：elevation-1（降低视觉重量）
```

### 3.5 边框与调整尺寸

```
可调整区域宽度：8px（四边 + 四角，角区域 = 16×16px）
最小窗口尺寸：320×200px
调整时实时重绘内容（不使用幻影矩形）
调整光标：
  上下边：resize-ns
  左右边：resize-ew
  四角：  resize-nwse / resize-nesw
```

---

## 四、控件系统规范

### 4.1 按钮（Button）

#### 变体矩阵

| 变体 | 用途 | 背景 | 文字 | 边框 |
|------|------|------|------|------|
| Primary | 最主要操作（每页唯一）| `accent-primary` | white | 无 |
| Secondary | 次要操作 | `bg-elevated` | `text-primary` | `border-default` |
| Ghost | 低优先级操作 | 透明 | `text-secondary` | 无 |
| Danger | 不可逆危险操作 | `red-600` | white | 无 |
| Link | 内联文字操作 | 透明 | `text-link` | 无，下划线 |

#### 尺寸标准

```
Size-SM：高度 28px，水平内边距 12px，label 字体
Size-MD：高度 32px，水平内边距 16px，body-sm 字体（默认）
Size-LG：高度 40px，水平内边距 20px，body-md 字体
Size-XL：高度 48px，水平内边距 24px，body-lg 字体
```

#### 状态规格

```
Default:  背景色 = 变体默认
Hover:    背景色偏亮 5%，过渡 duration-fast ease-standard
Pressed:  背景色偏暗 10%，scale(0.98)，过渡 duration-instant
Focus:    外描边 border-focus 2px，offset 2px
Disabled: opacity 0.38，cursor not-allowed，不响应事件
Loading:  文字变为旋转图标（Spinner 16px），禁止重复点击
```

#### 图标按钮

```
Icon-SM：24×24px，图标 14px
Icon-MD：32×32px，图标 16px（默认）
Icon-LG：40×40px，图标 20px

圆角：radius-md（方形）或 radius-full（圆形）
悬停背景：bg-hover
```

### 4.2 输入框（Input / TextField）

```
结构：
  [前置图标?] [占位符/内容文字] [清除按钮?] [后置图标?]

高度规格：
  SM: 28px   MD: 36px（默认）   LG: 44px

背景：bg-input
边框：
  Default:  border-default 1px
  Hover:    border-strong 1px
  Focus:    border-focus 2px（不是描边，而是实际边框加粗）
  Error:    border-danger red-500 2px
  Disabled: opacity 0.38，不可交互

占位符：text-secondary
输入文字：text-primary body-md

光标：
  颜色：accent-primary
  宽度：2px
  闪烁频率：530ms 开 / 530ms 关

文字选择高亮：accent-primary/30

错误提示（Error Message）：
  位置：输入框下方 4px，左对齐
  样式：body-sm text-danger
  带图标：⚠ 12px 图标 + 文字间距 4px

字符计数（可选）：
  位置：右下角
  样式：body-sm text-secondary
  接近上限（>80%）：text-warning
  超出上限：text-danger
```

### 4.3 下拉选择（Select / Dropdown）

```
外观与 Input 一致
展开时：
  面板背景：bg-overlay（elevation-2）
  最大高度：240px，超出滚动
  选项高度：36px，内边距 12px
  选项悬停：bg-hover
  选项选中：bg-selected + text-primary weight-500 + 右侧勾选图标
  键盘：↑↓ 导航，Enter 确认，Esc 关闭，字母键跳转到首字母匹配项
```

### 4.4 复选框（Checkbox）与开关（Toggle）

#### Checkbox
```
尺寸：16×16px（SM）/ 18×18px（MD，默认）/ 20×20px（LG）
边框：border-default 2px，radius-sm
选中：bg-accent-primary，白色勾图标
半选：bg-accent-primary，白色横线图标（三态）
Hover：border-strong
Focus：border-focus 2px + offset 2px
Label 间距：8px，body-md text-primary
```

#### Toggle Switch
```
轨道尺寸：40×22px，radius-full
滑块尺寸：18×18px，白色 radius-full
Off 态：轨道 bg-elevated border-default
On 态：轨道 accent-primary，过渡 duration-normal ease-standard
Hover：轨道透明度 +10%
焦点：外描边 border-focus
```

### 4.5 列表与表格

#### 列表项（List Item）

```
高度：36px（紧凑）/ 44px（标准）/ 56px（带副标题）
内边距：水平 12px，垂直居中
结构：[前置图标 16px, 间距 10px] [主文字 body-md] [副文字 body-sm text-secondary] [后置区域]

悬停：bg-hover（覆盖层，不改变背景）
选中：bg-selected，左侧 3px accent-primary 高亮竖条
焦点：border-focus 描边

多选：右侧复选框淡入（仅在多选模式激活时显示）

分组标题（Group Header）：
  高度：28px，文字 label all-caps text-secondary，内边距 12px
  不可点击，不参与键盘导航
```

#### 表格（Table）

```
表头：
  高度：36px，bg-elevated
  文字：label weight-600 text-secondary
  可排序列：悬停显示排序箭头，点击切换升/降序，激活列标题文字变 text-primary
  列宽：可拖拽调整

数据行：
  高度：36px（紧凑）/ 44px（标准）
  奇偶行：相同（不使用斑马纹，除非用户主题开启）
  悬停：bg-hover
  选中：bg-selected

单元格：
  内边距：水平 12px
  文字溢出：省略号 + 悬停显示完整内容 Tooltip

固定列：左侧最多 2 列可固定，右侧显示分隔阴影 elevation-1
虚拟滚动：超过 100 行启用，只渲染可见区域 ±3 行缓冲
```

### 4.6 滚动条

```
轨道宽度：
  悬停前：4px（细条，Overlay 风格）
  悬停后：8px（展开）

轨道背景：透明
滑块：
  Default：bg-overlay opacity-40，radius-full
  Hover：opacity-70
  Drag：opacity-100，accent-primary
  最小滑块高度：24px

自动隐藏：鼠标离开容器后 1.5s 淡出（opacity 0，duration-slow）
键盘：PageUp/PageDown = 视口高度 ×0.9 步进，↑↓ = 单行步进
```

### 4.7 进度指示

#### 进度条（Progress Bar）

```
高度：4px（线型）/ 8px（标准）/ 16px（粗型）
背景轨道：bg-elevated
填充：accent-primary，radius-full
动效：fill 过渡 duration-normal

不确定态（Indeterminate）：
  光条从左至右无限循环，使用 gradient 实现发光效果
  持续时间：1.4s，linear
```

#### 旋转加载（Spinner）

```
尺寸：16px（SM）/ 24px（MD）/ 32px（LG）
颜色：accent-primary
旋转周期：800ms，linear
线宽：2px
轨道颜色：border-subtle
```

#### 骨架屏（Skeleton）

```
颜色：bg-elevated → bg-overlay（渐变动画）
动效：600ms 的 shimmer 扫光效果，2s 循环
形状：文字行用圆角矩形替代，图片用完整矩形替代
```

### 4.8 对话框（Dialog）

```
遮罩：全屏 rgba(0,0,0,0.5)，点击不关闭（强制确认场景）
         或 rgba(0,0,0,0.3)，点击可关闭（可选操作场景）

对话框面板：
  背景：bg-surface
  圆角：radius-2xl
  阴影：elevation-4
  最大宽度：560px（标准）/ 720px（宽型）
  内边距：24px

结构：
  ┌────────────────────────────────┐
  │ [图标 24px]  标题 heading-lg   │  ← 24px 内边距
  │                                │
  │ 正文说明 body-md text-secondary │  ← body-lg 区域
  │ 可以是多行文字、表单或列表      │
  │                                │
  │ ──────────────────────────────  │  ← 分割线（可选）
  │             [取消]  [确认]      │  ← 按钮行，右对齐
  └────────────────────────────────┘

入场动效：duration-slow ease-spring，scale 0.95→1.0 + opacity 0→1
离场动效：duration-fast ease-accel，opacity 1→0

确认危险操作（Danger Dialog）：
  确认按钮使用 Danger 变体
  标题前使用红色警告图标
  强制要求用户输入确认字符串（macOS 行为）时，输入框匹配正确才启用确认按钮
```

### 4.9 通知与 Toast

```
位置：屏幕右下角，distance-from-edge = 16px
宽度：320px（固定）
堆叠：多条时纵向排列，间距 8px，最多同时显示 3 条，超出时折叠

结构：
  ┌─────────────────────────────────┐
  │ [图标]  标题 body-md weight-600  │
  │         副文字 body-sm text-sec  │  ← 可选
  │                    [操作按钮?]   │  ← Ghost 按钮
  └─────────────────────────────────┘
  背景：bg-overlay elevation-4
  左侧：4px 彩色边条（状态色）
  圆角：radius-lg

自动消失：
  Info/Success：4000ms
  Warning：6000ms
  Error：不自动消失，需用户手动关闭

入场：从右侧滑入，duration-normal ease-decel
离场：向右滑出 + 淡出，duration-fast ease-accel

进度条：底部 2px 细条随倒计时缩短（仅自动消失类型）
```

### 4.10 工具提示（Tooltip）

```
触发：悬停 600ms 后显示，鼠标离开立即隐藏
最大宽度：240px
内边距：space-2 × space-3（垂直×水平）
背景：bg-overlay elevation-3
文字：body-sm text-primary
圆角：radius-md

方向自适应：
  优先显示在元素上方，检测视口边界后自动翻转

箭头：5px 等腰三角形，颜色同背景

长文本（Rich Tooltip）：
  支持粗体、换行
  最大 2 行描述 + 可选快捷键标注（kbd 样式）
```

### 4.11 菜单系统

#### 右键菜单（Context Menu）

```
宽度：160px~280px（内容自适应）
背景：bg-overlay elevation-4，radius-lg
内边距：space-1（上下）

菜单项高度：32px
图标：16px，左侧 12px
文字：body-md text-primary，间距 8px
快捷键：右对齐 body-sm text-secondary
箭头（子菜单）：右侧 ▶ 图标

分割线：border-subtle 1px，垂直间距 4px
危险项：text-danger（例如"删除"）

禁用项：opacity 0.38，cursor default，不响应事件
悬停：bg-hover

子菜单：
  出现在父项右侧（或左侧，视视口空间）
  延迟 150ms 展开，防止误触
  保持父项悬停高亮

键盘：
  ↑↓ 导航，→ 进入子菜单，← 返回父菜单，Enter 执行，Esc 关闭
```

#### 菜单栏（Menu Bar）— 类 macOS 全局菜单

```
高度：22px
位置：屏幕顶部（全局菜单模式）或窗口标题栏下方（Windows 模式）
背景：bg-base 半透明 + 毛玻璃效果（软件模拟：blur 参数等效处理）

菜单项：
  内边距：水平 10px，垂直 2px
  文字：body-sm weight-500
  活跃下拉：bg-elevated，高亮色
```

---

## 五、桌面环境规范

### 5.1 桌面壁纸系统

```
默认壁纸：抽象几何渐变（纯软件生成，无外部图像资源）
  主题 Dark：深蓝/紫色放射状渐变（品牌色调）
  主题 Light：浅灰/白色柔和渐变

壁纸渲染方式：
  - 纯色填充（极简模式）
  - 线性渐变（CPU 软件渲染）
  - 预置程序化图案（Hilbert 曲线、网格、几何分形）

壁纸不影响系统性能（一次绘制后缓存到帧缓冲背景层，不频繁重绘）
```

### 5.2 Dock 栏规范（类 macOS Dock）

```
位置：屏幕底部居中
高度：64px（含外边距）图标尺寸 48×48px
背景：bg-overlay/80 + 毛玻璃效果，radius-2xl
外边距：距底部 8px

图标：
  圆角：radius-xl（约 22% 尺寸）
  悬停：放大至 56px，邻近图标微向两侧偏移（macOS 鱼眼效果）
  激活（应用运行中）：图标底部 4px 圆点，accent-primary
  拖拽排序：图标可拖拽重排，拖离 Dock 时可移除

分隔线：1px border-subtle 垂直线，将应用区与系统功能区分隔

磁力效果（Magnification）：
  中心图标放大 1.6×，线性衰减至相邻 ±2 图标恢复原大小
  过渡 duration-fast ease-standard

弹跳动效：
  应用启动时图标弹跳（scale 1.0→1.3→1.0，3次循环，每次 300ms）
```

### 5.3 顶部状态栏（Menu Bar / System Bar）

```
高度：22px（macOS 风格）或 28px（Windows 风格）
背景：bg-base/90 + 模糊

左侧（系统信息区）：
  ⌘ HicOS Logo（点击显示关于）
  应用名称（当前前台应用）
  应用菜单项

右侧（系统状态区，从右至左）：
  时钟：body-sm，精确到分钟，悬停显示完整日期
  网络状态图标（WiFi/有线/离线）
  音量图标（点击滑动调节）
  电量图标（有电池时显示）
  通知中心按钮（有未读时带红色徽章）
  快捷操作中心（⊕ 图标，点击展开面板）

所有状态图标：
  尺寸 16×16px
  间距：space-2
  点击展开弹出面板（elevation-3）
```

### 5.4 桌面图标与快捷方式

```
桌面图标尺寸：56×56px
图标文字：label，白色 + 文字阴影（黑色 0 1px 3px，确保壁纸可读性）
选中态：bg-selected/40 圆角矩形覆盖
拖拽：半透明跟随鼠标，不影响底层布局
双击：打开对应应用/文件

网格对齐：
  网格单元：80×88px（图标 56px + 标题 2行）
  对齐方向：右对齐到屏幕边缘（Windows 风格）或自由放置（macOS 风格）
```

### 5.5 任务切换器（Alt+Tab）

```
触发：Alt+Tab 显示，松开 Alt 确认选择
面板：水平居中浮层，elevation-4，bg-overlay
图标尺寸：64px，间距 12px
选中高亮：bg-selected/40，border-focus 2px，radius-xl
窗口预览：图标上方显示小型窗口截图缩略图（64×40px，elevation-2）
应用名称：图标下方，body-sm，最长 10 字符后省略

快捷键：
  Alt+Tab：向右切换
  Alt+Shift+Tab：向左切换
  Alt+`（反引号）：同一应用多窗口间切换
```

---

## 六、核心系统应用规范

### 6.1 终端（Terminal）

```
主题配色（内置 4 套）：
  ① HicOS Dark（默认）：#0D1117 背景，#C9D1D9 前景，品牌色光标
  ② HicOS Light：#F0F0F0 背景，#1F2328 前景
  ③ Solarized Dark：经典配色
  ④ High Contrast：无障碍专用

字体：HicOS Mono 14px，line-height 1.6

光标样式：
  Block（默认，使用中）/I-beam（插入模式）/Underline（可设置）
  颜色 accent-primary，闪烁 530ms 间隔

滚动：
  历史行数上限：10,000 行（可设置）
  滚动条：Overlay 风格，右侧 4→8px
  Shift+PageUp/Down：按屏滚动

Tab 标签（多会话）：
  标签栏高度：28px，bg-elevated
  标签宽度：自适应，最小 80px，最大 200px
  当前标签：bg-surface，无底边
  新建标签：+ 按钮，关闭：×（悬停显示）
  拖拽重排标签

侧边栏（可折叠）：
  会话树：多会话、SSH 收藏夹
  宽度：200px，可拖拽调整

选区与复制：
  鼠标拖拽选区，自动复制到剪贴板（可配置）
  双击选词，三击选行
  右键菜单：复制 / 粘贴 / 清屏 / 查找

查找栏（Ctrl+F）：
  浮层出现在右上角，当前匹配高亮，可循环跳转
  支持正则表达式
```

### 6.2 文件管理器（Files）

```
布局模式（三种，可切换）：
  ① 双栏：左侧导航树 + 右侧文件列表（默认）
  ② 单栏：纯文件列表，适合全屏使用
  ③ Gallery：大图预览（图片/媒体文件夹）

左侧导航面板（宽度 220px）：
  固定区域：
    ★ 收藏夹（用户自定义）
    🕐 最近（按时间排序最近访问）
    🗑 回收站
  设备区域：
    系统盘、可移动磁盘（自动检测挂载）
    每个设备显示容量进度条（mini，4px）

面包屑导航栏（Breadcrumb）：
  样式：/ 分隔，可点击跳转任意祖先目录
  末尾：可编辑（点击末尾空白处变为路径输入框）
  右侧：搜索框（Ctrl+F 激活）、视图切换按钮、排序按钮

文件列表（列表视图）：
  列：名称 / 大小 / 类型 / 修改日期（可配置显示/隐藏）
  行高：36px
  图标：16px 类型图标（文件夹/文档/图片/音频/视频/代码/压缩包）
  名称：body-md，可内联重命名（F2 触发，双击文字区）
  排序：点击列表头，支持 Name/Size/Date/Type
  批量选择：Ctrl+点击，Shift+点击，Ctrl+A

右键菜单（标准项）：
  打开 / 以……打开 / 新建文件夹 / 剪切 / 复制 / 粘贴 / 删除（移至回收站）/ 重命名 / 属性

底部状态栏：
  左：所选文件数量 + 总大小
  中：当前路径磁盘使用量（x GB / y GB，含mini进度条）
  右：视图模式切换图标

文件操作进度（大文件）：
  底部浮出进度条，可暂停/取消
  完成后 Toast 通知（含打开目标目录按钮）

搜索（Ctrl+F）：
  实时过滤当前目录（前缀匹配）
  全盘搜索（Enter 触发，展示结果列表带路径）
```

### 6.3 设置中心（Settings）

```
整体布局：
  左侧：分类导航（宽度 240px，可折叠）
  右侧：设置详情（最大宽度 720px，居中）
  顶部：搜索框（全局搜索设置项）

分类导航项（图标 + 标签，高度 40px）：
  👤 账户与安全
  🎨 外观与主题
  🖥 显示
  🔊 声音
  ⌨ 键盘与鼠标
  🌐 网络
  💾 存储
  🔔 通知
  🔒 隐私
  ⚡ 电源
  ♿ 无障碍
  🔧 高级系统
  ℹ 关于 HicOS

设置项规范：
  标题：body-md weight-600
  副文字：body-sm text-secondary（描述该设置的作用）
  控件：右对齐（Toggle、Select 等）
  每组设置用 Card（bg-elevated，radius-lg，内边距 16px）包裹
  每张 Card 最多 5 项，超出分卡

外观设置（完整规格）：
  主题模式：浅色 / 深色 / 跟随系统
  强调色：7 个预设色 + 自定义颜色选择器
  圆角风格：小 / 中 / 大（映射 radius 标度）
  透明效果：开关（关闭时停用毛玻璃效果，提升性能）
  减少动效：开关（A11y 需求）
  字体大小：小 / 中 / 大 / 超大（影响 text-scale-factor）
  Dock 位置：底部 / 左侧 / 右侧
  Dock 大小：滑块（32px~80px）

无障碍设置：
  高对比度模式：开关（覆盖所有颜色令牌至 AA 标准）
  减少动效：开关
  增大光标：开关（光标尺寸 ×2）
  屏幕阅读器支持：开关（文字转语音提示，需 audio.hl 支持）
  焦点环加粗：开关（border-focus 从 2px 升至 3px）
```

### 6.4 系统监控（System Monitor）

```
标签页：
  概览 / 进程 / 性能 / 磁盘 / 网络 / GPU

概览面板（仪表盘）：
  4 个指标卡片（CPU / 内存 / 磁盘 / 网络）
  每卡片：
    大号数值（display-lg weight-700）
    实时迷你折线图（60s 历史）
    趋势箭头

进程列表：
  列：PID / 进程名 / CPU% / 内存 / 状态 / 用户
  按 CPU% 降序默认排序
  搜索框：实时过滤
  右键菜单：强制结束 / 调整优先级 / 显示详情
  危险进程（CPU>80% 持续）：行背景浅红色警示

性能图表：
  每指标一个独立面板，历史 5 分钟折线图
  Y 轴自适应，X 轴滚动
  图表颜色：CPU 蓝，内存 绿，磁盘 黄，网络 紫

磁盘面板：
  每个挂载点横向进度条（使用/总量）
  颜色：<70% 绿，70-90% 黄，>90% 红
  SMART 状态指示灯
```

### 6.5 软件包管理器（Package Manager UI）

```
布局：
  顶部：搜索框（全宽，body-lg）+ 分类筛选器（横向标签）
  主区：软件卡片网格（每卡 200×240px，3~5 列自适应）
  侧边（详情面板）：点击卡片后右侧滑出，宽度 360px

软件卡片：
  图标（64×64px）
  名称（body-md weight-600）
  简短描述（body-sm text-secondary，2 行省略）
  版本号 / 大小（label text-secondary）
  安装按钮（Primary SM，已安装则变 Secondary "已安装"）

详情面板：
  完整描述
  截图轮播（如有）
  版本历史
  依赖列表
  安装/卸载/更新进度（内联进度条）

已安装视图：
  按字母/安装日期排序
  批量更新（"全部更新"按钮，数量徽章）
```

### 6.6 文本编辑器（Notepad++级别）

```
编辑器主区域：
  行号：右对齐，text-secondary，宽度自适应（最少 4 字符）
  当前行高亮：bg-hover 全行背景
  光标：2px 竖线，accent-primary，530ms 闪烁

折叠：
  可折叠区域（函数/大括号块）：左侧折叠图标 ▶/▼
  折叠后显示 "..." 占位

语法高亮（基于 syntax_highlight.hl）：
  关键字：blue-400 weight-600
  字符串：green-400
  注释：text-secondary italic
  数字：cyan-400
  函数名：purple-400
  类型/运算符：text-primary

状态栏：
  行:列 / 字符数 / 换行符 / 编码 / 缩进类型（Tab/Space N）

多标签：
  同 Terminal 标签栏规范
  未保存修改：标签名后显示 • 圆点

查找替换（Ctrl+H）：
  双行面板（查找框 + 替换框）
  选项：大小写 / 全词 / 正则
  "全部替换" 完成后 Toast 提示替换数量

小地图（Minimap）：
  右侧 80px 代码缩略图
  可见区域：高亮半透明矩形，可拖拽滚动
```

### 6.7 图形安装器（Installer）

```
步骤进度条（顶部）：
  ① 欢迎  ② 许可协议  ③ 磁盘分区  ④ 确认  ⑤ 安装  ⑥ 完成
  当前步骤：accent-primary 实心圆 + 步骤名
  已完成步骤：绿色勾选
  连接线：border-subtle

欢迎页：
  品牌大图（程序生成的几何艺术 Logo，256×256px）
  系统名称（display-xl weight-700）
  版本号（body-lg text-secondary）
  [新鲜安装] / [从 USB 启动体验] / [高级选项] 三个按钮

磁盘分区页：
  磁盘可视化：横向色块（分区用不同颜色区分）
  分区列表：表格展示 设备名/大小/文件系统/挂载点
  操作：全盘自动分区（推荐）/ 手动分区（高级）
  危险操作高亮：红色警告卡片

安装进度页：
  主进度条（全宽，8px，带百分比）
  当前步骤说明（body-md）
  日志输出区（可展开，滚动）
  禁止关闭系统提示（Danger Toast）

完成页：
  大绿色勾图标（动效绘制进来）
  "HicOS 已成功安装"（display-lg）
  [立即重启] / [继续体验（从 USB）] 两个按钮
```

---

## 七、启动体验规范（Boot UI）

### 7.1 开机 LOGO 画面

```
背景：纯黑 #000000
中心：HicOS 几何 Logo（程序生成 Hilbert 曲线徽章，白色线条，96×96px）
Logo 下方：系统名称 "HicOS" display-xl weight-100（极细字重，优雅感）
Logo 下方 32px：Loading 旋转圆环（24px，白色，opacity 0.8）

入场动效：
  Logo：scale 0.8→1.0 + opacity 0→1，duration-slow ease-spring
  文字：opacity 0→1，delay 200ms，duration-normal
  旋转环：opacity 0→1，delay 400ms

停留时间：硬件初始化期间持续显示（最少 1.2s，避免闪屏感）
```

### 7.2 启动进度界面

```
背景：同 LOGO 画面（黑色）
底部进度条：
  高度 2px，全宽，accent-primary
  不确定进度：shimmer 光条动效
  确定进度（知道百分比时）：平滑填充

左下角状态文字：body-sm text-secondary
  "正在初始化内核..."
  "正在加载驱动..."
  "正在启动图形系统..."

调试模式（按住 Shift）：
  切换为详细日志滚屏模式（类 Linux boot log 风格）
  每行带颜色状态标记：[  OK  ] 绿 / [WARN] 黄 / [FAIL] 红

开机时间显示（到达桌面后）：
  右下角 Toast："系统启动用时 3.2s"，4s 后自动消失
```

### 7.3 登录界面（锁屏/登录）

```
背景：壁纸高斯模糊（程序模拟，降低分辨率+大半径近似）
中心面板：bg-surface/80，宽度 380px，radius-2xl，elevation-4，内边距 32px

结构：
  头像（圆形，64×64px，radius-full）
  用户名（heading-md）
  密码输入框（Input LG，向下 16px）
  [登录] 按钮（Primary LG，全宽）
  
  ---
  [其他账户] [访客模式] [关机] [重启]

错误震动动效：
  密码错误时，输入框和按钮整体左右震动（translateX ±6px，100ms，3次）

时钟（锁屏时显示）：
  display-xl weight-200（极细字重）居中显示大时间
  body-md text-secondary 显示日期
```

---

## 八、无障碍规范（Accessibility）

### 8.1 颜色对比度（WCAG 2.1 AA 标准）

```
正文文字（text-primary on bg-surface）：    对比度 ≥ 7:1（AAA）
次级文字（text-secondary on bg-surface）：  对比度 ≥ 4.5:1（AA）
按钮文字（white on accent-primary）：        对比度 ≥ 4.5:1（AA）
图标（text-secondary on bg-elevated）：      对比度 ≥ 3:1（AA 非文本）

高对比度模式：
  所有文字对比度提升至 ≥ 7:1（AAA）
  边框从 1px 加粗至 2px
  取消半透明效果，全部使用纯色
```

### 8.2 键盘完全可访问

```
焦点遍历顺序：从左到右，从上到下（符合阅读顺序）
焦点环：2px border-focus 实线，offset 2px（确保在任何背景上可见）
跳过重复导航：Ctrl+M 跳过菜单栏直达主内容区
模态对话框：打开时焦点捕获在对话框内，关闭后焦点返回触发元素

所有图标按钮必须有 aria-label（屏幕阅读器描述）
所有表单控件必须有关联 Label
列表导航：方向键在列表项间导航，Home/End 跳到首/末项
```

### 8.3 减少动效支持

```
系统设置"减少动效"开启时：
  所有位移动效替换为简单淡入/淡出
  过渡时间压缩至 0ms（即时切换）
  Spinner 保留（必要的进度反馈）
  骨架屏 shimmer 效果关闭（改为静态骨架）
```

---

## 九、分辨率与 HiDPI 规范

```
支持分辨率档位：
  800×600     低分辨率最低支持（VESA 安全分辨率）
  1024×768    标准 4:3
  1280×720    HD 720p
  1366×768    主流笔记本
  1920×1080   Full HD（主目标分辨率）
  2560×1440   QHD
  3840×2160   4K（HiDPI 模式）

像素比例（Pixel Ratio）：
  1.0×：1920×1080 及以下
  1.5×：2560×1440（逻辑分辨率 1707×960）
  2.0×：4K（逻辑分辨率 1920×1080）

HiDPI 规则：
  所有尺寸基于逻辑像素（Logic Pixel）
  位图图标提供 1× 和 2× 两套
  线段、边框在 2× 模式下保持 1 逻辑像素（物理 2px，更锐利）
  字体位图在 2× 模式下使用 2× 版本（像素精确渲染）

自适应布局：
  960px 逻辑宽度以下：侧边栏默认折叠为抽屉式
  800px 逻辑宽度以下：双栏布局切换为单栏
```

---

## 十、主题系统规范

### 10.1 内置主题

```
① HicOS Dark（默认）
   基调：深蓝黑，冷色调，品牌蓝强调色
   适用：主力工作场景，低蓝光友好

② HicOS Light
   基调：纯白/浅灰，温暖中性，同蓝色强调
   适用：日光下使用，提升可读性

③ HicOS OLED
   基调：纯黑 #000000 背景（真OLED省电）
   适用：OLED 屏幕，极低功耗

④ High Contrast Dark（无障碍）
   基调：纯黑背景，纯白文字，黄色强调
   满足 WCAG AAA 标准

⑤ High Contrast Light（无障碍）
   基调：纯白背景，纯黑文字，蓝色强调
```

### 10.2 强调色定制

```
用户可从以下 8 色中选择强调色，系统自动生成衍生色调：
  蓝色（默认）#3B82F6
  青色         #06B6D4
  绿色         #22C55E
  紫色         #A855F7
  粉色         #EC4899
  橙色         #F97316
  红色         #EF4444
  银色         #94A3B8
```

---

## 十一、H-L 模块映射

| 设计规范区域 | 对应 H-L 模块 | 状态 |
|-------------|--------------|------|
| 色彩令牌系统 | `ui_theme.hl` | ✅ iter 124 |
| 基础控件库 | `ui_controls.hl` | ✅ iter 125 |
| 窗口管理器 | `wm.hl` | ✅ iter 120 |
| 图形终端 | `ui_terminal.hl` | ✅ iter 130 |
| 桌面与 Dock | `ui_desktop.hl` | ✅ iter 128 |
| 安装器 | `ui_installer.hl` | ✅ iter 129 |
| 文件管理器 | `ui_files.hl` | ✅ iter（待升级至本规范） |
| 设置中心 | `ui_settings.hl` | ✅ iter（待升级至本规范） |
| 系统监控 | `ui_sysmon.hl` | ✅ iter（待升级至本规范） |
| 通知系统 | `ui_notify.hl` | ✅ iter 128 |
| 对话框 | `ui_dialog.hl` | ✅ iter 128 |
| 主题引擎 | `ui_theme.hl` | 📋 需对照本规范全面更新 |
| Dock 鱼眼效果 | `wm.hl` | 📋 需新增 Magnification 逻辑 |
| 高对比度模式 | `ui_theme.hl` | 📋 需新增无障碍主题集 |
| 动效引擎 | `ui_controls.hl` | 📋 需新增 Motion Token 系统 |
| 文本编辑器 | `ui_text_editor.hl` | ✅ iter（待升级至本规范） |
| 软件包管理器 UI | `ui_pkgmgr.hl` | 📋 待新建 |
| 启动 Logo 动效 | `kernel_entry.hl` | 📋 需更新 Boot UI 序列 |
| HiDPI 渲染 | `framebuffer.hl` | 📋 需增加像素比例支持 |

---

## 十二、分阶段实施路线

### Phase A：设计令牌系统落地（优先级最高）

**目标：** 将本文档所有 Token 值编码进 `ui_theme.hl`，取代现有零散常量。

```
任务清单：
  □ 实现完整 Color Token 字典（Dark + Light 两套，80+ Token）
  □ 实现 Spacing Scale（12 个间距值）
  □ 实现 Typography Scale（10 个字体级别）
  □ 实现 Border Radius Scale（7 个值）
  □ 实现 Elevation（6 级阴影）
  □ 实现 Motion Token（5 个缓动 + 5 个时长）
  □ 实现主题切换机制（Dark/Light/High Contrast 运行时切换）
```

### Phase B：核心控件全面对齐

**目标：** `ui_controls.hl` 全面升级至本规范控件标准。

```
优先级排序（从高到低）：
  P1：Button（5 变体 × 4 尺寸 × 5 状态）
  P1：Input / TextField（含 Error 态、计数器）
  P1：List Item / 虚拟滚动
  P2：Dropdown / Select
  P2：Checkbox / Toggle
  P2：Dialog（含 Danger 变体）
  P2：Toast / Notification
  P3：Progress Bar / Spinner
  P3：Context Menu / Dropdown Menu
  P3：Tooltip
  P3：Table（含虚拟滚动）
  P4：Skeleton Screen
```

### Phase C：桌面环境商用化

```
□ Dock 鱼眼放大效果
□ Alt+Tab 任务切换器（含窗口缩略图）
□ 顶部菜单栏系统状态区（网络/音量/时钟）
□ 桌面右键菜单
□ 壁纸切换（程序生成多套几何图案）
□ 通知中心面板（右侧抽屉）
□ 快捷操作中心面板
□ 窗口贴靠（Snap 左/右半屏）
```

### Phase D：系统应用商用化

```
文件管理器：
  □ 面包屑导航 + 路径编辑
  □ 大图标/列表/详细三视图
  □ 快速预览（空格键）
  □ 拖拽操作 + 进度条
  □ 全盘搜索

设置中心：
  □ 外观设置完整实现（含实时预览）
  □ 无障碍设置全套
  □ 网络设置（连接管理）
  □ 显示设置（分辨率/缩放）

系统监控：
  □ 实时折线图（60s 历史）
  □ 进程详情与强制结束
  □ 磁盘 I/O 性能图

终端：
  □ 多标签支持
  □ 主题选择（4 套内置）
  □ 字体大小调节
  □ 查找功能
```

### Phase E：启动体验商用化

```
□ 开机 Logo 动效（几何品牌图标绘制动画）
□ 启动进度条（底部 2px 全宽）
□ 登录界面（密码输入 + 用户头像）
□ 锁屏界面（时钟 + 模糊壁纸）
□ 开机时间统计 Toast
```

---

## 十三、质量验收标准

每个 Phase 完成后，必须满足以下验收项：

### 视觉验收

- [ ] 所有颜色均来自 Design Token，无硬编码色值
- [ ] 所有间距为 4px 基础网格的整数倍
- [ ] 深色/浅色主题均可切换，无视觉破损
- [ ] 高对比度模式下所有文字对比度 ≥ 7:1

### 交互验收

- [ ] 所有控件可完全键盘操作（Tab 导航，Enter 确认，Esc 退出）
- [ ] 所有焦点元素有可见焦点环
- [ ] 所有按钮有 Hover/Pressed/Disabled 三态
- [ ] 危险操作有确认对话框

### 性能验收

- [ ] 窗口拖拽 / 调整大小全程 ≥30fps（30ms 以内重绘）
- [ ] 列表 1000 项以上使用虚拟滚动，滚动 ≥30fps
- [ ] 模态框打开时间 ≤100ms

### 一致性验收

- [ ] 相同类型的控件在所有应用中视觉行为一致
- [ ] 同一应用内各界面间切换过渡自然
- [ ] 错误提示格式（标题/说明/操作）统一

---

## 十四、基准参考

| 参考系统 | 借鉴要素 |
|---------|---------|
| **macOS Ventura/Sonoma** | Dock 鱼眼效果、标题栏设计、全局菜单栏、系统字体层级、对话框结构、通知位置 |
| **Windows 11 Fluent** | 圆角卡片系统、亚克力/毛玻璃效果（软件模拟）、Alt+Tab 体验、Snap 贴靠、设置中心布局 |
| **GNOME 44+** | 任务栏简洁设计、文件管理器双栏布局、控件无障碍实现参考 |
| **KDE Plasma 6** | 高度可定制主题系统、多分辨率支持策略 |

---

## 十五、设计一句话定位

**HicOS 的 UI 是：基于工程级 Design Token 体系，在裸机约束中实现完整商用桌面体验——每一像素有据可依，每一交互有迹可循。**

---

*本策划案 v2.0 基于 Windows 11 Fluent Design System 与 macOS Human Interface Guidelines 商用标准制定。*  
*修订日期：2026-05-19。*
