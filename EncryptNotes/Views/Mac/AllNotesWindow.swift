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
            HStack(spacing: DS.s2) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DS.textSubtle)
                    TextField("搜索笔记…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DS.body())
                }
                .padding(.horizontal, DS.s3)
                .padding(.vertical, DS.s2)
                .dsInputSurface()

                Button(action: { showingClearEmptyConfirmation = true }) {
                    Image(systemName: "trash")
                    Text("清空空笔记")
                }
                .font(DS.caption())
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(DS.destructive)
                .disabled(emptyNotes.isEmpty || isClearingEmptyNotes)
                .help(emptyNotes.isEmpty ? "没有空笔记" : "将空笔记移到回收站")
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
                    tagChip(name: "全部", isSelected: selectedTag == nil) {
                        selectedTag = nil
                    }
                    ForEach(vaultStore.allTags) { tagCount in
                        tagChip(name: tagCount.tag, isSelected: selectedTag == tagCount.tag) {
                            selectedTag = tagCount.tag
                        }
                    }
                }
                .padding(.horizontal, DS.s3)
                .padding(.top, DS.s2)
            }
            .padding(.bottom, DS.s2)

            List {
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

    private func tagChip(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(DS.caption())
                .padding(.horizontal, DS.s2)
                .padding(.vertical, DS.s1)
                .background(
                    RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                        .fill(isSelected ? DS.primaryContainer : DS.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                        .stroke(isSelected ? DS.primary.opacity(0.24) : DS.line, lineWidth: 0.5)
                )
                .foregroundColor(isSelected ? DS.primaryDeep : DS.textSecondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func noteRow(for item: NoteListItem) -> some View {
        switch item {
        case .readable(let note):
            HStack {
                Image(systemName: note.isEncrypted ? "lock.fill" : "doc.text")
                    .foregroundColor(note.isEncrypted ? DS.primaryDeep : DS.textSubtle)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(firstLine(of: note.body))
                        .font(DS.body())
                        .foregroundColor(DS.textStrong)
                        .lineLimit(1)

                    Text(note.isEncrypted ? "加密" : "明文")
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                }

                Spacer()

                Text(timeString(from: note.updatedAt))
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
            .padding(.horizontal, DS.s2)
            .padding(.vertical, DS.s2)
            .dsInputSurface()
            .listRowInsets(EdgeInsets(top: DS.s1, leading: DS.s3, bottom: DS.s1, trailing: DS.s3))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.bg)

        case .locked(let info):
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundColor(DS.textSubtle)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("加密笔记 · 未加载密钥")
                        .font(DS.body())
                        .foregroundColor(DS.textSecondary)

                    Text("加密")
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                }

                Spacer()

                Text(timeString(from: info.updatedAt))
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
            .padding(.horizontal, DS.s2)
            .padding(.vertical, DS.s2)
            .dsInputSurface()
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
