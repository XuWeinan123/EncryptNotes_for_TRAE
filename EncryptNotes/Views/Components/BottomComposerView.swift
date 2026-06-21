import SwiftUI

struct BottomComposerView: View {
    let onCreateNote: () -> Void
    let isDisabled: Bool

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
                }
                .disabled(isDisabled)
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
}
