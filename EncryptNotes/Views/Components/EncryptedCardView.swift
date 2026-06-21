import SwiftUI

struct EncryptedCardView: View {
    let info: EncryptedNoteInfo

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
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
