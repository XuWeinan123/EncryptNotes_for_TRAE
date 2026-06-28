import SwiftUI

struct EncryptedCardView: View {
    let info: EncryptedNoteInfo
    var isSelected: Bool = false
    var isSelecting: Bool = false
    var onDelete: (() -> Void)?
    var onToggleSelect: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.s3) {
            if isSelecting {
                selectionCircle
                    .padding(.top, DS.s1)
            }

            VStack(alignment: .leading, spacing: DS.memoGap) {
                HStack(spacing: DS.s2) {
                    Text(timestampText)
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                        .lineLimit(1)

                    Spacer()

                    if !isSelecting {
                        Menu {
                            if let onDelete {
                                Button(role: .destructive) { onDelete() } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DS.textSubtle)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                    }
                }

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
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface(shadow: false)
        .opacity(isPressed ? 0.92 : 1.0)
        .scaleEffect(isPressed ? 0.985 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelect?()
            }
        }
        .pressEvents {
            if !isSelecting {
                withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
            }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.15)) { isPressed = false }
        }
    }

    private var timestampText: String {
        let timestamp = DateFormatters.formatDisplayDateTime(info.updatedAt)
            .replacingOccurrences(of: ".", with: "-")
        return "\(timestamp) · 加密"
    }

    private var selectionCircle: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .foregroundColor(isSelected ? DS.primary : DS.textSubtle.opacity(0.5))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture { onToggleSelect?() }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
