import Foundation
import SwiftUI
import AppKit

struct AllNotesView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var isSearchBarVisible = false
    @State private var actionErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isSearchBarVisible {
                MacListSearchBar(
                    placeholder: "搜索笔记…",
                    text: $searchText,
                    onClose: { hideSearchBar() }
                )
            }

            tagFilters

            if isLoading {
                SWEmptyState(
                    title: "正在加载笔记",
                    message: "笔记会在同步和索引读取完成后显示。",
                    systemImage: "tray.full"
                )
            } else if filteredNotes.isEmpty {
                SWEmptyState(
                    title: "没有匹配的笔记",
                    message: emptyStateMessage,
                    systemImage: "magnifyingglass"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        listSummary

                        ForEach(filteredNotes) { item in
                            noteRow(for: item)
                                .padding(.horizontal, DS.s3)
                                .padding(.vertical, DS.s1)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openNote(item)
                                }
                                .contextMenu {
                                    noteContextMenu(for: item)
                                }
                        }

                        Color.clear
                            .frame(height: DS.s3)
                            .accessibilityHidden(true)
                    }
                }
                .background(DS.bg)
            }
        }
        .safeAreaPadding(.top, DS.s2)
        .background(DS.bg)
        .dsLiquidGlassToolbar()
        .navigationTitle("全部笔记")
        .toolbar { allNotesToolbar }
        .background(MacListSearchToolbarAppearance(isActive: isSearchBarVisible))
        .onChange(of: listSnapshot.tagCounts) { _, tagCounts in
            guard let selectedTag else { return }
            if !tagCounts.contains(where: { $0.tag == selectedTag }) {
                self.selectedTag = nil
            }
        }
        .alert("操作失败", isPresented: actionErrorBinding) {
            Button("好") {
                actionErrorMessage = nil
            }
        } message: {
            Text(actionErrorMessage ?? "")
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
            .controlSize(.small)
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
            Spacer(minLength: 0)
            Text(noteCountText)
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
                .padding(.top, 8)
//            if listSnapshot.emptyReadableCount > 0 {
//                SWStatusBadge("\(listSnapshot.emptyReadableCount) 条空笔记", systemImage: "exclamationmark.triangle", style: .warning)
//            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s3)
        .padding(.top, DS.s3 - DS.s4)
        .padding(.bottom, DS.s2)
    }

    @ViewBuilder
    private var tagFilters: some View {
        let tagCounts = listSnapshot.tagCounts
        if !tagCounts.isEmpty || selectedTag != nil {
            ViewThatFits(in: .horizontal) {
                tagFilterRow(tagCounts: tagCounts, visibleCount: 8)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 7)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 6)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 5)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 4)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 3)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 2)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 1)
                tagFilterRow(tagCounts: tagCounts, visibleCount: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.s3)
            .padding(.bottom, DS.s2)
        }
    }

    private func tagFilterRow(tagCounts: [TagCount], visibleCount: Int) -> some View {
        let visibleTags = Array(tagCounts.prefix(visibleCount))
        let overflowTags = Array(tagCounts.dropFirst(visibleCount))

        return HStack(spacing: DS.s1) {
            SWFilterChip(title: "全部", isSelected: selectedTag == nil) {
                selectedTag = nil
            }
            ForEach(visibleTags) { tagCount in
                SWFilterChip(title: tagCount.tag, isSelected: selectedTag == tagCount.tag) {
                    selectedTag = tagCount.tag
                }
            }
            if let selectedTag, !visibleTags.contains(where: { $0.tag == selectedTag }) {
                SWFilterChip(title: selectedTag, isSelected: true) {}
            }
            if !overflowTags.isEmpty {
                SWFilterChipMenu(title: "…", items: overflowTags.map(\.tag)) { tag in
                    selectedTag = tag
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var filteredNotes: [NoteListItem] {
        listSnapshot.items
    }

    private var listSnapshot: MacNoteListSnapshot {
        MacNoteListSnapshotBuilder.make(
            readableNotes: vaultStore.readableNotes,
            lockedEncryptedNotes: vaultStore.lockedEncryptedNotes,
            query: searchText,
            selectedTag: selectedTag,
            excludingHexColorsFromTags: settings.excludeHexColorsFromTags,
            titleProvider: { vaultStore.displayTitle(for: $0, emptyTitle: "") }
        )
    }

    private var isLoading: Bool {
        if case .loading = vaultStore.state { return true }
        return false
    }

    private var noteCountText: String {
        guard !isLoading else { return "全部笔记加载中" }
        let encryptedCount = listSnapshot.encryptedCount
        if encryptedCount > 0 {
            return "共 \(listSnapshot.totalCount) 条笔记，加密笔记 \(encryptedCount) 条"
        }
        return "共 \(listSnapshot.totalCount) 条笔记"
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
            AllNotesListRow(
                title: vaultStore.displayTitle(for: note, emptyTitle: NoteTitleFormatter.emptyTitle),
                subtitle: note.isEncrypted ? "" : notePreview(for: note),
                isLocked: note.isEncrypted,
                timeText: timeString(from: note.createdAt),
                onOpen: { openNote(item) },
                menu: { noteContextMenu(for: item) }
            )

        case .locked(let info):
            AllNotesListRow(
                title: info.title,
                subtitle: "",
                isLocked: true,
                timeText: timeString(from: info.createdAt),
                onOpen: { openNote(item) },
                menu: { noteContextMenu(for: item) }
            )
        }
    }

    @ViewBuilder
    private func noteContextMenu(for item: NoteListItem) -> some View {
        switch item {
        case .readable(let note):
            Button("重命名...") { beginRenaming(note) }
                .disabled(note.isEncrypted)
        case .locked:
            Button("重命名...") {}
                .disabled(true)
        }
        Divider()
        switch item {
        case .readable(let note):
            if note.isEncrypted {
                Button("转为明文笔记") { convertToPlain(item) }
            } else {
                Button("转为加密笔记") { convertToEncrypted(note) }
            }
        case .locked:
            Button("转为明文笔记") { convertToPlain(item) }
        }
        Divider()
        Button("移到回收站", role: .destructive) {
            deleteNote(item)
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    actionErrorMessage = nil
                }
            }
        )
    }

    private func timeString(from date: Date) -> String {
        DateFormatters.formatNoteListRelativeTime(date)
    }

    private func notePreview(for note: Note) -> String {
        NoteTitleFormatter.displayTitle(from: note.body, emptyTitle: "")
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
            do {
                switch item {
                case .readable(let note):
                    try await vaultStore.deleteNote(note)
                case .locked(let info):
                    try await vaultStore.deleteLockedNote(info)
                }
            } catch {
                actionErrorMessage = error.localizedDescription
                SyncStatusStore.shared.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func convertToEncrypted(_ note: Note) {
        Task {
            SyncStatusStore.shared.setSyncing()
            do {
                _ = try await vaultStore.encryptNoteForEditing(note, body: note.body)
                SyncStatusStore.shared.setSaved()
            } catch {
                actionErrorMessage = "转为加密笔记失败：\(error.localizedDescription)"
                SyncStatusStore.shared.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func convertToPlain(_ item: NoteListItem) {
        Task {
            SyncStatusStore.shared.setSyncing()
            do {
                let encryptedNote: Note
                switch item {
                case .readable(let note):
                    encryptedNote = note
                case .locked(let info):
                    encryptedNote = try await vaultStore.openEncryptedNote(info)
                }
                _ = try await vaultStore.decryptNotePermanently(encryptedNote)
                SyncStatusStore.shared.setSaved()
            } catch {
                actionErrorMessage = "转为明文笔记失败：\(error.localizedDescription)"
                SyncStatusStore.shared.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func beginRenaming(_ note: Note) {
        let alert = NSAlert()
        alert.messageText = "重命名笔记"
        alert.informativeText = "标题只影响列表、菜单和文件名，不会改写正文。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let titleField = NSTextField(
            string: vaultStore.displayTitle(for: note, emptyTitle: "")
        )
        titleField.placeholderString = "标题"
        titleField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        titleField.selectText(nil)
        alert.accessoryView = titleField

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            guard let cleanedTitle = NoteTitleFormatter.sanitizedGeneratedTitle(titleField.stringValue) else {
                actionErrorMessage = "请输入有效标题。"
                return
            }

            Task {
                do {
                    try await vaultStore.renameNote(note, title: cleanedTitle)
                } catch {
                    actionErrorMessage = "重命名失败：\(error.localizedDescription)"
                }
            }
        }

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

}

struct AllNotesListRow<MenuContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let title: String
    let subtitle: String
    let isLocked: Bool
    let timeText: String
    let onOpen: () -> Void
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack(spacing: DS.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.textStrong)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.s3)

            if isHovering {
                HStack(spacing: DS.s1) {
                    Button(action: onOpen) {
                        Text("打开")
                            .foregroundStyle(DS.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.regular)
                    .help("打开")

                    Menu {
                        menu()
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(DS.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(DS.textSecondary)
                    .menuIndicator(.hidden)
                    .help("更多操作")
                }
            } else {
                HStack(spacing: DS.s2) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(DS.surfaceSunken)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(DS.line, lineWidth: 0.5))
                    }

                    Text(timeText)
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, DS.s3)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .background(isHovering ? DS.primaryContainer.opacity(0.42) : DS.surfaceCard.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .stroke(isHovering ? DS.primary.opacity(0.28) : DS.line, lineWidth: 0.5)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
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
//        .background(Color(nsColor: .windowBackgroundColor))
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
