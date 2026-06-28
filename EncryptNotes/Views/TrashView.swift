import SwiftUI

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vaultStore = VaultStore.shared

    @State private var noteToRestore: TrashNote?
    @State private var noteToPurge: TrashNote?
    @State private var showEmptyConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if vaultStore.trashNotes.isEmpty {
                    emptyState
                } else {
                    noteList
                }
            }
            .dsCanvasBackground()
            .navigationTitle("回收站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                if !vaultStore.trashNotes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showEmptyConfirmation = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(DS.destructive)
                        }
                    }
                }
            }
            .alert("恢复笔记", isPresented: Binding(
                get: { noteToRestore != nil },
                set: { if !$0 { noteToRestore = nil } }
            )) {
                Button("取消", role: .cancel) { noteToRestore = nil }
                Button("恢复") {
                    if let note = noteToRestore {
                        Task {
                            do {
                                try await vaultStore.restoreTrashNote(note)
                            } catch {
                                vaultStore.lastError = "恢复失败：\(error.localizedDescription)"
                            }
                        }
                    }
                    noteToRestore = nil
                }
            } message: {
                Text("恢复后笔记将回到主列表。")
            }
            .alert("永久删除", isPresented: Binding(
                get: { noteToPurge != nil },
                set: { if !$0 { noteToPurge = nil } }
            )) {
                Button("取消", role: .cancel) { noteToPurge = nil }
                Button("永久删除", role: .destructive) {
                    if let note = noteToPurge {
                        Task {
                            do {
                                try await vaultStore.permanentlyDeleteTrashNote(note)
                            } catch {
                                vaultStore.lastError = "删除失败：\(error.localizedDescription)"
                            }
                        }
                    }
                    noteToPurge = nil
                }
            } message: {
                Text("永久删除后无法恢复。")
            }
            .alert("清空回收站", isPresented: $showEmptyConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    Task {
                        do {
                            try await vaultStore.emptyTrash()
                        } catch {
                            vaultStore.lastError = "清空失败：\(error.localizedDescription)"
                        }
                    }
                }
            } message: {
                Text("将永久删除回收站中的所有笔记，无法恢复。")
            }
            .task {
                await vaultStore.purgeExpiredTrash()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.s4) {
            Spacer()
            Image(systemName: "trash")
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(DS.textSubtle)
            Text("回收站为空")
                .font(DS.title())
                .foregroundColor(DS.textSecondary)
            Text("删除的笔记会在这里保留 30 天")
                .font(DS.body())
                .foregroundColor(DS.textSubtle)
            Spacer()
        }
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: DS.memoGap) {
                ForEach(vaultStore.trashNotes) { trashNote in
                    TrashCardView(
                        trashNote: trashNote,
                        onRestore: { noteToRestore = trashNote },
                        onPurge: { noteToPurge = trashNote }
                    )
                }
            }
            .padding(.horizontal, DS.cardPadding)
            .padding(.top, DS.s3)
            .padding(.bottom, DS.s8)
            .frame(maxWidth: DS.contentMax)
            .frame(maxWidth: .infinity)
        }
    }
}
