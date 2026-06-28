import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var appLockStore = AppLockStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSidebar = false
    @State private var showSettings = false
    @State private var showTrash = false
    @State private var showNewNoteEditor = false
    @State private var selectedNote: Note?
    @State private var noteToDelete: NoteListItem?
    @State private var showDeleteConfirmation = false
    @FocusState private var searchFocused: Bool

    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []

    @State private var showBatchDeleteConfirmation = false
    @State private var batchResultMessage: String?
    @State private var showBatchResult = false

    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var showKeyImporter = false

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
        }
        .sheet(isPresented: $showNewNoteEditor) {
            NoteEditorView(mode: .create) { body, isEncrypted in
                try await vaultStore.createNote(body: body, isEncrypted: isEncrypted)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedNote) { note in
            NoteEditorView(mode: .edit(note)) { body, _ in
                try await vaultStore.updateNote(note, body: body)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings, showTrash: $showTrash)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        .fileImporter(
            isPresented: $showKeyImporter,
            allowedContentTypes: [UTType(filenameExtension: "bkwkey") ?? .json],
            allowsMultipleSelection: false
        ) { result in
            handleKeyImport(result)
        }
        .alert("保存密钥文件", isPresented: $vaultStore.needsKeyExport) {
            Button("立即保存") { exportKeyFile() }
            Button("稍后", role: .cancel) { vaultStore.needsKeyExport = false }
        } message: {
            Text("密钥已经创建并加载。\n请导出并妥善保存密钥文件。丢失密钥后，加密笔记将无法恢复。")
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
        .alert("操作结果", isPresented: $showBatchResult) {
            Button("确定") { batchResultMessage = nil }
        } message: {
            Text(batchResultMessage ?? "")
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
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    NavigationStack {
                        ZStack {
                            DS.bg.ignoresSafeArea()
                            homeFeed
                        }
                        .navigationBarTitleDisplayMode(.inline)
                        .dsLiquidGlassToolbar()
                        .toolbar {
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
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            showSidebar.toggle()
                                        }
                                    }
                                    label: {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                }
                            }
                            ToolbarItem(placement: .principal) {
                                if isSelecting {
                                    Text("\(selectedItems.count) selected")
                                        .font(DS.title())
                                        .foregroundColor(DS.textEmphasize)
                                } else {
                                    Text("别看我")
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

                    if showSidebar {
                        sidebarOverlay(width: geo.size.width)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vaultStore.filteredNotes.count)
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

    private func sidebarOverlay(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Color.black.opacity(0.34))
            }
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) { showSidebar = false }
            }
            .transition(.opacity)

            SidebarView(
                isPresented: $showSidebar,
                showSettings: $showSettings,
                showTrash: $showTrash
            )
            .frame(width: DS.sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(DS.surfaceRaised)
            .shadow(color: DS.popoverShadow.color,
                    radius: DS.popoverShadow.radius,
                    x: DS.popoverShadow.x,
                    y: DS.popoverShadow.y)
            .transition(.move(edge: .leading).combined(with: .opacity))
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
            return "导入密钥文件后，加密笔记会在本机解密显示。"
        }
        return "点击下方按钮创建第一条笔记。"
    }

    private var keyStatusBanner: some View {
        HStack(spacing: DS.s3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DS.pro)

            VStack(alignment: .leading, spacing: 2) {
                Text("密钥未加载")
                    .font(DS.body())
                    .foregroundColor(DS.textEmphasize)
                Text("\(vaultStore.lockedNoteCount) 条加密笔记")
                    .font(DS.caption())
                    .foregroundColor(DS.textSecondary)
            }

            Spacer()

            Button {
                showKeyImporter = true
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(DS.primaryDeep)
            .accessibilityLabel("导入密钥文件")
        }
        .padding(DS.s3)
        .dsCardSurface(cornerRadius: DS.rMd, shadow: false)
    }

    private var homeFeed: some View {
        ScrollView {
            VStack(spacing: DS.memoGap) {
                if !vaultStore.isKeyLoaded && vaultStore.lockedNoteCount > 0 {
                    keyStatusBanner
                }

                if vaultStore.selectedTag != nil {
                    HStack {
                        Button {
                            vaultStore.selectedTag = nil
                        } label: {
                            HStack(spacing: DS.s1) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(vaultStore.selectedTag ?? "")
                            }
                            .font(DS.caption())
                            .foregroundColor(DS.primaryDeep)
                            .padding(.horizontal, DS.s2)
                            .padding(.vertical, DS.s1)
                            .background(DS.primaryContainer)
                            .clipShape(Capsule())
                        }
                        Spacer()
                    }
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
            .padding(.bottom, DS.s4)
            .frame(maxWidth: DS.contentMax)
            .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: filteredItems.count)
        .animation(.easeInOut(duration: 0.2), value: isSelecting)
        .animation(.easeInOut(duration: 0.2), value: selectedIDs)
        .onAppear {
            vaultStore.searchText = ""
        }
    }

    private var bottomSearchBar: some View {
        HStack(spacing: DS.s2) {
            HStack(spacing: DS.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)

                TextField("搜索", text: $vaultStore.searchText)
                    .font(DS.body())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .submitLabel(.search)

                Button {
                    searchFocused = true
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .regular))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
                .accessibilityLabel("语音搜索")
            }
            .padding(.horizontal, DS.s3)
            .frame(height: 44)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 6)

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
                isSelected: isItemSelected,
                isSelecting: isSelecting,
                onTap: {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedNote = note }
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
                isSelected: isItemSelected,
                isSelecting: isSelecting,
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

    private func toggleSelection(for id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
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

    private func handleKeyImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    _ = try await vaultStore.importKeyFile(from: url)
                } catch {
                    vaultStore.lastError = "导入密钥失败：\(error.localizedDescription)"
                }
            }
        case .failure:
            break
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

                Text("别看我")
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
