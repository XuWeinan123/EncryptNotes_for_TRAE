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

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
