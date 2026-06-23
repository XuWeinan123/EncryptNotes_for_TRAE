import SwiftUI

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
    @State private var isFloatPressed = false
    @State private var isSearching = false
    @State private var exportedKeyURL: URL?
    @State private var showShareSheet = false
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .dsCanvasBackground()

        case .error(let message):
            ErrorView(message: message) {
                Task { await vaultStore.initialize() }
            }

        case .ready:
            NavigationStack {
                ZStack(alignment: .bottom) {
                    DS.bg.ignoresSafeArea()

                    if vaultStore.filteredNotes.isEmpty {
                        emptyState
                    } else {
                        noteList
                    }

                    if isSearching {
                        searchOverlay
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }

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
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.textSubtle)

            TextField("搜索笔记", text: $vaultStore.searchText)
                .font(DS.body())
                .textFieldStyle(.plain)
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
        .padding(.vertical, 10)
        .padding(.horizontal, DS.s3)
        .dsInputSurface(cornerRadius: 18)
        .padding(.horizontal, DS.cardPadding)
        .padding(.top, DS.s2)
    }

    private var floatingButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showNewNoteEditor = true }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(DS.onPrimary)
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

    private var emptyState: some View {
        VStack(spacing: DS.s4) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(DS.textSubtle)
            Text(isSearching && !vaultStore.searchText.isEmpty ? "未找到匹配笔记" : "暂无笔记")
                .font(DS.title())
                .foregroundColor(DS.textSecondary)
            if let tag = vaultStore.selectedTag {
                Text("没有包含 \(tag) 的可读笔记")
                    .font(DS.body())
                    .foregroundColor(DS.textSubtle)
            } else if !(isSearching && !vaultStore.searchText.isEmpty) {
                Text("点击下方按钮创建第一条笔记")
                    .font(DS.body())
                    .foregroundColor(DS.textSubtle)
            }
            Spacer()
        }
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: DS.memoGap) {
                ForEach(vaultStore.filteredNotes) { item in
                    noteRow(item)
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
