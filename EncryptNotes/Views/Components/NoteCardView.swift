import SwiftUI

/// 可读笔记卡片（明文笔记或已解密加密笔记）。
struct NoteCardView: View {
    let note: Note

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
        VStack(alignment: .leading, spacing: DS.s3) {
            // 时间戳 + 加密状态 icon
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
            }

            // 标题
            Text(title)
                .font(DS.bodyLg())
                .foregroundColor(DS.textEmphasize)
                .lineLimit(2)

            // 预览行，#tags 用叶绿色
            if !previewLines.isEmpty {
                VStack(alignment: .leading, spacing: DS.s2) {
                    ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                        tagAwareText(line)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.cardPadding)
        .padding(.vertical, DS.cardPadding)
        .dsCardSurface()
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

    /// 将 `#tags` 渲染为叶绿色，其余文字保持正文色。
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
