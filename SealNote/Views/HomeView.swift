import SwiftUI

struct HomeView: View {
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var appLockStore = AppLockStore.shared
    @StateObject private var syncStore = SyncStatusStore.shared
    @StateObject private var settings = SettingsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSettings = false
    @State private var showTrash = false
    @State private var showNewNoteEditor = false
    @State private var selectedNote: Note?
    @State private var noteToDelete: NoteListItem?
    @State private var showDeleteConfirmation = false
    @State private var noteToRename: Note?
    @State private var renameTitle = ""

    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []

    @State private var showBatchDeleteConfirmation = false
    @State private var batchResultMessage: String?
    @State private var showBatchResult = false

    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var settingsInitialRoute: SettingsRoute?
    @State private var showKeyIssueAlert = false
    @State private var isStorageRefreshInProgress = false

    private var filteredItems: [NoteListItem] {
        vaultStore.filteredNotes
    }

    private var selectedItems: [NoteListItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }

    private var isSystemBottomSearchAvailable: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            mainContent

            if appLockStore.showPrivacyScreen {
                PrivacyScreenView()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            appLockStore.handleScenePhaseChange(newPhase)
            refreshNotesWhenAppBecomesActive(newPhase)
        }
        .onChange(of: syncStore.isNetworkAvailable) { wasAvailable, isAvailable in
            if !wasAvailable && isAvailable {
                requestStorageRefresh()
            }
        }
        .onChange(of: vaultStore.allTags) { _, _ in
            clearInvalidTagSelectionIfNeeded()
        }
        .onChange(of: settings.excludeHexColorsFromTags) { _, _ in
            clearInvalidTagSelectionIfNeeded()
        }
        .sheet(isPresented: $showNewNoteEditor) {
            NoteEditorView(mode: .create) { body, isEncrypted in
                return try await vaultStore.createNote(body: body, isEncrypted: isEncrypted)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedNote) { note in
            NoteEditorView(mode: .edit(note)) { body, _ in
                try await vaultStore.updateNote(note, body: body)
                return vaultStore.readableNotes.first(where: { $0.id == note.id }) ?? note
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showSettings, onDismiss: {
            settingsInitialRoute = nil
        }) {
            SettingsView(isPresented: $showSettings, showTrash: $showTrash, initialRoute: settingsInitialRoute)
        }
        .sheet(isPresented: $showTrash) {
            TrashView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert("发现本机笔记", isPresented: Binding(
            get: { vaultStore.strandedLocalDataDetected },
            set: { if !$0 { vaultStore.dismissStrandedDataPrompt() } }
        )) {
            Button("合并到 iCloud") {
                Task { try? await vaultStore.mergeLocalDataIntoICloud() }
            }
            Button("暂不", role: .cancel) { vaultStore.dismissStrandedDataPrompt() }
        } message: {
            Text("检测到本机存储中还有笔记，可能是 iCloud 退出登录期间创建的。是否合并到当前 iCloud 保险库？重复的笔记会保留为「本机副本」。")
        }
        .alert("保存密钥", isPresented: $vaultStore.needsKeyExport) {
            Button("立即保存") { exportKeyFile() }
            Button("稍后", role: .cancel) { vaultStore.needsKeyExport = false }
        } message: {
            Text("密钥已经创建并加载。\n请导出并妥善保存密钥。丢失密钥后，加密笔记将无法恢复。")
        }
        .alert("删除笔记", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { noteToDelete = nil }
            Button("删除", role: .destructive) {
                if let item = noteToDelete {
                    Task {
                        do {
                            try await deleteSingleItem(item)
                        } catch {
                            vaultStore.lastError = "删除失败：\(error.localizedDescription)"
                        }
                    }
                }
                noteToDelete = nil
            }
        } message: {
            Text("删除后笔记将进入回收站，30 天后自动永久删除。")
        }
        .alert("批量删除", isPresented: $showBatchDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除\(selectedItems.count)条", role: .destructive) {
                Task { await performBatchDelete() }
            }
        } message: {
            Text("选中的笔记将移动至回收站，30 天后自动永久删除。")
        }
        .alert("重命名笔记", isPresented: Binding(
            get: { noteToRename != nil },
            set: { if !$0 { noteToRename = nil } }
        )) {
            TextField("标题", text: $renameTitle)
            Button("取消", role: .cancel) { noteToRename = nil }
            Button("保存") { renameSelectedNote() }
                .disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("标题只影响列表和文件名，不会改写正文。")
        }
        .alert("操作结果", isPresented: $showBatchResult) {
            Button("确定") { batchResultMessage = nil }
        } message: {
            Text(batchResultMessage ?? "")
        }
        .alert(keyIssueTitle, isPresented: $showKeyIssueAlert) {
            Button("打开密钥设置") { openKeySettings() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(keyIssueMessage)
        }
        .alert("错误", isPresented: Binding(
            get: { vaultStore.lastError != nil },
            set: { if !$0 { vaultStore.lastError = nil } }
        )) {
            Button("确定") { vaultStore.lastError = nil }
        } message: {
            Text(vaultStore.lastError ?? "")
        }
        .task {
            if case .loading = vaultStore.state {
                await vaultStore.initialize()
            }
        }
    }

    private func refreshNotesWhenAppBecomesActive(_ phase: ScenePhase) {
        guard phase == .active else { return }
        guard case .ready = vaultStore.state else { return }
        requestStorageRefresh()
    }

    private func requestStorageRefresh() {
        guard !isStorageRefreshInProgress else { return }
        guard case .ready = vaultStore.state else { return }
        isStorageRefreshInProgress = true
        Task {
            await vaultStore.refreshFromStorage()
            isStorageRefreshInProgress = false
        }
    }

    private func clearInvalidTagSelectionIfNeeded() {
        guard let selectedTag = vaultStore.selectedTag else { return }
        if !vaultStore.allTags.contains(where: { $0.tag == selectedTag }) {
            vaultStore.selectedTag = nil
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch vaultStore.state {
        case .loading:
            loadingSkeleton
                .dsCanvasBackground()

        case .error(let message):
            ErrorView(message: message) {
                Task { await vaultStore.initialize() }
            }

        case .ready:
            NavigationStack {
                ZStack {
                    DS.bg.ignoresSafeArea()
                    homeFeed
                }
                .navigationBarTitleDisplayMode(.inline)
                .dsLiquidGlassToolbar()
                .toolbar { homeToolbar }
                .searchable(
                    text: $vaultStore.searchText,
                    placement: .toolbar,
                    prompt: "搜索"
                )
                .autocorrectionDisabled()
                .safeAreaInset(edge: .bottom) {
                    if !isSelecting && !isSystemBottomSearchAvailable {
                        bottomSearchBar
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vaultStore.filteredNotes.count)
        }
    }

    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button {
                    if selectedItems.count == filteredItems.count {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(filteredItems.map { $0.id })
                    }
                } label: {
                    Text(selectedItems.count == filteredItems.count && !filteredItems.isEmpty ? "取消全选" : "全选")
                        .font(DS.body())
                }
                .disabled(filteredItems.isEmpty)
            } else {
                Button { openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("设置")
            }
        }

        ToolbarItem(placement: .principal) {
            if isSelecting {
                Text("已选 \(selectedItems.count) 条")
                    .font(DS.title())
                    .foregroundColor(DS.textEmphasize)
            } else {
                Text("Seal Note")
                    .font(DS.page())
                    .foregroundColor(DS.textEmphasize)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button {
                    exitSelectMode()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                }
            } else {
                Menu {
                    Button {
                        enterSelectMode()
                    } label: {
                        Label("多选笔记", systemImage: "checkmark.circle")
                    }
                    Button {
                        exportNotes()
                    } label: {
                        Label("导出笔记", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .regular))
                }
            }
        }

        if isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    performBatchCopy()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .disabled(selectedItems.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    showBatchDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selectedItems.isEmpty)
            }
        } else if #available(iOS 26.0, *) {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showNewNoteEditor = true
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建笔记")
            }
        }
    }

    private var loadingSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: DS.memoGap) {
                ForEach(0..<3, id: \.self) { _ in
                    SWShimmer {
                        VStack(alignment: .leading, spacing: DS.s3) {
                            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                .fill(DS.surfaceSunken)
                                .frame(width: 120, height: 14)
                            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                .fill(DS.surfaceSunken)
                                .frame(height: 20)
                            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                                .fill(DS.surfaceSunken)
                                .frame(width: 220, height: 14)
                        }
                        .padding(DS.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dsCardSurface(shadow: false)
                    }
                }
            }
            .padding(DS.cardPadding)
            .frame(maxWidth: DS.contentMax)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.s4) {
            Spacer()
            Image(systemName: vaultStore.lockedNoteCount > 0 && !vaultStore.isKeyLoaded ? "lock.doc" : "note.text")
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(DS.textSubtle)
            Text(emptyTitle)
                .font(DS.title())
                .foregroundColor(DS.textSecondary)
            Text(emptyMessage)
                .font(DS.body())
                .foregroundColor(DS.textSubtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.s6)
            Spacer()
        }
        .frame(minHeight: 360)
    }

    private var emptyTitle: String {
        if !vaultStore.searchText.isEmpty { return "未找到匹配笔记" }
        if let tag = vaultStore.selectedTag { return "没有 \(tag)" }
        if vaultStore.lockedNoteCount > 0 && !vaultStore.isKeyLoaded { return "有笔记待解锁" }
        return "暂无笔记"
    }

    private var emptyMessage: String {
        if !vaultStore.searchText.isEmpty { return "换个关键词试试。" }
        if let tag = vaultStore.selectedTag {
            return "没有包含 \(tag) 的可读笔记。"
        }
        if vaultStore.lockedNoteCount > 0 && !vaultStore.isKeyLoaded {
            return "前往密钥设置加载原密钥后，加密笔记会在本机解密显示。"
        }
        return "点击下方按钮创建第一条笔记。"
    }

    private var homeFeed: some View {
        ScrollView {
            VStack(spacing: DS.memoGap) {
                if case .failed(let message) = syncStore.status {
                    syncErrorBanner(message)
                }

                if vaultStore.storageRootMismatch {
                    syncErrorBanner("iCloud 暂时不可用，正在临时使用本机存储。iCloud 恢复后会自动切回，笔记不会丢失。")
                }

                tagChips

                if !filteredItems.isEmpty {
                    listSummary
                }

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: DS.memoGap) {
                        ForEach(filteredItems) { item in
                            noteRow(item)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.s3)
            .padding(.top, DS.s3)
            .padding(.bottom, isSelecting || isSystemBottomSearchAvailable ? DS.s4 : 88)
            .frame(maxWidth: DS.contentMax)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            guard !isStorageRefreshInProgress else { return }
            isStorageRefreshInProgress = true
            await vaultStore.refreshFromStorage()
            isStorageRefreshInProgress = false
        }
        .animation(.easeInOut(duration: 0.2), value: filteredItems.count)
        .animation(.easeInOut(duration: 0.2), value: isSelecting)
        .animation(.easeInOut(duration: 0.2), value: selectedIDs)
    }

    private var tagChips: some View {
        VStack(alignment: .leading, spacing: DS.s1) {
            HStack {
//                Text("标签")
//                    .font(DS.caption())
//                    .foregroundColor(DS.textSubtle)
//
//                Spacer()

                if let selectedTag = vaultStore.selectedTag {
                    Button {
                        vaultStore.selectedTag = nil
                    } label: {
                        Text("清除 \(selectedTag)")
                            .font(DS.caption())
                            .foregroundColor(DS.primaryDeep)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.s1)
            .frame(height: 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.s2) {
                    tagChip(title: "全部", count: vaultStore.totalNoteCount, isSelected: vaultStore.selectedTag == nil) {
                        vaultStore.selectedTag = nil
                    }

                    ForEach(vaultStore.allTags) { tagCount in
                        tagChip(title: tagCount.tag, count: tagCount.count, isSelected: vaultStore.selectedTag == tagCount.tag) {
                            vaultStore.selectedTag = vaultStore.selectedTag == tagCount.tag ? nil : tagCount.tag
                        }
                    }
                }
                .padding(.horizontal, DS.s3)
            }
            .padding(.horizontal, -DS.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagChip(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.s1) {
                Text(title)
                    .lineLimit(1)
                Text("\(count)")
                    .foregroundColor(isSelected ? DS.onPrimary.opacity(0.78) : DS.textSubtle)
            }
            .font(DS.caption())
            .foregroundColor(isSelected ? DS.onPrimary : DS.textBody)
            .padding(.horizontal, DS.s3)
            .frame(height: 30)
            .background(isSelected ? DS.primary : DS.surfaceCard)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : DS.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func syncErrorBanner(_ message: String) -> some View {
        HStack(spacing: DS.s3) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DS.destructive)
            VStack(alignment: .leading, spacing: 2) {
                Text("同步失败")
                    .font(DS.body())
                    .foregroundColor(DS.textEmphasize)
                Text(message)
                    .font(DS.caption())
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("重试") {
                Task { await vaultStore.refreshFromStorage() }
            }
            .font(DS.caption())
            .foregroundColor(DS.primaryDeep)
        }
        .padding(DS.s3)
        .dsCardSurface(cornerRadius: DS.rMd, shadow: false)
    }

    private var listSummary: some View {
        HStack(spacing: DS.s2) {
            Spacer(minLength: 0)

            Text("共 \(filteredItems.count) 条笔记")
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)

            let emptyCount = vaultStore.readableNotes.filter {
                !$0.isEncrypted && $0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !vaultStore.isCloudOnly($0)
            }.count
            if emptyCount > 0 {
                SWStatusBadge(
                    "\(emptyCount) 条空笔记",
                    systemImage: "exclamationmark.triangle",
                    style: .warning
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s2)
    }

    // Pre-iOS-26 bottom action bar. Search now lives entirely in the system
    // `.searchable` field, so this carries only the new-note button (iOS 26 uses a
    // dedicated bottomBar toolbar item instead).
    private var bottomSearchBar: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showNewNoteEditor = true
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("新建笔记")
            .dsSystemGlassButton()
        }
        .padding(.horizontal, DS.cardPadding)
        .padding(.vertical, DS.s2)
        .background(.clear)
    }

    @ViewBuilder
    private func noteRow(_ item: NoteListItem) -> some View {
        let isItemSelected = selectedIDs.contains(item.id)
        switch item {
        case .readable(let note):
            NoteCardView(
                note: note,
                displayTitle: vaultStore.displayTitle(for: note),
                excludesHexColorsFromTags: settings.excludeHexColorsFromTags,
                isCloudOnly: vaultStore.isCloudOnly(note),
                isSelected: isItemSelected,
                isSelecting: isSelecting,
                onTap: {
                    openReadableNote(note)
                },
                onRename: note.isEncrypted ? nil : {
                    beginRenaming(note)
                },
                onEdit: {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedNote = note }
                },
                onDelete: {
                    noteToDelete = item
                    showDeleteConfirmation = true
                },
                onToggleSelect: {
                    toggleSelection(for: item.id)
                }
            )

        case .locked(let info):
            EncryptedCardView(
                info: info,
                isKeyLoaded: vaultStore.isKeyLoaded,
                isSelected: isItemSelected,
                isSelecting: isSelecting,
                onOpen: {
                    openLockedNote(info)
                },
                onDelete: {
                    noteToDelete = item
                    showDeleteConfirmation = true
                },
                onToggleSelect: {
                    toggleSelection(for: item.id)
                }
            )
        }
    }

    private func openLockedNote(_ info: EncryptedNoteInfo) {
        guard vaultStore.isKeyLoaded else {
            showKeyIssueAlert = true
            return
        }

        Task { @MainActor in
            do {
                let note = try await vaultStore.openEncryptedNote(info)
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedNote = note
                }
            } catch {
                vaultStore.lastError = "解锁失败：\(error.localizedDescription)"
            }
        }
    }

    private func openReadableNote(_ note: Note) {
        guard vaultStore.isCloudOnly(note) else {
            withAnimation(.easeInOut(duration: 0.2)) { selectedNote = note }
            return
        }
        Task { @MainActor in
            do {
                let loaded = try await vaultStore.openCloudOnlyNote(note)
                withAnimation(.easeInOut(duration: 0.2)) { selectedNote = loaded }
            } catch {
                vaultStore.lastError = "下载笔记失败：\(error.localizedDescription)"
            }
        }
    }

    private func openSettings(route: SettingsRoute? = nil) {
        settingsInitialRoute = route
        showSettings = true
    }

    private func openKeySettings() {
        openSettings(route: .key)
    }

    private var keyIssueTitle: String {
        #if os(iOS)
        if case .invalid = vaultStore.iosKeyStatus {
            return "密钥失效"
        }
        #endif
        return "需要密钥"
    }

    private var keyIssueMessage: String {
        #if os(iOS)
        if case .invalid = vaultStore.iosKeyStatus {
            return "当前本机密钥不可用，需要前往设置页重新导入密钥或处理加密笔记。"
        }
        #endif
        return "需要先前往设置页创建或加载密钥。"
    }

    private func toggleSelection(for id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func beginRenaming(_ note: Note) {
        renameTitle = vaultStore.displayTitle(for: note, emptyTitle: "")
        noteToRename = note
    }

    private func renameSelectedNote() {
        guard let note = noteToRename else { return }
        let title = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        noteToRename = nil

        Task {
            do {
                try await vaultStore.renameNote(note, title: title)
            } catch {
                vaultStore.lastError = "重命名失败：\(error.localizedDescription)"
            }
        }
    }

    private func enterSelectMode() {
        isSelecting = true
        selectedIDs.removeAll()
    }

    private func exitSelectMode() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func deleteSingleItem(_ item: NoteListItem) async throws {
        switch item {
        case .readable(let note):
            try await vaultStore.deleteNote(note)
        case .locked(let info):
            try await vaultStore.deleteLockedNote(info)
        }
    }

    private func performBatchDelete() async {
        let items = selectedItems
        exitSelectMode()
        do {
            let result = try await vaultStore.batchDeleteNotes(items)
            if result.errors > 0 {
                batchResultMessage = "成功删除 \(result.deleted) 条，\(result.errors) 条删除失败。"
            } else {
                batchResultMessage = "已将 \(result.deleted) 条笔记移动至回收站。"
            }
            showBatchResult = true
        } catch {
            vaultStore.lastError = "批量删除失败：\(error.localizedDescription)"
        }
    }

    private func performBatchCopy() {
        #if os(iOS)
        let result = vaultStore.batchCopyNotesToClipboard(selectedItems)
        if result.skipped > 0 {
            batchResultMessage = "已复制 \(result.copied) 条明文笔记，跳过 \(result.skipped) 条加密笔记。"
        } else {
            batchResultMessage = "已复制 \(result.copied) 条笔记到剪贴板。"
        }
        showBatchResult = true
        exitSelectMode()
        #endif
    }

    private func exportNotes() {
        do {
            let result = try vaultStore.exportReadableNotesAsZip()
            exportedFileURL = result.url
            showShareSheet = true
            if result.skippedCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    batchResultMessage = "导出 \(result.exportedCount) 条明文笔记，跳过 \(result.skippedCount) 条加密笔记。"
                    showBatchResult = true
                }
            }
        } catch {
            vaultStore.lastError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func exportKeyFile() {
        do {
            exportedFileURL = try vaultStore.exportKeyFile()
            vaultStore.needsKeyExport = false
            showShareSheet = true
        } catch {
            vaultStore.lastError = "导出密钥失败：\(error.localizedDescription)"
        }
    }

}

struct PrivacyScreenView: View {
    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: DS.s4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundColor(DS.textSecondary)

                Text("Seal Note")
                    .font(DS.page())
                    .foregroundColor(DS.textEmphasize)
            }
        }
        .ignoresSafeArea()
    }
}

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: DS.s6) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(DS.destructive)

            Text("出错了")
                .font(DS.title())
                .foregroundColor(DS.textEmphasize)

            Text(message)
                .font(DS.body())
                .foregroundColor(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("重试", action: retryAction)
                .font(DS.body())
                .foregroundColor(DS.onPrimary)
                .padding(.horizontal, DS.s6)
                .padding(.vertical, 12)
                .background(DS.primary)
                .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))

            Spacer()
        }
        .dsCanvasBackground()
    }
}

private extension View {
    @ViewBuilder
    func dsSystemGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
