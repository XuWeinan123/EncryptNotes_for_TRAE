import SwiftUI

struct NoteCardView: View {
    let note: Note
    var displayTitle: String? = nil
    var excludesHexColorsFromTags: Bool = false
    var isSelected: Bool = false
    var isSelecting: Bool = false
    var onTap: (() -> Void)?
    var onRename: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleSelect: (() -> Void)?

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
                            if let onRename {
                                Button { onRename() } label: {
                                    Label("重命名", systemImage: "pencil.line")
                                }
                            }
                            if let onEdit {
                                Button { onEdit() } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                            }
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

                if note.isEncrypted {
                    VStack(alignment: .leading, spacing: DS.s2) {
                        Text(displayTitle ?? NoteTitleFormatter.displayTitle(from: note.body))
                            .font(DS.body().weight(.semibold))
                            .foregroundColor(DS.textBody)
                            .lineLimit(2)

                        Label("加密笔记，打开后查看正文", systemImage: "lock.fill")
                            .font(DS.caption())
                            .foregroundColor(DS.textSubtle)
                    }
                } else {
                    tagAwareText(note.body)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.cardPadding)
        .padding(.vertical, DS.cardPadding)
        .dsCardSurface(shadow: false)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelect?()
            } else {
                onTap?()
            }
        }
    }

    private var timestampText: String {
        let timestamp = DateFormatters.formatDisplayDateTime(note.updatedAt)
            .replacingOccurrences(of: ".", with: "-")
        return note.isEncrypted ? "\(timestamp) · 加密" : timestamp
    }

    private var selectionCircle: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .foregroundColor(isSelected ? DS.primary : DS.textSubtle.opacity(0.5))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture { onToggleSelect?() }
    }

    private func tagAwareText(_ source: String) -> Text {
        let ns = source as NSString
        let matches = TagParser.matches(
            in: source,
            excludingHexColors: excludesHexColorsFromTags
        )

        if matches.isEmpty {
            return Text(source)
                .font(DS.body())
                .foregroundColor(DS.textBody)
        }

        var result = Text("")
        var cursor = 0
        for match in matches {
            let matchRange = match.range
            if matchRange.location > cursor {
                let before = ns.substring(with: NSRange(location: cursor, length: matchRange.location - cursor))
                result = result + Text(before)
                    .font(DS.body())
                    .foregroundColor(DS.textBody)
            }
            let tag = ns.substring(with: matchRange)
            result = result + Text(tag)
                .font(DS.body())
                .foregroundColor(DS.primary)
            cursor = matchRange.location + matchRange.length
        }
        if cursor < ns.length {
            let tail = ns.substring(from: cursor)
            result = result + Text(tail)
                .font(DS.body())
                .foregroundColor(DS.textBody)
        }
        return result
    }
}
