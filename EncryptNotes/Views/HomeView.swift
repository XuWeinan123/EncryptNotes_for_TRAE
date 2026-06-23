import SwiftUI
import UniformTypeIdentifiers

/// 统一首页：始终显示笔记列表，密钥状态只影响加密笔记的显示方式。
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
    @State private var isSearching = false
    @State private var isFloatPressed = false
    @State private var exportedKeyURL: URL?
    @State private var showShareSheet = false
    @State private var showKeyImporter = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            mainContent

            if appLockStore.showPrivacyScreen {
                PrivacyScreenView()
                    .transition(.opacity)
            }

            if showSidebar {
                sidebarOverlay
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
            if let url = exportedKeyURL {
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
                            switch item {
                            case .readable(let note):
                                try await vaultStore.deleteNote(note)
                            case .locked(let info):
                                try await vaultStore.deleteLockedNote(info)
                            }
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
            NavigationStack {
                ZStack {
                    DS.bg.ignoresSafeArea()
                    homeFeed
                    floatingButton
                }
                .navigationBarTitleDisplayMode(.inline)
                .dsLiquidGlassToolbar()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showSidebar.toggle()
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .disabled(isSearching)
                    }
                    ToolbarItem(placement: .principal) {
                        Text("别看我")
                            .font(DS.page())
                            .foregroundColor(DS.textEmphasize)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { isSearching = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                searchFocused = true
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .disabled(showSidebar)
                    }
                }
                .onChange(of: isSearching) { _, newValue in
                    if !newValue { vaultStore.searchText = "" }
                }
                .onChange(of: vaultStore.selectedTag) { _, _ in
                    withAnimation(.easeInOut(duration: 0.2)) {}
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
                        .dsCardSurface()
                    }
                }
            }
            .padding(DS.cardPadding)
            .frame(maxWidth: DS.contentMax)
            .frame(maxWidth: .infinity)
        }
    }

    private var sidebarOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) { showSidebar = false }
                }
                .transition(.opacity)

            SidebarView(isPresented: $showSidebar, showSettings: $showSettings, showTrash: $showTrash)
                .frame(width: DS.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(DS.bg)
                .shadow(color: DS.popoverShadow.color,
                        radius: DS.popoverShadow.radius,
                        x: DS.popoverShadow.x,
                        y: DS.popoverShadow.y)
                .transition(.move(edge: .leading))
        }
    }

    private var searchOverlay: some View {
        HStack(spacing: DS.s2) {
            SWSearchBar(text: $vaultStore.searchText, placeholder: "搜索笔记")
                .focused($searchFocused)

            Button("取消") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false
                    vaultStore.searchText = ""
                    searchFocused = false
                }
            }
            .font(DS.body())
            .foregroundColor(DS.textSecondary)
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
            if !vaultStore.isKeyLoaded && vaultStore.lockedNoteCount > 0 {
                Button("导入密钥文件") {
                    showKeyImporter = true
                }
                .font(DS.body())
                .foregroundColor(DS.primaryDeep)
                .padding(.horizontal, DS.s4)
                .padding(.vertical, DS.s2)
                .background(DS.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
            }
            Spacer()
        }
    }

    private var emptyTitle: String {
        if isSearching && !vaultStore.searchText.isEmpty { return "未找到匹配笔记" }
        if let tag = vaultStore.selectedTag { return "没有 \(tag)" }
        if vaultStore.lockedNoteCount > 0 && !vaultStore.isKeyLoaded { return "有笔记待解锁" }
        return "暂无笔记"
    }

    private var emptyMessage: String {
        if isSearching && !vaultStore.searchText.isEmpty { return "换个关键词试试。" }
        if let tag = vaultStore.selectedTag {
            return "没有包含 \(tag) 的可读笔记。"
        }
        if vaultStore.lockedNoteCount > 0 && !vaultStore.isKeyLoaded {
            return "导入密钥文件后，加密笔记会在本机解密显示。"
        }
        return "点击右下角按钮创建第一条笔记。"
    }

    private var floatingButton: some View {
        VStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showNewNoteEditor = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(DS.onFloat)
                    .frame(width: 56, height: 56)
                    .background(DS.primary)
                    .clipShape(Circle())
                    .shadow(color: DS.floatShadow.color,
                            radius: DS.floatShadow.radius,
                            x: DS.floatShadow.x,
                            y: DS.floatShadow.y)
                    .scaleEffect(isFloatPressed ? 0.92 : 1.0)
            }
            .buttonStyle(.plain)
            .pressEvents {
                withAnimation(.easeInOut(duration: 0.1)) { isFloatPressed = true }
            } onRelease: {
                withAnimation(.easeInOut(duration: 0.15)) { isFloatPressed = false }
            }
            .padding(.bottom, DS.s8)
        }
    }

    private var homeFeed: some View {
        ScrollView {
            VStack(spacing: DS.memoGap) {
                if isSearching {
                    searchOverlay
                }

                privacyStatusCard

                if vaultStore.filteredNotes.isEmpty {
                    emptyState
                        .frame(minHeight: 360)
                } else {
                    LazyVStack(spacing: DS.memoGap) {
                        ForEach(vaultStore.filteredNotes) { item in
                            noteRow(item)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.cardPadding)
            .padding(.top, DS.s3)
            .padding(.bottom, 120)
            .frame(maxWidth: DS.contentMax)
            .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: vaultStore.filteredNotes)
    }

    private var privacyStatusCard: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.s1) {
                    Text(vaultStore.isKeyLoaded ? "密钥已加载" : "密钥未加载")
                        .font(DS.title())
                        .foregroundColor(DS.textEmphasize)
                    Text(vaultStore.isKeyLoaded ? "加密笔记只在本机解密显示。" : "加密笔记会保持乱码，直到导入密钥文件。")
                        .font(DS.caption())
                        .foregroundColor(DS.textSecondary)
                }
                Spacer()
                SWStatusBadge(
                    vaultStore.isKeyLoaded ? "可查看" : "待导入",
                    systemImage: vaultStore.isKeyLoaded ? "lock.open.fill" : "lock.fill",
                    style: vaultStore.isKeyLoaded ? .success : .warning
                )
            }

            HStack(spacing: DS.s2) {
                SWStatusBadge("可读 \(vaultStore.readableNoteCount)", systemImage: "doc.text", style: .neutral)
                SWStatusBadge("加密 \(vaultStore.encryptedNoteCount)", systemImage: "lock.fill", style: .neutral)
                if vaultStore.lockedNoteCount > 0 {
                    SWStatusBadge("待解锁 \(vaultStore.lockedNoteCount)", systemImage: "exclamationmark.lock", style: .warning)
                }
            }

            if !vaultStore.isKeyLoaded {
                HStack(spacing: DS.s2) {
                    Button("导入密钥文件") {
                        showKeyImporter = true
                    }
                    .font(DS.body())
                    .foregroundColor(DS.onPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.s2)
                    .background(DS.primary)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))

                    Button("创建密钥") {
                        Task {
                            do { try await vaultStore.createKey() }
                            catch { vaultStore.lastError = "创建密钥失败：\(error.localizedDescription)" }
                        }
                    }
                    .font(DS.body())
                    .foregroundColor(DS.textBody)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.s2)
                    .background(DS.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
                }
            }
        }
        .padding(DS.cardPadding)
        .dsCardSurface(cornerRadius: DS.rMd)
    }

    @ViewBuilder
    private func noteRow(_ item: NoteListItem) -> some View {
        switch item {
        case .readable(let note):
            NoteCardView(note: note)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedNote = note }
                }
                .contextMenu {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedNote = note }
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        noteToDelete = item
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }

        case .locked(let info):
            EncryptedCardView(info: info)
                .contextMenu {
                    Button(role: .destructive) {
                        noteToDelete = item
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
        }
    }

    private func exportKeyFile() {
        do {
            exportedKeyURL = try vaultStore.exportKeyFile()
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
