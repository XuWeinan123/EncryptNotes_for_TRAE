import Foundation
import SwiftUI

struct AllNotesView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var showingClearEmptyConfirmation = false
    @State private var isClearingEmptyNotes = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: DS.s3) {
                SWPageHeader(
                    title: "全部笔记",
                    subtitle: selectedTag.map { "正在筛选 #\($0)" } ?? "浏览、搜索和打开所有可读笔记",
                    systemImage: "tray.full",
                    tint: DS.primaryDeep
                )

                HStack(spacing: DS.s2) {
                    SWSearchField(placeholder: "搜索笔记…", text: $searchText)

                    SWStatusBadge("\(filteredNotes.count) 条", systemImage: "doc.text", style: .success)
                    if !emptyNotes.isEmpty {
                        SWStatusBadge("\(emptyNotes.count) 条空笔记", systemImage: "exclamationmark.triangle", style: .warning)
                    }

                    Button {
                        showingClearEmptyConfirmation = true
                    } label: {
                        Label("清空空笔记", systemImage: "trash")
                    }
                    .font(DS.caption())
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(DS.destructive)
                    .disabled(emptyNotes.isEmpty || isClearingEmptyNotes)
                    .help(emptyNotes.isEmpty ? "没有空笔记" : "将空笔记移到回收站")
                }
            }
            .padding(DS.s3)
            .background(DS.surfaceRaised)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DS.line)
                    .frame(height: 0.5)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.s1) {
                    SWFilterChip(title: "全部", isSelected: selectedTag == nil) {
                        selectedTag = nil
                    }
                    ForEach(vaultStore.allTags) { tagCount in
                        SWFilterChip(title: tagCount.tag, isSelected: selectedTag == tagCount.tag) {
                            selectedTag = tagCount.tag
                        }
                    }
                }
                .padding(.horizontal, DS.s3)
                .padding(.top, DS.s2)
            }
            .padding(.bottom, DS.s2)

            List {
                if filteredNotes.isEmpty {
                    SWEmptyState(
                        title: "没有匹配的笔记",
                        message: emptyStateMessage,
                        systemImage: "magnifyingglass"
                    )
                    .listRowInsets(EdgeInsets(top: DS.s3, leading: DS.s3, bottom: DS.s3, trailing: DS.s3))
                    .listRowSeparator(.hidden)
                    .listRowBackground(DS.bg)
                } else {
                    ForEach(filteredNotes) { item in
                        noteRow(for: item)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                openNote(item)
                            }
                            .contextMenu {
                                Button("打开") { openNote(item) }
                                Divider()
                                Button("移到回收站", role: .destructive) {
                                    deleteNote(item)
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
        }
        .background(DS.bg)
        .alert(isPresented: $showingClearEmptyConfirmation) {
            Alert(
                title: Text("清空空笔记？"),
                message: Text("将 \(emptyNotes.count) 条空笔记移到回收站，可以恢复。"),
                primaryButton: .destructive(Text("清空")) {
                    clearEmptyNotes()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var filteredNotes: [NoteListItem] {
        var items = vaultStore.readableNotes

        if let tag = selectedTag {
            items = items.filter { note in
                TagParser.tags(in: note.body).contains(tag)
            }
        }

        if !searchText.isEmpty {
            items = items.filter {
                $0.body.localizedCaseInsensitiveContains(searchText)
            }
        }

        var result: [NoteListItem] = items.map { .readable($0) }

        if selectedTag == nil && searchText.isEmpty {
            result.append(contentsOf: vaultStore.lockedEncryptedNotes.map { .locked($0) })
        }

        return result
    }

    private var emptyNotes: [Note] {
        vaultStore.readableNotes.filter { isEmptyNote($0) }
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "换个关键词试试，或清空搜索内容。"
        }
        if selectedTag != nil {
            return "这个标签下暂时没有可读笔记。"
        }
        return "创建第一条笔记后会出现在这里。"
    }

    @ViewBuilder
    private func noteRow(for item: NoteListItem) -> some View {
        switch item {
        case .readable(let note):
            SWNoteListRow(
                title: firstLine(of: note.body),
                subtitle: note.isEncrypted ? "加密笔记" : "明文笔记",
                systemImage: note.isEncrypted ? "lock.fill" : "doc.text",
                tint: note.isEncrypted ? DS.primaryDeep : DS.textSubtle
            ) {
                HStack(spacing: DS.s2) {
                    SWStatusBadge(note.isEncrypted ? "加密" : "明文", systemImage: note.isEncrypted ? "lock.fill" : "doc.text", style: note.isEncrypted ? .success : .neutral)
                    Text(timeString(from: note.updatedAt))
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                }
            }
            .listRowInsets(EdgeInsets(top: DS.s1, leading: DS.s3, bottom: DS.s1, trailing: DS.s3))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.bg)

        case .locked(let info):
            SWNoteListRow(
                title: "加密笔记 · 未加载密钥",
                subtitle: "加密笔记",
                systemImage: "lock.fill",
                tint: DS.textSubtle
            ) {
                HStack(spacing: DS.s2) {
                    SWStatusBadge("锁定", systemImage: "lock.fill", style: .neutral)
                    Text(timeString(from: info.updatedAt))
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                }
            }
            .listRowInsets(EdgeInsets(top: DS.s1, leading: DS.s3, bottom: DS.s1, trailing: DS.s3))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.bg)
        }
    }

    private func firstLine(of body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(空笔记)" }
        return String(trimmed.components(separatedBy: .newlines).first { !$0.isEmpty } ?? "(空笔记)")
    }

    private func isEmptyNote(_ note: Note) -> Bool {
        note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func timeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func openNote(_ item: NoteListItem) {
        switch item {
        case .readable(let note):
            MacMenuBarController.shared.openStickyNote(for: note)
        case .locked(let info):
            MacMenuBarController.shared.openLockedStickyNote(for: info)
        }
    }

    private func deleteNote(_ item: NoteListItem) {
        Task {
            switch item {
            case .readable(let note):
                try? await vaultStore.deleteNote(note)
            case .locked(let info):
                try? await vaultStore.deleteLockedNote(info)
            }
        }
    }

    private func clearEmptyNotes() {
        let notesToDelete = emptyNotes
        guard !notesToDelete.isEmpty else { return }

        isClearingEmptyNotes = true
        Task {
            for note in notesToDelete {
                StickyNoteWindowManager.shared.closeWindow(for: note.id)
                try? await vaultStore.deleteNote(note)
            }
            isClearingEmptyNotes = false
        }
    }
}
