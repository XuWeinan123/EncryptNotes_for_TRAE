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

struct SWSearchBar: View {
    @Binding var text: String
    var placeholder: String = "搜索"

    var body: some View {
        HStack(spacing: DS.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.textSubtle)

            TextField(placeholder, text: $text)
                .font(DS.body())
                .foregroundColor(DS.textBody)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()

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

struct SWTabButton: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.s1) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(DS.caption())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.s2)
            .foregroundColor(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var foreground: Color {
        if !isEnabled { return DS.textSubtle }
        return isSelected ? DS.primaryDeep : DS.textSecondary
    }

    private var background: Color {
        if !isEnabled { return DS.surfaceSunken.opacity(0.6) }
        return isSelected ? DS.primaryContainer : DS.surfaceSunken
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
