import SwiftUI

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vaultStore = VaultStore.shared

    @State private var noteToRestore: TrashNote?
    @State private var noteToPurge: TrashNote?
    @State private var showEmptyConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.bg.ignoresSafeArea()

                if vaultStore.trashNotes.isEmpty {
                    emptyState
                } else {
                    trashList
                }
            }
            .navigationTitle("回收站")
            .navigationBarTitleDisplayMode(.inline)
            .dsLiquidGlassToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                if !vaultStore.trashNotes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showEmptyConfirmation = true } label: {
                            Image(systemName: "trash")
                        }
                        .tint(DS.destructive)
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
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DS.s6)
    }

    private var trashList: some View {
        List {
            ForEach(vaultStore.trashNotes) { trashNote in
                trashCard(trashNote)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(
                        top: DS.s1 + 2,
                        leading: DS.s3,
                        bottom: DS.s1 + 2,
                        trailing: DS.s3
                    ))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            noteToRestore = trashNote
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.backward")
                        }
                        .tint(DS.primary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            noteToPurge = trashNote
                        } label: {
                            Label("永久删除", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            noteToRestore = trashNote
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.backward")
                        }

                        Button(role: .destructive) {
                            noteToPurge = trashNote
                        } label: {
                            Label("永久删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.top, DS.s2)
    }

    private func trashCard(_ trashNote: TrashNote) -> some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack {
                Label(
                    trashNote.isEncrypted ? "加密笔记" : "明文笔记",
                    systemImage: trashNote.isEncrypted ? (trashNote.isReadable ? "lock.open.fill" : "lock.fill") : "doc.text"
                )
                .foregroundStyle(.secondary)
                .font(DS.caption())

                Spacer()

                Menu {
                    Button {
                        noteToRestore = trashNote
                    } label: {
                        Label("恢复", systemImage: "arrow.uturn.backward")
                    }

                    Button(role: .destructive) {
                        noteToPurge = trashNote
                    } label: {
                        Label("永久删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.textSubtle)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: DS.s2) {
                Text("删除于 \(DateFormatters.formatDisplayDateTime(trashNote.deletedAt).replacingOccurrences(of: ".", with: "-"))")
                    .font(DS.caption())
                    .foregroundStyle(DS.textSubtle)

                Spacer()

                Text("剩 \(trashNote.remainingDays) 天")
                    .font(DS.caption())
                    .foregroundStyle(DS.textSubtle)
            }

            if let body = trashNote.body {
                Text(body)
                    .font(DS.body())
                    .foregroundStyle(DS.textBody)
                    .lineLimit(3)
            } else if let preview = trashNote.ciphertextPreview {
                Text(preview)
                    .font(DS.mono())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface(shadow: false)
    }
}
