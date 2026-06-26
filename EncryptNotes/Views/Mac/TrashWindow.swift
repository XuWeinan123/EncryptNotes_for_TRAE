import Foundation
import SwiftUI

struct TrashView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var showingEmptyTrashConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("回收站")
                    .font(DS.title())
                Spacer()
                Button("清空回收站", role: .destructive) {
                    showingEmptyTrashConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vaultStore.trashNotes.isEmpty)
            }
            .padding(DS.s3)

            List {
                ForEach(vaultStore.trashNotes) { trashNote in
                    trashRow(for: trashNote)
                        .padding(.vertical, DS.s1)
                }
            }
            .listStyle(.plain)
        }
        .background(DS.bg)
        .alert("确认清空回收站？", isPresented: $showingEmptyTrashConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task {
                    try? await vaultStore.emptyTrash()
                }
            }
        } message: {
            Text("回收站中的所有笔记将被永久删除，无法恢复。")
        }
    }

    @ViewBuilder
    private func trashRow(for trashNote: TrashNote) -> some View {
        HStack(alignment: .top, spacing: DS.s2) {
            Image(systemName: trashNote.isEncrypted ? "lock.fill" : "doc.text")
                .foregroundColor(trashNote.isEncrypted ? DS.primary : DS.textSubtle)
                .font(.system(size: 12))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                if let body = trashNote.body {
                    Text(firstLine(of: body))
                        .font(DS.body())
                        .foregroundColor(DS.textStrong)
                        .lineLimit(1)
                } else if trashNote.isEncrypted {
                    Text("加密笔记")
                        .font(DS.body())
                        .foregroundColor(DS.textSecondary)
                } else {
                    Text("(无内容)")
                        .font(DS.body())
                        .foregroundColor(DS.textSubtle)
                }

                Text("删除于 \(timeString(from: trashNote.deletedAt))")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }

            Spacer()

            HStack(spacing: DS.s1) {
                Button("恢复") {
                    Task {
                        try? await vaultStore.restoreTrashNote(trashNote)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("永久删除", role: .destructive) {
                    Task {
                        try? await vaultStore.permanentlyDeleteTrashNote(trashNote)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func firstLine(of body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(空笔记)" }
        return String(trimmed.components(separatedBy: .newlines).first { !$0.isEmpty } ?? "(空笔记)")
    }

    private func timeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
