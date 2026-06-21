import SwiftUI

struct NoteCardView: View {
    let note: Note

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(note.title.isEmpty ? "无标题" : note.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(DateFormatters.formatDisplayDate(note.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(note.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !note.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .cornerRadius(8)
                    }

                    if note.tags.count > 3 {
                        Text("+\(note.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .shadow(color: .black.opacity(isPressed ? 0.05 : 0.08), radius: isPressed ? 2 : 4, x: 0, y: isPressed ? 1 : 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = false
            }
        }
    }
}
