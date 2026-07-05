import SwiftUI

#if os(iOS)
import UIKit
#endif

struct SWShimmer<Content: View>: View {
    @State private var animate = false

    var duration: Double = 1.8
    var delay: Double = 0.4
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .overlay {
                GeometryReader { geo in
                    let bandWidth = geo.size.width * 0.55
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.36), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: animate ? geo.size.width + bandWidth : -bandWidth * 1.5)
                    .animation(
                        .linear(duration: duration)
                        .delay(delay)
                        .repeatForever(autoreverses: false),
                        value: animate
                    )
                }
                .clipped()
            }
            .task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                animate = true
            }
    }
}

enum SWStatusBadgeStyle {
    case success
    case warning
    case error
    case neutral

    var tint: Color {
        switch self {
        case .success: return DS.primaryDeep
        case .warning: return DS.pro
        case .error: return DS.destructive
        case .neutral: return DS.textSecondary
        }
    }

    var fill: Color {
        switch self {
        case .success: return DS.primaryContainer
        case .warning: return DS.pro.opacity(0.12)
        case .error: return DS.destructive.opacity(0.12)
        case .neutral: return DS.surfaceSunken
        }
    }
}

struct SWStatusBadge: View {
    let text: String
    let systemImage: String?
    let style: SWStatusBadgeStyle

    init(_ text: String, systemImage: String? = nil, style: SWStatusBadgeStyle = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        HStack(spacing: DS.s1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(DS.caption())
                .lineLimit(1)
        }
        .foregroundColor(style.tint)
        .padding(.horizontal, DS.s2)
        .padding(.vertical, DS.s1)
        .background(style.fill)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(style.tint.opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct SWSectionPanel<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(
        _ title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            if let title {
                Text(title)
                    .font(DS.title())
                    .foregroundColor(DS.textEmphasize)
                    .padding(.horizontal, DS.s1)
            }

            VStack(spacing: 0) {
                content()
            }
            .dsCardSurface(shadow: false)

            if let footer {
                Text(footer)
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.s1)
            }
        }
    }
}

struct SWPanelStack<Content: View>: View {
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let viewportTopPadding: CGFloat
    let viewportBottomPadding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        topPadding: CGFloat = DS.s4,
        bottomPadding: CGFloat = DS.s8,
        viewportTopPadding: CGFloat = 0,
        viewportBottomPadding: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.viewportTopPadding = viewportTopPadding
        self.viewportBottomPadding = viewportBottomPadding
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewportTopPadding > 0 {
                DS.bg.frame(height: viewportTopPadding)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DS.s4) {
                    content()
                }
                .padding(.top, topPadding)
                .padding(.horizontal, DS.s4)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)

            if viewportBottomPadding > 0 {
                DS.bg.frame(height: viewportBottomPadding)
            }
        }
        .background(DS.bg)
    }
}

struct SWPageHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color = DS.primaryDeep
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: DS.rLg, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.title())
                    .foregroundColor(DS.textEmphasize)
                Text(subtitle)
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                    .lineLimit(2)
            }

            Spacer(minLength: DS.s3)
        }
        .padding(DS.cardPadding)
        .dsCardSurface(shadow: false)
        .padding(.bottom, DS.s4)
    }
}

struct SWSettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = DS.primaryDeep,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DS.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.bodyLg())
                    .foregroundColor(DS.textStrong)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: DS.s3)

            trailing()
                .foregroundColor(DS.textSecondary)
        }
        .padding(.horizontal, DS.s3)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct SWRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.line)
            .frame(height: 0.5)
            .padding(.leading, DS.s3 + 28 + DS.s3)
    }
}

struct SWEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: DS.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundColor(DS.primaryDeep)
                .frame(width: 58, height: 58)
                .background(DS.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: DS.rLg, style: .continuous))

            Text(title)
                .font(DS.title())
                .foregroundColor(DS.textStrong)

            Text(message)
                .font(DS.body())
                .foregroundColor(DS.textSubtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.s6)
        .dsCardSurface(shadow: false)
    }
}

struct SWSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: DS.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.textSubtle)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.body())
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.textSubtle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.s3)
        .padding(.vertical, DS.s2)
        .dsInputSurface(cornerRadius: DS.rMd)
    }
}

struct SWFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.caption())
                .foregroundColor(isSelected ? DS.primaryDeep : DS.textSecondary)
                .padding(.horizontal, DS.s3)
                .padding(.vertical, DS.s2)
                .background(isSelected ? DS.primaryContainer : DS.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                        .stroke(isSelected ? DS.primary.opacity(0.28) : DS.line, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

enum SWNoteListRowStyle {
    case card
    case compact
}

struct SWNoteListRow<Trailing: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let style: SWNoteListRowStyle
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color = DS.textSubtle,
        style: SWNoteListRowStyle = .card,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.style = style
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: rowSpacing) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: iconFrame, height: iconFrame)
                .background(iconBackground)
                .clipShape(RoundedRectangle(cornerRadius: iconRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(titleFont)
                    .foregroundColor(DS.textStrong)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.s3)

            trailing()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
                .stroke(rowStroke, lineWidth: 0.5)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isHovering)
        #if os(macOS)
        .onHover { hovering in
            isHovering = hovering
        }
        #endif
    }

    private var rowSpacing: CGFloat {
        style == .compact ? DS.s2 : DS.s3
    }

    private var iconSize: CGFloat {
        style == .compact ? 12 : 13
    }

    private var iconFrame: CGFloat {
        style == .compact ? 24 : 28
    }

    private var iconRadius: CGFloat {
        style == .compact ? DS.rSm : DS.rMd
    }

    private var iconBackground: Color {
        style == .compact ? DS.surfaceSunken : tint.opacity(0.12)
    }

    private var titleFont: Font {
        style == .compact ? .system(size: 14, weight: .semibold) : DS.body()
    }

    private var horizontalPadding: CGFloat {
        style == .compact ? DS.s3 : DS.s3
    }

    private var verticalPadding: CGFloat {
        style == .compact ? 10 : DS.s2
    }

    private var rowRadius: CGFloat {
        style == .compact ? DS.rMd : DS.rMd
    }

    private var rowBackground: Color {
        switch style {
        case .card:
            return isHovering ? DS.primaryContainer.opacity(0.52) : DS.surfaceCard
        case .compact:
            return isHovering ? DS.primaryContainer.opacity(0.42) : DS.surfaceCard.opacity(0.72)
        }
    }

    private var rowStroke: Color {
        isHovering ? tint.opacity(0.32) : DS.line
    }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
