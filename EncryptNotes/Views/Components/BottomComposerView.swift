import SwiftUI

struct BottomComposerView: View {
    let onCreateNote: () -> Void
    let isDisabled: Bool

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                TextField("点击创建笔记...", text: .constant(""))
                    .font(.subheadline)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .disabled(true)

                Button(action: onCreateNote) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundColor(isDisabled ? .gray : .accentColor)
                        .scaleEffect(isPressed ? 0.9 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
                }
                .disabled(isDisabled)
                .buttonStyle(.plain)
                .pressEvents {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                } onRelease: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
}