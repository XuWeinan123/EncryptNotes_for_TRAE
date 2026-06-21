import SwiftUI

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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(DateFormatters.formatDisplayDateTime(note.updatedAt).replacingOccurrences(of: ".", with: "-"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))

                    Text(title)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 13) {
                ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: line.hasPrefix("•") ? 17 : 19, weight: .regular))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }

            Text("展开")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color(red: 0.12, green: 0.58, blue: 1.0))
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(isPressed ? 0.985 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isPressed)
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isPressed = false
            }
        }
    }
}
