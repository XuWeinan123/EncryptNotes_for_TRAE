---
version: alpha
name: flomo
description: Capture-first card-note tool with crisp index cards, restrained leaf-green action, and quiet warm-neutral surfaces.
colors:
  primary: "#30CF79"
  primary-container: "#E6F9EF"
  primary-deep: "#397354"
  link: "#6890F8"
  destructive: "#E47571"
  ai: "#A94AD9"
  pro: "#F07200"
  bg: "#F9F9F9"
  surface-card: "#FFFFFF"
  surface-raised: "#FFFFFF"
  surface-sunken: "#F5F5F5"
  text-emphasize: "#121212"
  text-strong: "#262626"
  text-body: "#2E2E2E"
  text-secondary: "#787078"
  text-subtle: "#949494"
  line: "rgba(0,0,0,.08)"
  on-primary: "#FFFFFF"
  dark-primary: "#397354"
  dark-primary-container: "rgba(57,115,84,.32)"
  dark-primary-deep: "#D4D4D4"
  dark-link: "#4071E2"
  dark-destructive: "#BD5551"
  dark-bg: "#121212"
  dark-surface-card: "#202020"
  dark-surface-raised: "#202020"
  dark-surface-sunken: "rgba(120,120,120,.18)"
  dark-text-emphasize: "#FFFFFF"
  dark-text-strong: "#E2E2E2"
  dark-text-body: "#D4D4D4"
  dark-text-secondary: "#949494"
  dark-text-subtle: "#949494"
  dark-line: "rgba(120,120,120,.18)"
  dark-text: "#D4D4D4"
typography:
  caption:
    fontFamily: PingFang SC
    fontSize: 12px
    fontWeight: 400
    lineHeight: 16px
    letterSpacing: 0em
  body:
    fontFamily: PingFang SC
    fontSize: 15px
    fontWeight: 400
    lineHeight: 24px
    letterSpacing: 0em
  body-lg:
    fontFamily: PingFang SC
    fontSize: 15px
    fontWeight: 400
    lineHeight: 22px
    letterSpacing: 0em
  title:
    fontFamily: PingFang SC
    fontSize: 16px
    fontWeight: 600
    lineHeight: 24px
    letterSpacing: 0em
  page:
    fontFamily: PingFang SC
    fontSize: 16px
    fontWeight: 600
    lineHeight: 16px
    letterSpacing: 0em
  display:
    fontFamily: Baloo 2
    fontSize: 28px
    fontWeight: 600
    lineHeight: 34px
    letterSpacing: 0em
  mono:
    fontFamily: SF Mono
    fontSize: 13px
    fontWeight: 400
    lineHeight: 18px
    letterSpacing: 0em
rounded:
  sm: 3px
  md: 6px
  lg: 12px
  full: 9999px
spacing:
  1: 4px
  2: 8px
  3: 12px
  4: 16px
  6: 24px
  8: 32px
  card-padding: 16px
  section-gutter: 24px
  memo-gap: 12px
  sidebar-width: 280px
  sidebar-row-height: 40px
  sidebar-row-radius: 26px
  content-max: 720px
  navbar-height: 52px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 12px
    height: 36px
  button-tonal:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.primary-deep}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: 12px
  memo-card:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-body}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 16px
  tag-inline:
    backgroundColor: transparent
    textColor: "{colors.primary}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: 0px
  float-button:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.lg}"
    size: 52px
  input:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-body}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 12px
  app-canvas:
    backgroundColor: "{colors.bg}"
    textColor: "{colors.text-body}"
    typography: "{typography.body}"
  destructive-action:
    backgroundColor: "{colors.destructive}"
    textColor: "{colors.text-emphasize}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: 12px
  sunken-well:
    backgroundColor: "{colors.surface-sunken}"
    textColor: "{colors.text-body}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: 12px
  popover:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-body}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: 16px
  divider:
    backgroundColor: "{colors.line}"
    width: 100px
    height: 1px
  dark-canvas:
    backgroundColor: "{colors.dark-bg}"
    textColor: "{colors.dark-text}"
    typography: "{typography.body}"
  dark-card:
    backgroundColor: "{colors.dark-surface-card}"
    textColor: "{colors.dark-text}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 16px
---

# Design System: flomo (浮墨笔记)

## Overview

flomo (浮墨笔记) 是一个以捕捉为先的卡片笔记工具：用户快速记下一闪而过的想法，用 `#tags` 将其连接起来，并通过每日回顾与 AI 洞察让过往笔记重新浮现。

产品哲学是「记录想法，而非管理任务」。界面应显得谦逊、密集、几乎没有装饰镀层：清爽的白色无阴影索引卡片、一个明亮的叶绿色强调色，以及温暖的近中性灰阶。

移动端是主要界面，包含 memo 信息流、底部编辑器、统计/热力图、标签下钻和 AI 洞察。桌面/Web 使用双栏布局：280px 左侧栏 + 居中的 720px 信息流，并始终展示内联编辑器。

设计原则：

- **捕捉优先于管理。** 编辑器始终触手可及；不要在想法和信息流之间放置模态框、向导或其他阻碍。
- **一个强调色，克制使用。** 叶绿色只标记动作与身份：主按钮、发送、`#tags`、浮动按钮、热力图。
- **索引卡片，而不是胶囊。** 12px 圆角、细线边框、无阴影，形成清爽纸感。
- **默认安静。** 低对比度中性色、紧凑排版、无渐变、无发光效果；绿色浮动按钮只使用轻投影。
- **重反思，轻通知。** 动效和颜色鼓励慢慢重读，而不是制造紧迫感；不要使用弹跳、循环动画或抢眼红点。

声音与文案也属于视觉系统的一部分。flomo 的语气是安静、温暖、第二人称中文，像一位体贴的朋友一样称呼用户为“你”，团队称为“我们”。品牌名 `flomo` 小写；缩略词大写（`PRO`、`AI`、`API`）；统计标签大写（`MEMO / DAY / TAG`）。

## Colors

调色板建立在微弱米白画布与温暖近中性灰阶之上，只使用一个标志性叶绿色作为主强调色。正文文字绝不要使用纯 `#000`，墨色应是柔和黑。

### Brand & Semantic Roles

| Token                        | Light     | Dark                 | Role                                                  |
| ---------------------------- | --------- | -------------------- | ----------------------------------------------------- |
| `{colors.primary}`           | `#30CF79` | `#397354`            | 品牌叶绿色；主按钮、发送、`#tags`、浮动按钮、热力图。 |
| `{colors.primary-container}` | `#E6F9EF` | `rgba(57,115,84,.32)` | 带强调色的浅色表面，用于选中状态。                    |
| `{colors.primary-deep}`      | `#397354` | `#D4D4D4`            | 浅色背景上的强调文字。                                |
| `{colors.link}`              | `#6890F8` | `#4071E2`            | 超链接。                                              |
| `{colors.destructive}`       | `#E47571` | `#BD5551`            | 删除与危险操作。                                      |
| `{colors.ai}`                | `#A94AD9` | `#A94AD9`            | AI 洞察强调色。                                       |
| `{colors.pro}`               | `#F07200` | `#F07200`            | PRO / 会员琥珀色。                                    |

次级强调色必须锁定角色。蓝色只用于链接，红色只用于危险操作，紫色只用于 AI，琥珀色只用于 PRO。不要为了增加视觉趣味而调用这些颜色。

### Surface & Text

| Token                     | Light             | Dark                  | Role                   |
| ------------------------- | ----------------- | --------------------- | ---------------------- |
| `{colors.bg}`             | `#F9F9F9`         | `#121212`             | 应用画布。             |
| `{colors.surface-card}`   | `#FFFFFF`         | `#202020`             | memo 卡片。            |
| `{colors.surface-raised}` | `#FFFFFF`         | `#202020`             | 浮层、底部弹层、菜单。 |
| `{colors.surface-sunken}` | `#F5F5F5`         | `rgba(120,120,120,.18)` | 内嵌区域与代码。       |
| `{colors.text-emphasize}` | `#121212`         | `#FFFFFF`             | 标题与强调内容。       |
| `{colors.text-strong}`    | `#262626`         | `#E2E2E2`             | 标题文字。             |
| `{colors.text-body}`      | `#2E2E2E`         | `#D4D4D4`             | 默认正文。             |
| `{colors.text-secondary}` | `#787078`         | `#949494`             | 元信息与说明文字。     |
| `{colors.text-subtle}`    | `#949494`         | `#949494`             | 时间戳与提示。         |
| `{colors.line}`           | `rgba(0,0,0,.08)` | `rgba(120,120,120,.18)` | 极细边框。             |
| `{colors.sidebar-section-title}` | `#C18B49` | `#89602F`             | 侧栏分区小标题。       |
| `{colors.sidebar-metric}` | `#9D9D9D`         | `#949494`             | 侧栏统计数字。         |
| `{colors.contribution-0}` | `#E8E8E8`         | `#343434`             | 热力图空格。           |
| `{colors.contribution-1}` | `#CFE8D9`         | `#254D39`             | 热力图低频。           |
| `{colors.contribution-2}` | `#8AD9B1`         | `#397354`             | 热力图中频。           |
| `{colors.contribution-3}` | `#53B88B`         | `#4EA778`             | 热力图高频。           |

深色模式 token 来自 Figma Dark 组（`Pages - Narrow / Dark`）的实际渲染值。实现时始终使用语义 token，让主题自动切换，不要在视图里手写 `.white`、`.black` 或固定 hex。

## Typography

中文界面采用紧凑、密集的字号阶梯。只使用两种字重：Regular 400 与 SemiBold 600；不要使用 Light、Medium-display 或 Bold。

| Token                  | Size / Line Height | Weight | Use                            |
| ---------------------- | ------------------ | ------ | ------------------------------ |
| `{typography.caption}` | 12px / 16px        | 400    | 时间戳、元信息、列标题。       |
| `{typography.body}`    | 15px / 24px        | 400    | 默认 memo 内容。               |
| `{typography.body-lg}` | 15px / 22px        | 400    | 舒适阅读与设置行。             |
| `{typography.title}`   | 16px / 24px        | 600    | 分区 / 分组标题。              |
| `{typography.page}`    | 16px / 16px        | 600    | 屏幕 / 导航栏标题。            |
| `{typography.display}` | 28px / 34px        | 600    | 引导页标题、大数字、字标兜底。 |
| `{typography.mono}`    | 13px / 18px        | 400    | API 片段与等宽数据。           |

行高应保持紧凑。不要放大字号，flomo 有意采用小字号。UI 文案使用简短名词短语，例如「全部笔记」「无标签笔记」「每日回顾」「会员权益」。

## Layout

布局应服务于快速捕捉与回看，节奏像纸张一样轻：`4 · 8 · 12 · 16 · 24 · 32`。这些值映射到 `{spacing.1}` 至 `{spacing.8}`。

核心布局 token：

- `{spacing.sidebar-width}`: 280px，用于桌面左侧栏。
- `{spacing.sidebar-row-height}`: 40px，用于侧栏列表项高度。
- `{spacing.sidebar-row-radius}`: 26px，用于侧栏列表项胶囊圆角。
- `{spacing.content-max}`: 720px，用于桌面/Web 居中信息流。
- `{spacing.navbar-height}`: 52px，用于导航栏高度。
- `{spacing.card-padding}`: 16px，用于卡片内边距。
- `{spacing.section-gutter}`: 24px，用于分区边距。
- `{spacing.memo-gap}`: 12px，用于 memo 内容间距。

移动端应优先保留底部编辑器与单列信息流。桌面/Web 使用 280px 左侧栏加 720px 中央 feed，内联编辑器始终可见。页面不需要营销式大留白；信息应紧凑但可扫读。

图像与媒体只在 memo 内容需要时出现，使用 `{rounded.lg}` 12px。不要引入营销插图、装饰渐变或与内容无关的背景图。

## Elevation & Depth

flomo 的深度很浅，主要通过极细边框、轻微阴影和表面层级表达，而不是厚重投影。

| Level       | Treatment                                                  | Use                            |
| ----------- | ---------------------------------------------------------- | ------------------------------ |
| L0 Flat     | 无边框、无阴影。                                           | 应用画布、大面积空白。         |
| L1 Hairline | 0.5px `{colors.line}`。                                    | 卡片、输入框、分隔线。         |
| L2 Card     | 仅使用 0.5px `{colors.line}`，无阴影。                      | 默认首页 memo 卡片。           |
| L3 Popover  | `0 6px 24px rgba(0,0,0,.12), 0 0 0 .5px rgba(0,0,0,.06)`。 | 浮层、菜单、底部弹层、对话框。 |
| L4 Float    | `0 0 5px rgba(0,0,0,.15)`。                                | 绿色浮动按钮的轻投影。         |

交互状态：

- 悬停：普通控件使用淡灰色覆盖 `rgba(0,0,0,.05)`；填充控件亮度降低约 6%。
- 按下：按钮缩放到 `0.97`，浮动按钮缩放到 `0.92`。
- 选中：使用 `{colors.primary-container}` 表面与 `{colors.primary-deep}` 文字。
- 动效：标准 `cubic-bezier(.4,0,.2,1)`，时长 120-200ms。分段控件滑块是系统中最显眼的动效。
- 禁止：弹跳、无限循环和装饰性动画。

## Shapes

形状语言是纸感、克制。卡片、主按钮和输入框默认使用 `{rounded.lg}` 12px；小型 chip 使用 `{rounded.sm}`，图标按钮、图片和内嵌控件使用 `{rounded.md}`。

| Token            | Value  | Use                            |
| ---------------- | ------ | ------------------------------ |
| `{rounded.sm}`   | 3px    | 小型 chip。                    |
| `{rounded.md}`   | 6px    | 图标按钮、图片、内嵌控件。     |
| `{rounded.lg}`   | 12px   | 卡片、主按钮、输入框、分组列表。 |
| `{rounded.full}` | 9999px | 仅限圆形头像和胶囊 chip。      |

不要把普通按钮、卡片、输入框圆成胶囊。`{rounded.full}` 是少数高语义对象的例外，不是默认形状。

图标使用 SF Symbols 风格的线性/填充字形：纤细、圆润、单一字重。真实产品中使用 Apple SF Symbols；本系统提供 flomo 绘制的矢量模块：

- `assets/icons/icon-data.js`: 38 个字形，格式为 `{ viewBox, body }`。
- `assets/icons/Icon.jsx`: `<Icon name="…" size={…} />`，使用 `currentColor` 绘制。
- `assets/icons/Icon.d.ts`: 有效名称索引，命名图标前必须阅读。

不要手绘 SVG 图标，也不要把 emoji 用作功能性图标。Emoji 只出现在 About/设置列表行中（每行一个前导 emoji）以及 🍀 品牌标记中。Logo 以矢量形式提供：`assets/logo-text.svg`。

## Components

组件加载在全局命名空间 `window.DesignSystem_e2e2a1` 上（bundle: `_ds_bundle.js`）。构建界面时应组合使用这些组件，不要重新实现基础组件。

| Group      | Components                                           |
| ---------- | ---------------------------------------------------- |
| core       | `Button` · `IconButton` · `Tag` · `Badge` · `Avatar` |
| forms      | `Input` · `Textarea` · `Checkbox` · `Segment`        |
| memo       | `MemoCard` · `Heatmap` · `StatRow`                   |
| navigation | `NavBar` · `FloatButton`                             |
| feedback   | `Snackbar` · `Dialog`                                |
| icons      | `Icon`（38 个字形）                                  |

### Buttons

`{components.button-primary}` 是唯一主动作样式：叶绿色背景、白色文字、12px 圆角。用于发送、主 CTA 和关键确认动作。

`{components.button-tonal}` 用于选中或弱强调状态：浅绿色背景、深绿色文字。普通工具按钮应保持中性色。

### Memo & Tags

`{components.memo-card}` 是默认首页内容容器：白色表面、柔和黑正文、16px 内边距、12px 圆角、0.5px 边框，无阴影。卡片操作（分享、更多）应默认隐藏，悬停时渐进披露。

`{components.tag-inline}` 用于 memo 正文中的 `#tags`，继承正文节奏并使用叶绿色文字。侧栏 chip 可以使用 `{rounded.full}`，但正文标签不应显得像大型胶囊按钮。

### Navigation & Feedback

`FloatButton` 使用 52px 正方形、12px 圆角和轻黑色投影。`NavBar` 高度为 52px。`Snackbar`、`Dialog`、菜单和底部弹层使用 `{rounded.lg}` 或系统 sheet 圆角与 L3 浮层阴影。

`Sidebar` 使用 280px 白色/深色浮层，右侧遮罩 `rgba(0,0,0,.6)`。内容横向内边距 12px，列表项宽 256px、高 40px、圆角 26px、左右 12px 内边距、图标 16px、标题 15/16。选中态使用 `{colors.primary}` 胶囊背景和白色文字；普通态保持透明背景与 `{colors.text-emphasize}`。

## Do's and Don'ts

- 叶绿色仅用于动作和标识。
- 除非具有明确的语义角色，否则其他所有颜色都应保持中性。
- 半径应保持较小；表面应像索引卡片一样清晰易读。
- 首页 memo 卡片使用 0.5px 的极细边框，不使用阴影；浮层和设置分组可使用低调阴影。
- 在备忘录正文中，使用 `<Tag>` 内联渲染 `#tags`。
- 使用简短、亲切的第二人称中文文案。
- 使用 `currentColor` 为图标重新着色，并从 `Icon.d.ts` 文件中获取图标名称。
- 不要使用蓝紫色渐变、装饰性发光或浓重的阴影。
- 不要使用纯黑色 `#000` 作为正文颜色。
- 不要增大字体大小或将普通控件转换为药丸状控件。
- 不要手绘 SVG 图标或将表情符号用作功能性图标。
- 不要将蓝色、红色、紫色或琥珀色用于其明确语义角色之外的用途。
- 不要在捕获流程前面添加模态框或向导。
