import Foundation
import SwiftUI

struct TrashView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var showingEmptyTrashConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.s2) {
                SWStatusBadge("\(vaultStore.trashNotes.count) 条", systemImage: "doc.text", style: .neutral)
                Text(vaultStore.trashNotes.isEmpty ? "没有已删除笔记" : "删除的笔记会保留 30 天")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                Spacer()
                Button(role: .destructive) {
                    showingEmptyTrashConfirmation = true
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vaultStore.trashNotes.isEmpty)
                .help(vaultStore.trashNotes.isEmpty ? "回收站为空" : "永久删除回收站中的所有笔记")
            }
            .padding(.horizontal, DS.s3)
            .padding(.vertical, DS.s2)
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
                            .contextMenu {
                                Button("恢复") {
                                    Task {
                                        try? await vaultStore.restoreTrashNote(trashNote)
                                    }
                                }
                                Button("永久删除", role: .destructive) {
                                    Task {
                                        try? await vaultStore.permanentlyDeleteTrashNote(trashNote)
                                    }
                                }
                            }
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
            tint: trashNote.isEncrypted ? DS.primaryDeep : DS.textSubtle,
            style: .compact
        ) {
            HStack(spacing: DS.s2) {
                if trashNote.isEncrypted {
                    SWStatusBadge("加密", systemImage: "lock.fill", style: .neutral)
                }
                SWStatusBadge("剩 \(trashNote.remainingDays) 天", systemImage: "clock", style: .warning)

                Button {
                    Task {
                        try? await vaultStore.restoreTrashNote(trashNote)
                    }
                } label: {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("恢复")

                Menu {
                    Button("恢复") {
                        Task {
                            try? await vaultStore.restoreTrashNote(trashNote)
                        }
                    }
                    Divider()
                    Button("永久删除", role: .destructive) {
                        Task {
                            try? await vaultStore.permanentlyDeleteTrashNote(trashNote)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .help("更多操作")
            }
        }
    }

    private func trashTitle(for trashNote: TrashNote) -> String {
        if let body = trashNote.body {
            return firstLine(of: body)
        } else if trashNote.isEncrypted {
            return trashNote.title
        } else {
            return "(无内容)"
        }
    }

    private func firstLine(of body: String) -> String {
        NoteTitleFormatter.displayTitle(from: body, emptyTitle: NoteTitleFormatter.emptyTitle)
    }

    private func timeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
