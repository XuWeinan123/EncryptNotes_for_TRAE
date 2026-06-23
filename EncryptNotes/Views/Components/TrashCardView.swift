import SwiftUI

/// 回收站笔记卡片：明文/已解密加密/未解密加密三种态。
struct TrashCardView: View {
    let trashNote: TrashNote

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack {
                Image(systemName: trashNote.isEncrypted ? (trashNote.isReadable ? "lock.open.fill" : "lock.fill") : "doc.text")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(DS.textSecondary)

                Text(trashNote.isEncrypted ? "加密笔记" : "明文笔记")
                    .font(DS.body())
                    .foregroundColor(DS.textSecondary)

                Spacer()

                Text("剩 \(trashNote.remainingDays) 天")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }

            if let body = trashNote.body {
                Text(body)
                    .font(DS.body())
                    .foregroundColor(DS.textBody)
                    .lineLimit(3)
            } else if let preview = trashNote.ciphertextPreview {
                Text(preview)
                    .font(DS.mono())
                    .foregroundColor(DS.textSubtle)
                    .lineLimit(2)
                    .opacity(0.7)
            }

            Text("删除于 \(DateFormatters.formatDisplayDateTime(trashNote.deletedAt).replacingOccurrences(of: ".", with: "-"))")
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface()
    }
}
