import SwiftUI

struct EncryptedCardView: View {
    let info: EncryptedNoteInfo

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)

                Text("已加密")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(DateFormatters.formatDisplayDate(info.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(info.ciphertextPreview)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            HStack {
                Text("已加密")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(formatFileSize(info.fileSize))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .shadow(color: .black.opacity(isPressed ? 0.05 : 0.08), radius: isPressed ? 2 : 4, x: 0, y: isPressed ? 1 : 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = false
            }
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
