import SwiftUI

/// 未导入密钥时明文笔记的卡片视图。
///
/// 显示锁定的小锁标志和乱码内容，视觉上与 `EncryptedCardView` 一致，
/// 但标签为「待加密」以区分于已加密笔记。
struct PlainNoteLockedCardView: View {
    let note: Note

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(DS.textSecondary)

                Text("待加密")
                    .font(DS.body())
                    .foregroundColor(DS.textSecondary)

                Spacer()

                Text(DateFormatters.formatDisplayDate(note.updatedAt))
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }

            Text(NoteObfuscator.garbledPreview(of: note.body))
                .font(DS.mono())
                .foregroundColor(DS.textSubtle)
                .lineLimit(2)

            HStack(spacing: DS.s1) {
                Text("未导入密钥")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)

                Text("·")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)

                Text("导入后可解密")
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
}
