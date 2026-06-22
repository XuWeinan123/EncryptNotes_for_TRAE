import SwiftUI

/// flomo 设计系统 token
///
/// 详见根目录 DESIGN.md。所有界面颜色、字号、间距、圆角均通过此处的常量引用，
/// 以保证主题一致并支持后续深色模式切换。
enum DS {
    // MARK: - Colors

    /// 品牌叶绿色；主按钮、发送、`#tags`、浮动按钮、热力图。
    static let primary = Color(hex: 0x30CF79)
    /// 带强调色的浅色表面，用于选中状态。
    static let primaryContainer = Color(hex: 0xE6F9EF)
    /// 浅色背景上的强调文字。
    static let primaryDeep = Color(hex: 0x397354)
    /// 超链接。
    static let link = Color(hex: 0x6890F8)
    /// 删除与危险操作。
    static let destructive = Color(hex: 0xE47571)
    /// AI 洞察强调色。
    static let ai = Color(hex: 0xA94AD9)
    /// PRO / 会员琥珀色。
    static let pro = Color(hex: 0xF07200)

    /// 应用画布。
    static let bg = Color(hex: 0xF9F9F9)
    /// memo 卡片。
    static let surfaceCard = Color.white
    /// 浮层、底部弹层、菜单。
    static let surfaceRaised = Color.white
    /// 内嵌区域与代码。
    static let surfaceSunken = Color(hex: 0xF5F5F5)

    /// 标题与强调内容。
    static let textEmphasize = Color(hex: 0x121212)
    /// 标题文字。
    static let textStrong = Color(hex: 0x262626)
    /// 默认正文。
    static let textBody = Color(hex: 0x2E2E2E)
    /// 元信息与说明文字。
    static let textSecondary = Color(hex: 0x787078)
    /// 时间戳与提示。
    static let textSubtle = Color(hex: 0x949494)
    /// 极细边框。
    static let line = Color.black.opacity(0.08)
    /// 主按钮文字。
    static let onPrimary = Color(hex: 0x121212)

    /// 深色模式画布。
    static let darkBg = Color(hex: 0x121212)
    /// 深色模式卡片。
    static let darkSurfaceCard = Color(hex: 0x202020)
    /// 深色模式正文。
    static let darkText = Color(hex: 0xEDEDED)

    // MARK: - Rounded

    /// 卡片、按钮、输入框。
    static let rSm: CGFloat = 3
    /// 浮层、菜单、底部弹层、对话框。
    static let rMd: CGFloat = 6
    /// 大型底部弹层与图片。
    static let rLg: CGFloat = 12
    /// 浮动按钮、圆形头像、chip。
    static let rFull: CGFloat = 9999

    // MARK: - Spacing

    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32

    static let cardPadding: CGFloat = 16
    static let sectionGutter: CGFloat = 24
    static let memoGap: CGFloat = 12
    static let sidebarWidth: CGFloat = 280
    static let contentMax: CGFloat = 720
    static let navbarHeight: CGFloat = 52

    // MARK: - Elevation

    /// L2 Card: `0 1px 2px rgba(51,44,96,.08)` + L1。
    static let cardShadow = (color: Color(hex: 0x332C60).opacity(0.08),
                             radius: CGFloat(2), x: CGFloat(0), y: CGFloat(1))
    /// L3 Popover: `0 6px 24px rgba(0,0,0,.12), 0 0 0 .5px rgba(0,0,0,.06)`。
    static let popoverShadow = (color: Color.black.opacity(0.12),
                                radius: CGFloat(24), x: CGFloat(0), y: CGFloat(6))
    /// L4 Float: `0 4px 14px rgba(48,207,121,.36)`，唯一允许绿色光晕。
    static let floatShadow = (color: Color(hex: 0x30CF79).opacity(0.36),
                              radius: CGFloat(14), x: CGFloat(0), y: CGFloat(4))

    // MARK: - Typography

    /// 时间戳、元信息、列标题。13/16/400。
    static func caption() -> Font { .system(size: 13, weight: .regular) }

    /// 默认 memo 内容。14/20/400。
    static func body() -> Font { .system(size: 14, weight: .regular) }

    /// 舒适阅读与设置行。15/22/400。
    static func bodyLg() -> Font { .system(size: 15, weight: .regular) }

    /// 分区 / 分组标题。16/24/600。
    static func title() -> Font { .system(size: 16, weight: .semibold) }

    /// 屏幕 / 导航栏标题。20/28/600。
    static func page() -> Font { .system(size: 20, weight: .semibold) }

    /// 引导页标题、大数字、字标兜底。28/34/600。
    static func display() -> Font { .system(size: 28, weight: .semibold) }

    /// API 片段与等宽数据。13/18/400。
    static func mono() -> Font { .system(size: 13, weight: .regular, design: .monospaced) }
}

extension View {
    /// L2 索引卡片：3px 圆角、0.5px 细线和非常轻的纸面阴影。
    func dsCardSurface(cornerRadius: CGFloat = DS.rSm) -> some View {
        background(DS.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.line, lineWidth: 0.5)
            )
            .shadow(color: DS.cardShadow.color,
                    radius: DS.cardShadow.radius,
                    x: DS.cardShadow.x,
                    y: DS.cardShadow.y)
    }

    /// L1 输入表面：白色卡片背景与 0.5px 细线，保持捕捉区安静。
    func dsInputSurface(cornerRadius: CGFloat = DS.rSm) -> some View {
        background(DS.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.line, lineWidth: 0.5)
            )
    }
}

extension Color {
    /// 通过 0xRRGGBB 创建 Color。
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension View {
    /// 应用画布背景。
    ///
    /// iOS 26+ 不使用 `.ignoresSafeArea()`，避免自定义背景延伸到 navigation bar
    /// 下方干扰系统 Liquid Glass 折射效果；toolbar 由系统自动渲染为 liquid glass。
    /// iOS 26 以下保留 `.ignoresSafeArea()` 以铺满屏幕。
    @ViewBuilder
    func dsCanvasBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.background(DS.bg)
        } else {
            self.background(DS.bg.ignoresSafeArea())
        }
    }

    /// List 背景处理。
    ///
    /// iOS 26+ 避免把自定义背景延伸到 navigation bar 下方，保留系统
    /// toolbar 的 Liquid Glass 折射空间；iOS 26 以下隐藏默认背景并铺满 DS.bg。
    @ViewBuilder
    func dsListBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollContentBackground(.hidden)
                .background(DS.bg)
        } else {
            self.scrollContentBackground(.hidden)
                .background(DS.bg.ignoresSafeArea())
        }
    }

    /// 系统导航栏 / toolbar 背景策略。
    ///
    /// iOS 26+ 必须让系统管理 navigation bar 背景，不能强制显示旧式实色 /
    /// material bar，否则系统会退回接近 iOS 18 的 toolbar 观感。这里显式隐藏
    /// SwiftUI toolbar 背景，交给 iOS 26 的 Liquid Glass toolbar 渲染。
    /// iOS 26 以下保留浅色实体栏，延续原有设计。
    @ViewBuilder
    func dsLiquidGlassToolbar() -> some View {
        if #available(iOS 26.0, *) {
            self.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self.toolbarBackground(DS.surfaceCard, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    /// iOS 26+ 为 toolbar 内按钮使用系统 Liquid Glass button style；旧系统保持默认。
    @ViewBuilder
    func dsToolbarButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self
        }
    }
}
