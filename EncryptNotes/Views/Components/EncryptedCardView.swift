import SwiftUI

struct EncryptedCardView: View {
    let info: EncryptedNoteInfo
    var isKeyLoaded: Bool = false
    var isSelected: Bool = false
    var isSelecting: Bool = false
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleSelect: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DS.s3) {
            if isSelecting {
                selectionCircle
                    .padding(.top, DS.s1)
            }

            VStack(alignment: .leading, spacing: DS.noteGap) {
                HStack(spacing: DS.s2) {
                    Text(timestampText)
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                        .lineLimit(1)

                    Spacer()

                    if !isSelecting {
                        Menu {
                            if let onOpen {
                                Button { onOpen() } label: {
                                    Label(openActionTitle, systemImage: openActionIcon)
                                }
                            }
                            if onOpen != nil && onDelete != nil {
                                Divider()
                            }
                            if let onDelete {
                                Button(role: .destructive) { onDelete() } label: {
                                    Label("Delete", systemImage: "trash")
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

                Text(info.title)
                    .font(DS.body())
                    .foregroundColor(DS.textBody)
                    .lineLimit(1)

                Text(info.ciphertextPreview)
                    .font(DS.mono())
                    .foregroundColor(DS.textSubtle)
                    .lineLimit(3)
                    .opacity(0.7)

                HStack(spacing: DS.s1) {
                    Text(isKeyLoaded ? "Click to Unlock" : "Go to Key Settings")
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
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelect?()
            } else {
                onOpen?()
            }
        }
    }

    private var timestampText: String {
        let timestamp = DateFormatters.formatDisplayDateTime(info.updatedAt)
            .replacingOccurrences(of: ".", with: "-")
        return L10n.string("%@ · Encrypted", timestamp)
    }

    private var openActionTitle: String {
        isKeyLoaded ? "Unlock to View" : "Open Key Settings"
    }

    private var openActionIcon: String {
        isKeyLoaded ? "lock.open" : "key"
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
