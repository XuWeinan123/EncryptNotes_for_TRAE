import Foundation
import SwiftUI

struct TrashView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var showingEmptyTrashConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            SWPageHeader(
                title: "回收站",
                subtitle: vaultStore.trashNotes.isEmpty ? "这里暂时没有已删除笔记" : "删除的笔记会在这里保留 30 天",
                systemImage: "trash",
                tint: vaultStore.trashNotes.isEmpty ? DS.textSubtle : DS.destructive
            )
            .padding(DS.s3)

            HStack(spacing: DS.s2) {
                SWStatusBadge("\(vaultStore.trashNotes.count) 条", systemImage: "doc.text", style: vaultStore.trashNotes.isEmpty ? .neutral : .error)
                Spacer()
                Button(role: .destructive) {
                    showingEmptyTrashConfirmation = true
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vaultStore.trashNotes.isEmpty)
            }
            .padding(.horizontal, DS.s3)
            .padding(.bottom, DS.s3)
            .background(DS.surfaceRaised)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DS.line)
                    .frame(height: 0.5)
            }

            List {
                if vaultStore.trashNotes.isEmpty {
                    emptyRow
                        .listRowInsets(EdgeInsets(top: DS.s3, leading: DS.s3, bottom: DS.s3, trailing: DS.s3))
                        .listRowSeparator(.hidden)
                        .listRowBackground(DS.bg)
                } else {
                    ForEach(vaultStore.trashNotes) { trashNote in
                        trashRow(for: trashNote)
                            .listRowInsets(EdgeInsets(top: DS.s1, leading: DS.s3, bottom: DS.s1, trailing: DS.s3))
                            .listRowSeparator(.hidden)
                            .listRowBackground(DS.bg)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
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

    private var emptyRow: some View {
        SWEmptyState(
            title: "回收站为空",
            message: "删除的笔记会在这里保留 30 天",
            systemImage: "trash"
        )
    }

    @ViewBuilder
    private func trashRow(for trashNote: TrashNote) -> some View {
        SWNoteListRow(
            title: trashTitle(for: trashNote),
            subtitle: "删除于 \(timeString(from: trashNote.deletedAt))",
            systemImage: trashNote.isEncrypted ? "lock.fill" : "doc.text",
            tint: trashNote.isEncrypted ? DS.primaryDeep : DS.textSubtle
        ) {
            HStack(spacing: DS.s1) {
                SWStatusBadge(trashNote.isEncrypted ? "加密" : "明文", systemImage: trashNote.isEncrypted ? "lock.fill" : "doc.text", style: trashNote.isEncrypted ? .success : .neutral)
                SWStatusBadge("剩 \(trashNote.remainingDays) 天", systemImage: "clock", style: .warning)

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

    private func trashTitle(for trashNote: TrashNote) -> String {
        if let body = trashNote.body {
            return firstLine(of: body)
        } else if trashNote.isEncrypted {
            return "加密笔记"
        } else {
            return "(无内容)"
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
