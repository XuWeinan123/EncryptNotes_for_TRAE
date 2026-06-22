import SwiftUI

struct BottomComposerView: View {
    let onCreateNote: () -> Void
    let isDisabled: Bool

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(DS.line)

            HStack(spacing: DS.s3) {
                TextField("点击创建笔记...", text: .constant(""))
                    .font(DS.body())
                    .foregroundColor(DS.textBody)
                    .padding(.vertical, 10)
                    .padding(.horizontal, DS.s3)
                    .background(DS.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                            .stroke(DS.line, lineWidth: 0.5)
                    )
                    .disabled(true)

                Button(action: onCreateNote) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundColor(isDisabled ? DS.textSubtle : DS.primary)
                        .scaleEffect(isPressed ? 0.92 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: isPressed)
                }
                .disabled(isDisabled)
                .buttonStyle(.plain)
                .pressEvents {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                } onRelease: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPressed = false
                    }
                }
            }
            .padding(DS.cardPadding)
            .background(DS.surfaceCard)
        }
    }
}
