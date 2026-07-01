import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// flomo 设计系统 token
///
/// 详见根目录 DESIGN.md。所有界面颜色、字号、间距、圆角均通过此处的常量引用，
/// 以保证主题一致并支持后续深色模式切换。
enum DS {
    // MARK: - Colors

    /// 品牌叶绿色；主按钮、发送、`#tags`、浮动按钮、热力图。
    static var primary: Color {
        switch currentMacTheme {
        case .green: return Color(light: 0x30CF79, dark: 0x397354)
        case .pink: return Color(light: 0xFF94C5, dark: 0xFF94C5)
        case .cyan: return Color(light: 0x14C8D8, dark: 0x33D2E3)
        }
    }
    /// 带强调色的浅色表面，用于选中状态。
    static var primaryContainer: Color {
        switch currentMacTheme {
        case .green: return Color(light: 0xE6F9EF, dark: 0x397354, darkAlpha: 0.32)
        case .pink: return Color(light: 0xFFE8F3, dark: 0xFF94C5, darkAlpha: 0.24)
        case .cyan: return Color(light: 0xE3FAFC, dark: 0x33D2E3, darkAlpha: 0.24)
        }
    }
    /// 浅色背景上的强调文字。
    static var primaryDeep: Color {
        switch currentMacTheme {
        case .green: return Color(light: 0x397354, dark: 0xD4D4D4)
        case .pink: return Color(light: 0x8F2D5A, dark: 0xFFD8E8)
        case .cyan: return Color(light: 0x246A73, dark: 0xCFF7FB)
        }
    }
    /// 超链接。
    static let link = Color(light: 0x6890F8, dark: 0x4071E2)
    /// 删除与危险操作。
    static let destructive = Color(light: 0xE47571, dark: 0xBD5551)
    /// AI 洞察强调色。
    static let ai = Color(hex: 0xA94AD9)
    /// PRO / 会员琥珀色。
    static let pro = Color(hex: 0xF07200)

    /// 应用画布。
    static let bg = Color(light: 0xF9F9F9, dark: 0x121212)
    /// memo 卡片。
    static let surfaceCard = Color(light: 0xFFFFFF, dark: 0x202020)
    /// 浮层、底部弹层、菜单。
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x202020)
    /// 内嵌区域与代码。
    static let surfaceSunken = Color(light: 0xF5F5F5, dark: 0x787878, darkAlpha: 0.18)

    /// 标题与强调内容。
    static let textEmphasize = Color(light: 0x121212, dark: 0xFFFFFF)
    /// 标题文字。
    static let textStrong = Color(light: 0x262626, dark: 0xE2E2E2)
    /// 默认正文。
    static let textBody = Color(light: 0x2E2E2E, dark: 0xD4D4D4)
    /// 元信息与说明文字。
    static let textSecondary = Color(light: 0x787078, dark: 0x949494)
    /// 时间戳与提示。
    static let textSubtle = Color(light: 0x949494, dark: 0x949494)
    /// 极细边框。
    static let line = Color(light: 0x000000, dark: 0x787878, lightAlpha: 0.08, darkAlpha: 0.18)
    /// 主按钮文字。
    static var onPrimary: Color {
        switch currentMacTheme {
        case .green: return Color.white
        case .pink: return Color(hex: 0x351625)
        case .cyan: return Color(hex: 0x10363C)
        }
    }
    /// 浮动按钮图标。
    static let onFloat = Color.white
    /// 侧栏分区小标题。
    static let sidebarSectionTitle = Color(light: 0xC18B49, dark: 0x89602F)
    /// 侧栏统计数字与热力图空格。
    static let sidebarMetric = Color(light: 0x9D9D9D, dark: 0x949494)
    /// 热力图空格。
    static let contribution0 = Color(light: 0xE8E8E8, dark: 0x343434)
    /// 热力图低频。
    static let contribution1 = Color(light: 0xCFE8D9, dark: 0x254D39)
    /// 热力图中频。
    static let contribution2 = Color(light: 0x8AD9B1, dark: 0x397354)
    /// 热力图高频。
    static let contribution3 = Color(light: 0x53B88B, dark: 0x4EA778)

    /// 深色模式画布。
    static let darkBg = Color(hex: 0x121212)
    /// 深色模式卡片。
    static let darkSurfaceCard = Color(hex: 0x202020)
    /// 深色模式正文。
    static let darkText = Color(hex: 0xD4D4D4)

    // MARK: - Rounded

    /// 小型 chip。
    static let rSm: CGFloat = 3
    /// 图标按钮、图片、内嵌控件。
    static let rMd: CGFloat = 6
    /// 卡片、浮动按钮、分组列表。
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
    static let sidebarRowHeight: CGFloat = 40
    static let sidebarRowRadius: CGFloat = 26
    static let contentMax: CGFloat = 720
    static let navbarHeight: CGFloat = 52
    /// 固定 toolbar 图标宽度，避免状态切换时按钮组跳动。
    static let macToolbarIconWidth: CGFloat = 18

    private static var currentMacTheme: MacTheme {
        MacTheme(rawValue: UserDefaults.standard.string(forKey: "BKMacTheme") ?? "") ?? .pink
    }

    // MARK: - Elevation

    /// L2 Card: 近乎不可见的纸面阴影。
    static let cardShadow = (color: Color.black.opacity(0.03),
                             radius: CGFloat(6), x: CGFloat(0), y: CGFloat(1))
    /// L3 Popover: `0 6px 24px rgba(0,0,0,.12), 0 0 0 .5px rgba(0,0,0,.06)`。
    static let popoverShadow = (color: Color.black.opacity(0.12),
                                radius: CGFloat(24), x: CGFloat(0), y: CGFloat(6))
    /// L4 Float: Figma 浮动按钮阴影，不使用额外绿色光晕。
    static let floatShadow = (color: Color.black.opacity(0.15),
                              radius: CGFloat(5), x: CGFloat(0), y: CGFloat(0))

    // MARK: - Typography

    /// 时间戳、元信息、列标题。12/16/400。
    static func caption() -> Font { .system(size: 12, weight: .regular) }

    /// 默认 memo 内容。15/24/400。
    static func body() -> Font { .system(size: 15, weight: .regular) }

    /// 舒适阅读与设置行。15/22/400。
    static func bodyLg() -> Font { .system(size: 15, weight: .regular) }

    /// 分区 / 分组标题。16/24/600。
    static func title() -> Font { .system(size: 16, weight: .semibold) }

    /// 屏幕 / 导航栏标题。16/16/600。
    static func page() -> Font { .system(size: 16, weight: .semibold) }

    /// 引导页标题、大数字、字标兜底。28/34/600。
    static func display() -> Font { .system(size: 28, weight: .semibold) }

    /// API 片段与等宽数据。13/18/400。
    static func mono() -> Font { .system(size: 13, weight: .regular, design: .monospaced) }
}

extension View {
    /// 索引卡片：12px 圆角、0.5px 细线；阴影仅用于需要抬升的表面。
    func dsCardSurface(cornerRadius: CGFloat = DS.rLg, shadow: Bool = true) -> some View {
        background(DS.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.line, lineWidth: 0.5)
            )
            .shadow(color: shadow ? DS.cardShadow.color : .clear,
                    radius: shadow ? DS.cardShadow.radius : 0,
                    x: shadow ? DS.cardShadow.x : 0,
                    y: shadow ? DS.cardShadow.y : 0)
    }

    /// L1 输入表面：白色卡片背景与 0.5px 细线，保持捕捉区安静。
    func dsInputSurface(cornerRadius: CGFloat = DS.rLg) -> some View {
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

    /// 通过 light/dark 0xRRGGBB 创建随系统外观切换的 Color。
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1.0, darkAlpha: Double = 1.0) {
        #if canImport(UIKit)
        self.init(UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            let alpha = traits.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
            return UIColor(hex: value, alpha: alpha)
        })
        #elseif canImport(AppKit)
        self.init(NSColor(name: nil) { appearance in
            let best = appearance.bestMatch(from: [.darkAqua, .aqua])
            let isDark = best == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
        #else
        self.init(hex: light, alpha: lightAlpha)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: CGFloat(alpha))
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: CGFloat(alpha))
    }
}
#endif

extension View {
    /// 应用画布背景。
    ///
    @ViewBuilder
    func dsCanvasBackground() -> some View {
        self.background(DS.bg.ignoresSafeArea())
    }

    /// List 背景处理。
    @ViewBuilder
    func dsListBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
    }

    /// 系统导航栏 / toolbar 背景策略。
    @ViewBuilder
    func dsLiquidGlassToolbar() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self.toolbarBackground(.hidden, for: .navigationBar)
                .overlay(alignment: .top) {
                    DSToolbarMaterialFade()
                        .allowsHitTesting(false)
                }
        }
        #else
        self
        #endif
    }

    /// toolbar item 按钮走系统默认样式，避免覆盖 iOS 26 自动分组的 glass surface。
    @ViewBuilder
    func dsToolbarButtonStyle() -> some View {
        self
    }

    /// macOS 便利贴窗口样式。
    @ViewBuilder
    func dsStickyNoteWindow() -> some View {
        self
            .background(DS.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .stroke(DS.line, lineWidth: 0.5)
            )
            .shadow(color: DS.popoverShadow.color,
                    radius: DS.popoverShadow.radius,
                    x: DS.popoverShadow.x,
                    y: DS.popoverShadow.y)
    }
}

#if os(iOS)
private struct DSToolbarMaterialFade: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: DS.navbarHeight + DS.s8)
            .mask(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black.opacity(0.9), location: 0.58),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .top)
    }
}
#endif

#if os(macOS)
extension View {
    @ViewBuilder
    func dsMacStickyToolbarScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
#endif
