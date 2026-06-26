import Foundation
import SwiftUI

struct AllNotesView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var searchText = ""
    @State private var selectedTag: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DS.textSubtle)
                TextField("搜索笔记…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(DS.s2)
            .background(DS.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
            .padding(DS.s3)

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
        }
        .background(DS.bg)
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

    private func tagChip(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(DS.caption())
                .padding(.horizontal, DS.s2)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                        .fill(isSelected ? DS.primaryContainer : DS.surfaceSunken)
                )
                .foregroundColor(isSelected ? DS.primary : DS.textSecondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func noteRow(for item: NoteListItem) -> some View {
        switch item {
        case .readable(let note):
            HStack {
                Image(systemName: note.isEncrypted ? "lock.fill" : "doc.text")
                    .foregroundColor(note.isEncrypted ? DS.primary : DS.textSubtle)
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
            .padding(.vertical, DS.s1)

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
            .padding(.vertical, DS.s1)
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
}
