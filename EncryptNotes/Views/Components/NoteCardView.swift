import SwiftUI

struct NoteCardView: View {
    let note: Note

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(4)

            Text(DateFormatters.formatDisplayDate(note.updatedAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
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
