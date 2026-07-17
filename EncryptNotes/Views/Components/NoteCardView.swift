import SwiftUI

struct NoteCardView: View {
    let note: Note
    var displayTitle: String? = nil
    var excludesHexColorsFromTags: Bool = false
    var isCloudOnly: Bool = false
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

            VStack(alignment: .leading, spacing: DS.noteGap) {
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
                                    Label("Rename", systemImage: "pencil.line")
                                }
                            }
                            if let onEdit {
                                Button { onEdit() } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
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

                if isCloudOnly {
                    VStack(alignment: .leading, spacing: DS.s2) {
                        Text(displayTitle ?? NoteTitleFormatter.emptyTitle)
                            .font(DS.body().weight(.semibold))
                            .foregroundColor(DS.textBody)
                            .lineLimit(2)

                        Label("Stored in iCloud and downloaded when opened", systemImage: "icloud.and.arrow.down")
                            .font(DS.caption())
                            .foregroundColor(DS.textSubtle)
                    }
                } else if note.isEncrypted {
                    VStack(alignment: .leading, spacing: DS.s2) {
                        Text(displayTitle ?? NoteTitleFormatter.displayTitle(from: note.body))
                            .font(DS.body().weight(.semibold))
                            .foregroundColor(DS.textBody)
                            .lineLimit(2)

                        Label("Encrypted note; open to view content", systemImage: "lock.fill")
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
        return note.isEncrypted ? L10n.string("%@ · Encrypted", timestamp) : timestamp
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
                let beforeText = Text(before)
                    .font(DS.body())
                    .foregroundColor(DS.textBody)
                result = Text("\(result)\(beforeText)")
            }
            let tag = ns.substring(with: matchRange)
            let tagText = Text(tag)
                .font(DS.body())
                .foregroundColor(DS.primary)
            result = Text("\(result)\(tagText)")
            cursor = matchRange.location + matchRange.length
        }
        if cursor < ns.length {
            let tail = ns.substring(from: cursor)
            let tailText = Text(tail)
                .font(DS.body())
                .foregroundColor(DS.textBody)
            result = Text("\(result)\(tailText)")
        }
        return result
    }
}
