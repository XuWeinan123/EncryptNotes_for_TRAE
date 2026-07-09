import Foundation
import SwiftUI
import AppKit

struct AllNotesView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var renamingNote: Note?
    @State private var renameTitle = ""
    @State private var renameErrorMessage: String?
    @State private var isRenamingNote = false
    @State private var isSearchBarVisible = false

    var body: some View {
        VStack(spacing: 0) {
            if isSearchBarVisible {
                MacListSearchBar(
                    placeholder: "搜索笔记…",
                    text: $searchText,
                    onClose: { hideSearchBar() }
                )
            }

            listSummary

            tagFilters

            List {
                if isLoading {
                    SWEmptyState(
                        title: "正在加载笔记",
                        message: "笔记会在同步和索引读取完成后显示。",
                        systemImage: "tray.full"
                    )
                    .listRowInsets(EdgeInsets(top: DS.s3, leading: DS.s3, bottom: DS.s3, trailing: DS.s3))
                    .listRowSeparator(.hidden)
                    .listRowBackground(DS.bg)
                } else if filteredNotes.isEmpty {
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
                                if case .readable(let note) = item {
                                    Button("重命名...") { beginRenaming(note) }
                                }
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
        .dsLiquidGlassToolbar()
        .navigationTitle("全部笔记")
        .toolbar { allNotesToolbar }
        .background(MacListSearchToolbarAppearance(isActive: isSearchBarVisible))
        .sheet(isPresented: renameSheetBinding) {
            if let note = renamingNote {
                AllNotesRenameSheet(
                    title: $renameTitle,
                    errorMessage: renameErrorMessage,
                    isSaving: isRenamingNote,
                    onCancel: { finishRenaming() },
                    onSave: { renameNote(note) }
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var allNotesToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                toggleSearchBar()
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("搜索")
            .keyboardShortcut("f", modifiers: .command)
        }
    }

    private func toggleSearchBar() {
        if isSearchBarVisible {
            hideSearchBar()
        } else {
            isSearchBarVisible = true
        }
    }

    private func hideSearchBar() {
        isSearchBarVisible = false
        searchText = ""
    }

    private var listSummary: some View {
        HStack(spacing: DS.s2) {
            Text(noteCountText)
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
            if !emptyNotes.isEmpty {
                SWStatusBadge("\(emptyNotes.count) 条空笔记", systemImage: "exclamationmark.triangle", style: .warning)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s3)
        .padding(.top, DS.s3)
        .padding(.bottom, DS.s2)
    }

    @ViewBuilder
    private var tagFilters: some View {
        if !vaultStore.allTags.isEmpty || selectedTag != nil {
            HStack(spacing: DS.s1) {
                SWFilterChip(title: "全部", isSelected: selectedTag == nil) {
                    selectedTag = nil
                }
                ForEach(visibleTagCounts) { tagCount in
                    SWFilterChip(title: tagCount.tag, isSelected: selectedTag == tagCount.tag) {
                        selectedTag = tagCount.tag
                    }
                }
                if let selectedTag, !visibleTagCounts.contains(where: { $0.tag == selectedTag }) {
                    SWFilterChip(title: selectedTag, isSelected: true) {}
                }
                if !overflowTagCounts.isEmpty {
                    Menu {
                        ForEach(overflowTagCounts) { tagCount in
                            Button(tagCount.tag) {
                                selectedTag = tagCount.tag
                            }
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis")
                            .font(DS.caption())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.s3)
            .padding(.bottom, DS.s2)
        }
    }

    private var filteredNotes: [NoteListItem] {
        var items = vaultStore.readableNotes
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let tag = selectedTag {
            items = items.filter { note in
                TagParser.tags(in: note.body).contains(tag)
            }
        }

        if !query.isEmpty {
            items = items.filter { vaultStore.noteMatchesSearch($0, searchText: query) }
        }

        var result: [NoteListItem] = items.map { .readable($0) }

        if selectedTag == nil {
            let locked = query.isEmpty
                ? vaultStore.lockedEncryptedNotes
                : vaultStore.lockedEncryptedNotes.filter { vaultStore.lockedNoteMatchesSearch($0, searchText: query) }
            result.append(contentsOf: locked.map { .locked($0) })
        }

        return result
    }

    private var isLoading: Bool {
        if case .loading = vaultStore.state { return true }
        return false
    }

    private var noteCountText: String {
        isLoading ? "全部笔记加载中" : "全部 \(filteredNotes.count) 条笔记"
    }

    private var emptyNotes: [Note] {
        vaultStore.readableNotes.filter { isEmptyNote($0) }
    }

    private var visibleTagCounts: [TagCount] {
        Array(vaultStore.allTags.prefix(8))
    }

    private var overflowTagCounts: [TagCount] {
        Array(vaultStore.allTags.dropFirst(8))
    }

    private var emptyStateMessage: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                title: vaultStore.displayTitle(for: note, emptyTitle: NoteTitleFormatter.emptyTitle),
                subtitle: note.isEncrypted ? "加密笔记" : "明文笔记",
                systemImage: note.isEncrypted ? "lock.fill" : "doc.text",
                tint: note.isEncrypted ? DS.primaryDeep : DS.textSubtle,
                style: .compact
            ) {
                HStack(spacing: DS.s2) {
                    if note.isEncrypted {
                        SWStatusBadge("加密", systemImage: "lock.fill", style: .neutral)
                    }
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
                title: info.title,
                subtitle: "加密笔记",
                systemImage: "lock.fill",
                tint: DS.textSubtle,
                style: .compact
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

    private var renameSheetBinding: Binding<Bool> {
        Binding(
            get: { renamingNote != nil },
            set: { isPresented in
                if !isPresented {
                    finishRenaming()
                }
            }
        )
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

    private func beginRenaming(_ note: Note) {
        renamingNote = note
        renameTitle = vaultStore.displayTitle(for: note, emptyTitle: "")
        renameErrorMessage = nil
        isRenamingNote = false
    }

    private func finishRenaming() {
        renamingNote = nil
        renameTitle = ""
        renameErrorMessage = nil
        isRenamingNote = false
    }

    private func renameNote(_ note: Note) {
        guard let cleanedTitle = NoteTitleFormatter.sanitizedGeneratedTitle(renameTitle) else {
            renameErrorMessage = "请输入有效标题。"
            return
        }

        isRenamingNote = true
        renameErrorMessage = nil
        Task {
            do {
                try await vaultStore.renameNote(note, title: cleanedTitle)
                finishRenaming()
            } catch {
                renameErrorMessage = "重命名失败：\(error.localizedDescription)"
                isRenamingNote = false
            }
        }
    }

}

private struct AllNotesRenameSheet: View {
    @Binding var title: String
    let errorMessage: String?
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            SWPageHeader(
                title: "重命名笔记",
                subtitle: "标题只影响列表、菜单和文件名，不会改写正文。",
                systemImage: "pencil",
                tint: DS.primaryDeep
            )

            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(DS.body())
                .onSubmit(onSave)

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.caption())
                    .foregroundColor(DS.destructive)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "保存中..." : "保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(DS.s4)
        .frame(width: 420)
        .background(DS.bg)
    }
}

struct MacListSearchBar: View {
    let placeholder: String
    @Binding var text: String
    let onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DS.s2) {
            HStack(spacing: DS.s2) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DS.textSubtle)

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(DS.body())
                    .focused($isFocused)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(DS.textSubtle)
                    }
                    .buttonStyle(.plain)
                    .help("清空搜索")
                }
            }
            .padding(.horizontal, DS.s3)
            .padding(.vertical, DS.s2)
            .dsInputSurface(cornerRadius: DS.rMd)

            Button {
                onClose()
            } label: {
                Label("关闭搜索", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundColor(DS.textSecondary)
            .help("关闭搜索")
        }
        .padding(.horizontal, DS.s3)
        .padding(.vertical, DS.s2)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.line)
                .frame(height: 0.5)
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onExitCommand {
            onClose()
        }
    }
}

struct MacListSearchToolbarAppearance: NSViewRepresentable {
    let isActive: Bool

    func makeNSView(context: Context) -> MacListSearchToolbarAppearanceView {
        let view = MacListSearchToolbarAppearanceView()
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: MacListSearchToolbarAppearanceView, context: Context) {
        nsView.isActive = isActive
        nsView.apply()
    }

    static func dismantleNSView(_ nsView: MacListSearchToolbarAppearanceView, coordinator: ()) {
        nsView.isActive = false
        nsView.apply()
    }
}

final class MacListSearchToolbarAppearanceView: NSView {
    var isActive = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func apply() {
        guard let window else { return }
        window.titlebarAppearsTransparent = !isActive
        window.backgroundColor = isActive ? .white : .textBackgroundColor
        window.titlebarSeparatorStyle = isActive ? .line : .automatic
    }
}
