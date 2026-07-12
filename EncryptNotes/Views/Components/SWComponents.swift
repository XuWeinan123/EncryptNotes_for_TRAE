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
    let trailingMinWidth: CGFloat
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = DS.primaryDeep,
        trailingMinWidth: CGFloat = 150,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.trailingMinWidth = trailingMinWidth
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
                .foregroundStyle(.primary)
                .frame(minWidth: trailingMinWidth, alignment: .trailing)
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
        #if os(macOS)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(DS.s6)
        #else
        content
            .frame(maxWidth: .infinity)
            .padding(DS.s6)
            .dsCardSurface(shadow: false)
        #endif
    }

    private var content: some View {
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
    }
}

struct SWFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SWFilterChipLabel(title: title, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct SWFilterChipLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(DS.caption())
            .foregroundColor(isSelected ? DS.primaryDeep : DS.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, DS.s3)
            .padding(.vertical, DS.s2)
            .background(isSelected ? DS.primaryContainer : DS.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .stroke(isSelected ? DS.primary.opacity(0.28) : DS.line, lineWidth: 0.5)
            )
    }
}

#if os(macOS)
struct SWFilterChipMenu: View {
    let title: String
    let items: [String]
    let onSelect: (String) -> Void

    @State private var presenter = SWFilterChipMenuPresenter()

    var body: some View {
        SWFilterChip(title: title, isSelected: false) {
            presenter.present(items: items, onSelect: onSelect)
        }
        .background(SWFilterChipMenuAnchor(presenter: presenter))
    }
}

@MainActor
private final class SWFilterChipMenuPresenter: NSObject {
    weak var anchorView: NSView?
    private var onSelect: ((String) -> Void)?

    func present(items: [String], onSelect: @escaping (String) -> Void) {
        guard let anchorView, !items.isEmpty else { return }
        self.onSelect = onSelect

        let menu = NSMenu()
        menu.autoenablesItems = false
        for title in items {
            let item = NSMenuItem(title: title, action: #selector(selectItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = title
            menu.addItem(item)
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: anchorView.bounds.minY),
            in: anchorView
        )
    }

    @objc private func selectItem(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String else { return }
        onSelect?(title)
    }
}

private struct SWFilterChipMenuAnchor: NSViewRepresentable {
    let presenter: SWFilterChipMenuPresenter

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughMenuAnchorView()
        presenter.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        presenter.anchorView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // The presenter owns no AppKit view; its weak reference clears naturally.
    }
}

private final class PassthroughMenuAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
#endif

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
