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

    private var lines: [String] {
        note.body
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var title: String {
        lines.first ?? "无标题笔记"
    }

    private var previewLines: [String] {
        Array(lines.dropFirst().prefix(5))
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.s3) {
            if isSelecting {
                selectionCircle
                    .padding(.top, DS.s1)
            }

            VStack(alignment: .leading, spacing: DS.s3) {
                HStack(spacing: DS.s1) {
                    Text(DateFormatters.formatDisplayDateTime(note.updatedAt).replacingOccurrences(of: ".", with: "-"))
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)

                    Spacer()

                    SWStatusBadge(
                        note.isEncrypted ? "加密" : "明文",
                        systemImage: note.isEncrypted ? "lock.open.fill" : "doc.text",
                        style: note.isEncrypted ? .success : .neutral
                    )

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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DS.textSubtle)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                    }
                }

                Text(title)
                    .font(DS.bodyLg())
                    .foregroundColor(DS.textEmphasize)
                    .lineLimit(2)

                if !previewLines.isEmpty {
                    VStack(alignment: .leading, spacing: DS.s2) {
                        ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                            tagAwareText(line)
                                .lineLimit(1)
                        }
                    }
                }
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
