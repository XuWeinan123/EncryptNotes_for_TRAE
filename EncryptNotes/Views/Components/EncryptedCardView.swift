import SwiftUI

/// 未解密加密笔记的卡片：上锁 icon + 密文乱码 + 柔和模糊。
struct EncryptedCardView: View {
    let info: EncryptedNoteInfo

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.memoGap) {
            HStack(spacing: DS.s2) {
                Text(timestampText)
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.textSubtle)
            }

            // 密文乱码，适度模糊降低压迫感
            Text(info.ciphertextPreview)
                .font(DS.mono())
                .foregroundColor(DS.textSubtle)
                .lineLimit(3)
                .opacity(0.7)

            HStack(spacing: DS.s1) {
                Text("导入密钥后查看")
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
        .dsCardSurface(cornerRadius: DS.rLg, shadow: false)
        .opacity(isPressed ? 0.92 : 1.0)
        .scaleEffect(isPressed ? 0.985 : 1.0)
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

    private var timestampText: String {
        let timestamp = DateFormatters.formatDisplayDateTime(info.updatedAt)
            .replacingOccurrences(of: ".", with: "-")
        return "\(timestamp) · 加密"
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
