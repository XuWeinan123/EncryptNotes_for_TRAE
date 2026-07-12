import SwiftUI

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vaultStore = VaultStore.shared

    @State private var noteToRestore: TrashNote?
    @State private var noteToPurge: TrashNote?
    @State private var showEmptyConfirmation = false
    @State private var searchText = ""
    @State private var actionErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                DS.bg.ignoresSafeArea()

                if filteredTrashNotes.isEmpty {
                    emptyState
                } else {
                    trashList
                }
            }
            .navigationTitle("回收站")
            .navigationBarTitleDisplayMode(.inline)
            .dsLiquidGlassToolbar()
            .searchable(text: $searchText, prompt: "搜索回收站")
            .autocorrectionDisabled()
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
                                actionErrorMessage = "恢复失败：\(error.localizedDescription)"
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
                                actionErrorMessage = "删除失败：\(error.localizedDescription)"
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
                            actionErrorMessage = "清空失败：\(error.localizedDescription)"
                        }
                    }
                }
            } message: {
                Text("将永久删除回收站中的所有笔记，无法恢复。")
            }
            .alert("操作失败", isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )) {
                Button("确定") { actionErrorMessage = nil }
            } message: {
                Text(actionErrorMessage ?? "")
            }
            .task {
                await vaultStore.purgeExpiredTrash()
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            SWEmptyState(
                title: vaultStore.trashNotes.isEmpty ? "回收站为空" : "没有匹配的笔记",
                message: vaultStore.trashNotes.isEmpty
                    ? "删除的笔记会在这里保留 30 天"
                    : "换个关键词试试，或清空搜索内容。",
                systemImage: vaultStore.trashNotes.isEmpty ? "trash" : "magnifyingglass"
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DS.s6)
    }

    private var trashList: some View {
        List {
            HStack {
                Spacer(minLength: 0)
                Text("回收站 \(filteredTrashNotes.count) 条笔记")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                Spacer(minLength: 0)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            ForEach(filteredTrashNotes) { trashNote in
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

    private var filteredTrashNotes: [TrashNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vaultStore.trashNotes }
        return vaultStore.trashNotes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || (!note.isEncrypted && note.body?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private func trashCard(_ trashNote: TrashNote) -> some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack {
                SWStatusBadge(
                    trashNote.isEncrypted ? "加密笔记" : "明文笔记",
                    systemImage: trashNote.isEncrypted ? (trashNote.isReadable ? "lock.open.fill" : "lock.fill") : "doc.text",
                    style: trashNote.isEncrypted ? .success : .neutral
                )

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

                SWStatusBadge("\(trashNote.remainingDays) 天", systemImage: "clock", style: .warning)
            }

            if trashNote.isEncrypted {
                Text(trashNote.title)
                    .font(DS.body().weight(.semibold))
                    .foregroundStyle(DS.textBody)
                    .lineLimit(2)
            } else if let body = trashNote.body {
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
