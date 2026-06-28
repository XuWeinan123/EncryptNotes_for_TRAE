import SwiftUI

struct NoteCardView: View {
    let note: Note
    var isSelected: Bool = false
    var isSelecting: Bool = false
    var onTap: (() -> Void)?
    var onEdit: (() -> Void)?
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

                tagAwareText(note.body)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.cardPadding)
        .padding(.vertical, DS.cardPadding)
        .dsCardSurface(shadow: false)
        .opacity(isPressed ? 0.92 : 1.0)
        .scaleEffect(isPressed ? 0.985 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelect?()
            } else {
                onTap?()
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
        let pattern = TagParser.pattern
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Text(source)
                .font(DS.body())
                .foregroundColor(DS.textBody)
        }

        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))

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
