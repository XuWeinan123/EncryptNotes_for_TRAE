---
version: alpha
name: Seal Note
description: A quiet, privacy-first note utility with a warm pink accent, native Apple materials, and compact editorial surfaces.
colors:
  primary: "#FF94C5"
  primary-container: "#FFE8F3"
  primary-deep: "#8F2D5A"
  on-primary: "#351625"
  link: "#6890F8"
  destructive: "#E47571"
  background: "#F9F9F9"
  surface: "#FFFFFF"
  surface-raised: "#FFFFFF"
  surface-sunken: "#F5F5F5"
  on-surface-emphasize: "#121212"
  on-surface-strong: "#262626"
  on-surface: "#2E2E2E"
  on-surface-secondary: "#787078"
  on-surface-subtle: "#949494"
  outline-subtle: "rgba(0,0,0,.08)"
typography:
  caption:
    fontFamily: system-ui, PingFang SC, sans-serif
    fontSize: 12px
    fontWeight: 400
    lineHeight: 16px
    letterSpacing: 0em
  body:
    fontFamily: system-ui, PingFang SC, sans-serif
    fontSize: 15px
    fontWeight: 400
    lineHeight: 24px
    letterSpacing: 0em
  body-comfortable:
    fontFamily: system-ui, PingFang SC, sans-serif
    fontSize: 15px
    fontWeight: 400
    lineHeight: 22px
    letterSpacing: 0em
  title:
    fontFamily: system-ui, PingFang SC, sans-serif
    fontSize: 16px
    fontWeight: 600
    lineHeight: 24px
    letterSpacing: 0em
  page-title:
    fontFamily: system-ui, PingFang SC, sans-serif
    fontSize: 16px
    fontWeight: 600
    lineHeight: 16px
    letterSpacing: 0em
  display:
    fontFamily: system-ui, PingFang SC, sans-serif
    fontSize: 28px
    fontWeight: 600
    lineHeight: 34px
    letterSpacing: 0em
  mono:
    fontFamily: SF Mono, ui-monospace, monospace
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
  note-gap: 12px
  sidebar-width: 280px
  sidebar-row-height: 40px
  content-max: 720px
  toolbar-icon-width: 18px
---

# Seal Note Design System

<!--
  Ownership mode: code-backed.
  SwiftUI and AppKit source code own exact component construction, native
  materials, interaction states, accessibility, and alternate color themes.
  This document owns the default pink theme's stable visual semantics and
  component-selection intent.
-->

## Overview

Seal Note 是一款安静、轻巧且重视隐私的快速记录工具。界面要让用户感到内容始终属于自己：记录路径短，信息层级清楚，加密能力可信但不制造压迫感。

默认视觉以柔和粉色为唯一品牌强调，搭配系统中性色、原生玻璃材质与紧凑排版。整体气质应温暖而克制，既不像企业后台，也不做甜腻或装饰性的少女风表达。

设计遵循以下原则：

- **内容先于装饰。** 笔记正文是最高优先级，容器只提供必要的边界与层级。
- **粉色表达品牌与交互。** 粉色用于关键操作、焦点、选中状态和少量身份提示，不作为大面积背景填充。
- **优先使用 Apple 原生控件。** 系统按钮、菜单、工具栏、输入控件与弹层保留平台熟悉的材质、反馈和无障碍行为。
- **安全感来自清晰。** 加密、密钥、存储和危险操作使用直接、准确的文字与稳定的语义色，不用夸张警示制造焦虑。
- **桌面工作流保持轻盈。** 菜单栏入口、悬浮笔记窗口和快捷键应让记录融入当前工作，而不是要求用户切换到复杂的管理界面。

## Colors

文档只定义默认粉色主题。其他可选主题及深色外观的精确映射由 `DesignSystem.swift` 负责，不在此扩展第二套调色板。

### Pink Accent

| Token | Value | Role |
| --- | --- | --- |
| `{colors.primary}` | `#FF94C5` | 主要交互强调、系统控件 tint、焦点与少量品牌识别。 |
| `{colors.primary-container}` | `#FFE8F3` | 选中、悬停和提示区域的柔和强调表面。 |
| `{colors.primary-deep}` | `#8F2D5A` | 浅粉表面上的图标、文字和 Markdown 强调。 |
| `{colors.on-primary}` | `#351625` | 实色粉色表面上的前景色。 |

`{colors.primary}` 应保持稀疏；同一视图中优先突出一个动作或一组紧密关联的状态。大面积区域使用中性表面，让粉色保持辨识度。

### Surfaces and Text

| Token | Value | Role |
| --- | --- | --- |
| `{colors.background}` | `#F9F9F9` | 应用画布与列表底层。 |
| `{colors.surface}` | `#FFFFFF` | 笔记、设置分组与输入区域。 |
| `{colors.surface-raised}` | `#FFFFFF` | 浮层、菜单和需要暂时聚焦的内容。 |
| `{colors.surface-sunken}` | `#F5F5F5` | 代码、预览和内嵌信息区域。 |
| `{colors.on-surface-emphasize}` | `#121212` | 页面级标题与最高层级信息。 |
| `{colors.on-surface-strong}` | `#262626` | 分区标题和强调正文。 |
| `{colors.on-surface}` | `#2E2E2E` | 默认正文。 |
| `{colors.on-surface-secondary}` | `#787078` | 说明、辅助标签与非关键状态。 |
| `{colors.on-surface-subtle}` | `#949494` | 时间、占位符和可省略的元信息。 |
| `{colors.outline-subtle}` | `rgba(0,0,0,.08)` | 0.5px 细边界与弱分隔。 |

正文不使用纯黑；通过多级中性文字建立信息层级。`{colors.on-surface-subtle}` 只承载非关键元信息，必要说明使用 `{colors.on-surface-secondary}` 或更高层级。

### Semantic Color

- `{colors.link}` 只用于可打开的链接和 URL。
- `{colors.destructive}` 只用于删除、清空、替换密钥等不可逆或高风险操作。
- 状态图标应优先使用系统语义色；只有当状态同时承担品牌交互含义时才使用粉色。

## Typography

使用 Apple 系统字体。中文由系统匹配 PingFang SC，拉丁文本使用 SF 系列；代码与结构化片段使用 SF Mono。常规界面只使用 Regular 400 与 Semibold 600，保持阅读自然并避免不必要的字重噪声。

| Token | Size / Line Height | Weight | Use |
| --- | --- | --- | --- |
| `{typography.caption}` | 12px / 16px | 400 | 时间、元信息和紧凑标签。 |
| `{typography.body}` | 15px / 24px | 400 | 默认笔记与界面正文。 |
| `{typography.body-comfortable}` | 15px / 22px | 400 | 设置说明与舒适阅读区域。 |
| `{typography.title}` | 16px / 24px | 600 | 分区和分组标题。 |
| `{typography.page-title}` | 16px / 16px | 600 | 窗口与工具栏标题。 |
| `{typography.display}` | 28px / 34px | 600 | About 产品名、空状态主标题与大数字。 |
| `{typography.mono}` | 13px / 18px | 400 | 密钥指纹、路径、Markdown 与技术数据。 |

笔记编辑器字号可由用户设置；它属于阅读偏好，不改变界面字体层级。标题层级通过字号、字重和间距共同建立，不用彩色标题代替结构。

引导页的 40px 产品标题是为首次启动场景保留的特殊层级，不作为可复用 Token。

## Layout

基础间距节奏为 `4 · 8 · 12 · 16 · 24 · 32`，对应 `{spacing.1}` 至 `{spacing.8}`。相邻控件使用 8–12px，容器内边距使用 16px，主要分区使用 24–32px。

- `{spacing.card-padding}` 16px：内容卡片和紧凑分组的标准内边距。
- `{spacing.section-gutter}` 24px：窗口主要分区与面板边距。
- `{spacing.note-gap}` 12px：笔记内部元素和列表内容间距。
- `{spacing.sidebar-width}` 280px：需要侧栏时的基准宽度。
- `{spacing.sidebar-row-height}` 40px：侧栏可点击行的基准高度。
- `{spacing.content-max}` 720px：长文本和集中阅读区域的建议最大宽度。
- `{spacing.toolbar-icon-width}` 18px：macOS 工具栏图标的稳定占位宽度。

悬浮笔记窗口应让正文自然占据可用空间，工具栏不挤压编辑区。设置与列表窗口可以扩展宽度，但文本行长仍应保持可读。不要为了视觉饱满而填入与当前任务无关的面板。

## Elevation & Depth

层级主要依靠原生材质、表面明度与细边界建立。投影只用于需要从其他窗口或内容上方脱离的层。

| Level | Treatment | Use |
| --- | --- | --- |
| Flat | `{colors.background}` 或透明系统背景，无阴影。 | 应用画布与连续内容。 |
| Bordered | `{colors.surface}` + 0.5px `{colors.outline-subtle}`。 | 笔记容器、输入区与设置面板。 |
| Card | 黑色 3% 不透明度、半径 6px、Y 轴 1px。 | 确实需要与画布区分的轻量卡片。 |
| Popover | 黑色 12% 不透明度、半径 24px、Y 轴 6px。 | 悬浮笔记窗口与聚焦浮层。 |
| Float | 黑色 15% 不透明度、半径 5px。 | 应用图标等少量悬浮对象。 |

macOS 26 工具栏使用系统 Liquid Glass 与滚动边缘效果。保持工具栏透明，按钮使用系统默认 glass 表现；不要叠加自定义背景、描边、渐变或粉色光晕。

## Shapes

连续圆角用于柔化紧凑界面，但每个半径对应明确层级：

| Token | Value | Use |
| --- | --- | --- |
| `{rounded.sm}` | 3px | 小型标记和非常紧凑的内嵌对象。 |
| `{rounded.md}` | 6px | 图标容器、输入控件和悬浮笔记窗口。 |
| `{rounded.lg}` | 12px | 卡片、面板和较大的内容分组。 |
| `{rounded.full}` | 9999px | 圆形状态、短胶囊标签和明确采用 Capsule 的单一动作。 |

图标统一使用 SF Symbols，并匹配系统控件的字号和字重。功能图标不使用 emoji，也不为常见系统动作重新绘制私有图标。

## Components

组件的精确尺寸、材质、状态和行为由 SwiftUI 与 AppKit 实现负责。新增界面应先组合系统组件和仓库中已有的共享组件，再考虑创建新的视觉构件。

- **Buttons:** 工具栏按钮保留系统自动样式；主要确认动作使用系统 prominent 或 glass prominent 变体并以 `{colors.primary}` 着色。危险按钮使用系统 destructive role。
- **Toolbars:** 保持透明，让系统管理 glass 分组、悬停、按下和窗口激活状态。图标使用 `{spacing.toolbar-icon-width}` 稳定布局。
- **Note surfaces:** 笔记容器使用现有的系统背景、`{rounded.md}` 连续圆角与细边界；除非窗口层级需要，不额外增加阴影。
- **Inputs:** 短文本使用原生 TextField，长文本和 Markdown 编辑使用现有编辑器；输入焦点跟随系统行为与粉色 tint。
- **Selection:** 柔和选中态使用 `{colors.primary-container}`，前景使用 `{colors.primary-deep}`；强选中态才使用 `{colors.primary}`。
- **Panels and lists:** 设置面板使用清晰分组与行分隔；列表在悬停时只做轻微表面变化，不把每一行都变成独立卡片。
- **Feedback:** Alert、Sheet、Confirmation Dialog、Menu 与 Progress View 优先使用原生组件；安全状态文案保持具体，错误与危险操作保持明确。

## Do's and Don'ts

- Do use `{colors.primary}` as the single brand accent so important actions remain easy to find.
- Do pair `{colors.primary-container}` with `{colors.primary-deep}` for quiet selection and hover feedback.
- Do preserve the existing transparent toolbar and native glass button treatment.
- Do use system controls and SF Symbols so macOS interaction, accessibility, and materials stay coherent.
- Do keep note surfaces restrained: neutral background, continuous radius, 0.5px boundary, and only necessary elevation.
- Do use `{colors.destructive}` and system destructive roles only for genuinely risky actions.
- Don't introduce green, cyan, or another competing theme palette into the default pink visual contract.
- Don't apply pink to large backgrounds, long text, or every icon; that turns the accent into visual noise.
- Don't add gradients, colored glows, thick borders, or decorative shadows around native glass controls.
- Don't replace the current note container, toolbar, or button materials with custom styling without a specific functional need.
- Don't use `{colors.on-surface-subtle}` for required instructions or essential status because its contrast is intentionally secondary.
- Don't create one-off colors, radii, or spacing values when an existing semantic token expresses the same role.
