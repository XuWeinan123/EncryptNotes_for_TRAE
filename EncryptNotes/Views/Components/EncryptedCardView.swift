import SwiftUI

struct EncryptedCardView: View {
    let info: EncryptedNoteInfo

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(DS.textSecondary)

                Text("已加密")
                    .font(DS.body())
                    .foregroundColor(DS.textSecondary)

                Spacer()

                Text(DateFormatters.formatDisplayDate(info.updatedAt))
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }

            Text(info.ciphertextPreview)
                .font(DS.mono())
                .foregroundColor(DS.textSubtle)
                .lineLimit(2)

            HStack(spacing: DS.s1) {
                Text("已加密")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)

                Text("·")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)

                Text(formatFileSize(info.fileSize))
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface()
        .shadow(color: DS.cardShadow.color,
                radius: isPressed ? 1 : 0,
                x: 0,
                y: isPressed ? -1 : 0)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
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

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
