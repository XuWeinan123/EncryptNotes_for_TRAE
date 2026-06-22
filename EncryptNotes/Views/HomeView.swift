import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var purchaseStore = PurchaseStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showKeyImporter = false
    @State private var showSettings = false
    @State private var showNewNoteEditor = false
    @State private var selectedNote: Note?
    @State private var showKeyExportGuide = false
    @State private var exportedKeyURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            mainContent
                .animation(.easeInOut(duration: 0.3), value: vaultStore.state)

            if showPrivacyScreen {
                PrivacyScreenView()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            withAnimation(.easeInOut(duration: 0.2)) {
                handleScenePhaseChange(newPhase)
            }
        }
        .onChange(of: vaultStore.needsKeyExport) { _, needsExport in
            if needsExport {
                showKeyExportGuide = true
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
        }
        .sheet(isPresented: $showNewNoteEditor) {
            NoteEditorView(mode: .create) { body in
                try await vaultStore.createNote(body: body)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedNote) { note in
            NoteEditorView(mode: .edit(note)) { body in
                try await vaultStore.updateNote(note, body: body)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $showKeyImporter,
            allowedContentTypes: [UTType(filenameExtension: "bkwkey") ?? .json],
            allowsMultipleSelection: false
        ) { result in
            handleKeyImport(result)
        }
        .alert("保存密钥文件", isPresented: $showKeyExportGuide) {
            Button("立即保存") {
                exportKeyFile()
            }
            Button("稍后", role: .cancel) {
                vaultStore.needsKeyExport = false
            }
        } message: {
            Text("请保存你的密钥文件（.bkwkey）。没有密钥文件，换设备或重装应用后将无法解密笔记。")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedKeyURL {
                ShareSheet(items: [url])
            }
        }
        .alert("错误", isPresented: Binding(
            get: { vaultStore.lastError != nil },
            set: { if !$0 { vaultStore.lastError = nil } }
        )) {
            Button("确定") {
                vaultStore.lastError = nil
            }
        } message: {
            Text(vaultStore.lastError ?? "")
        }
        .task {
            await vaultStore.initialize()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch vaultStore.state {
        case .noVault:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.bg.ignoresSafeArea())
                .onAppear {
                    Task {
                        await vaultStore.initialize()
                    }
                }

        case .locked:
            LockedHomeView(showKeyImporter: $showKeyImporter)

        case .unlocking(let progress):
            UnlockingView(progress: progress)

        case .unlocked:
            UnlockedHomeView(
                showSettings: $showSettings,
                showNewNoteEditor: $showNewNoteEditor,
                selectedNote: $selectedNote
            )

        case .error(let message):
            ErrorView(message: message) {
                Task {
                    await vaultStore.initialize()
                }
            }
        }
    }

    @State private var showPrivacyScreen = false

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            showPrivacyScreen = false
        case .inactive, .background:
            // 仅显示隐私屏幕保护内容，不清空内存中的 key。
            // 用户手动点击「锁定 App」时才会真正 unload key。
            showPrivacyScreen = true
        @unknown default:
            break
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

    private func exportKeyFile() {
        do {
            exportedKeyURL = try vaultStore.exportKeyFile()
            vaultStore.needsKeyExport = false
            // 使用系统分享导出
            showShareSheet = true
        } catch {
            vaultStore.lastError = "导出密钥失败：\(error.localizedDescription)"
        }
    }
}

struct LockedHomeView: View {
    @Binding var showKeyImporter: Bool
    @StateObject private var vaultStore = VaultStore.shared
    @State private var showResetConfirmation = false
    @State private var showFinalResetConfirmation = false
    @State private var isResettingVault = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.s6) {
                VStack(spacing: DS.s2) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundColor(DS.textSecondary)
                        .padding(.bottom, DS.s2)

                    Text("这台设备还没有密钥")
                        .font(DS.title())
                        .foregroundColor(DS.textEmphasize)

                    Text("导入密钥文件后，笔记将在本机解密显示。")
                        .font(DS.body())
                        .foregroundColor(DS.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, DS.s8)
                .padding(.horizontal, DS.s6)

                Button {
                    showKeyImporter = true
                } label: {
                    Text("导入密钥文件")
                        .font(DS.body())
                        .foregroundColor(DS.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DS.primary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)

                Text("密钥文件只会在本机读取，不会上传。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)

                VStack(spacing: DS.s2) {
                    Text("忘记密钥？")
                        .font(DS.caption())
                        .foregroundColor(DS.textSecondary)

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("清空数据重来", systemImage: "trash")
                            .font(DS.body())
                            .foregroundColor(DS.destructive)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isResettingVault)

                    Text("会删除当前加密文件并生成新密钥，让 App 重新进入可用状态。")
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, DS.s2)
                .padding(.horizontal, DS.s6)

                lockedNoteList
            }
            .frame(maxWidth: DS.contentMax)
            .frame(maxWidth: .infinity)
            .padding(.bottom, DS.s6)
        }
        .background(DS.bg.ignoresSafeArea())
        .alert("清空加密文件？", isPresented: $showResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("继续", role: .destructive) {
                showFinalResetConfirmation = true
            }
        } message: {
            Text("如果你忘记了密钥，可以清空当前加密笔记文件并创建新的加密空间。此操作不可撤销。")
        }
        .alert("最终确认", isPresented: $showFinalResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空并重置", role: .destructive) {
                Task {
                    isResettingVault = true
                    defer { isResettingVault = false }

                    do {
                        try await vaultStore.resetVault()
                    } catch {
                        vaultStore.lastError = "重置失败：\(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("确定要永久删除所有加密笔记文件，并在这台设备上生成新的密钥吗？")
        }
    }

    @ViewBuilder
    private var lockedNoteList: some View {
        if case .locked(let files) = vaultStore.state, !files.isEmpty {
            VStack(alignment: .leading, spacing: DS.s3) {
                Text("已加密笔记")
                    .font(DS.title())
                    .foregroundColor(DS.textEmphasize)
                    .padding(.horizontal, DS.cardPadding)

                LazyVStack(spacing: DS.memoGap) {
                    ForEach(files) { file in
                        EncryptedCardView(info: file)
                    }
                }
                .padding(.horizontal, DS.cardPadding)
            }
        }
    }
}

struct UnlockingView: View {
    let progress: UnlockProgress

    var body: some View {
        VStack(spacing: DS.s6) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: DS.s2) {
                Text("正在本机解析密钥")
                    .font(DS.title())
                    .foregroundColor(DS.textEmphasize)

                Text("密钥文件不会上传。")
                    .font(DS.body())
                    .foregroundColor(DS.textSecondary)

                Text("正在解密笔记 \(progress.current) / \(progress.total)")
                    .font(DS.body())
                    .foregroundColor(DS.textSecondary)
            }

            Spacer()
        }
        .background(DS.bg.ignoresSafeArea())
    }
}

struct UnlockedHomeView: View {
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var purchaseStore = PurchaseStore.shared
    @Binding var showSettings: Bool
    @Binding var showNewNoteEditor: Bool
    @Binding var selectedNote: Note?

    @State private var noteToDelete: Note?
    @State private var showDeleteConfirmation = false
    @State private var showPaywall = false
    @State private var isFloatPressed = false
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                    .transition(.move(edge: .top).combined(with: .opacity))

                if vaultStore.filteredNotes.isEmpty {
                    emptyState
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    noteList
                        .transition(.opacity)
                }
            }

            // FloatButton: 唯一允许绿色光晕的元素
            Button {
                createNote()
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
                withAnimation(.easeInOut(duration: 0.1)) {
                    isFloatPressed = true
                }
            } onRelease: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFloatPressed = false
                }
            }
            .padding(.bottom, DS.s8)
        }
        .animation(.easeInOut(duration: 0.2), value: vaultStore.filteredNotes.count)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }


    private func createNote() {
        if !purchaseStore.isPro && vaultStore.notes.count >= 20 {
            showPaywall = true
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                showNewNoteEditor = true
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: DS.s2) {
                if isSearching {
                    // 搜索模式：搜索框 + 取消
                    HStack(spacing: DS.s2) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(DS.textSubtle)

                        TextField("搜索笔记", text: $vaultStore.searchText)
                            .font(DS.body())
                            .foregroundColor(DS.textBody)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)

                        if !vaultStore.searchText.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    vaultStore.searchText = ""
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.textSubtle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, DS.s3)
                    .background(DS.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                            .stroke(DS.line, lineWidth: 0.5)
                    )

                    Button("取消") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearching = false
                            vaultStore.searchText = ""
                            searchFocused = false
                        }
                    }
                    .font(DS.body())
                    .foregroundColor(DS.textSecondary)
                    .buttonStyle(.plain)
                } else {
                    // 正常模式：设置按钮 + 标题 + 搜索按钮
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(DS.textSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: DS.s1) {
                        Text("flomo")
                            .font(DS.page())
                            .foregroundColor(DS.textEmphasize)
                            .textCase(.lowercase)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearching = true
                        }
                        // 等动画启动后聚焦输入框
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            searchFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(DS.textSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.cardPadding)
            .frame(height: DS.navbarHeight)

            Divider()
                .overlay(DS.line)
        }
        .background(DS.surfaceCard)
    }

    private var searchBar: some View {
        HStack(spacing: DS.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DS.textSubtle)

            TextField("搜索笔记", text: $vaultStore.searchText)
                .font(DS.body())
                .foregroundColor(DS.textBody)
                .textFieldStyle(.plain)

            if !vaultStore.searchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vaultStore.searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.textSubtle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, DS.s3)
        .dsInputSurface()
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
            if !(isSearching && !vaultStore.searchText.isEmpty) {
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
                ForEach(vaultStore.filteredNotes) { note in
                    NoteCardView(note: note)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedNote = note
                            }
                        }
                        .contextMenu {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedNote = note
                                }
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                noteToDelete = note
                                showDeleteConfirmation = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, DS.cardPadding)
            .padding(.top, DS.s3)
            .padding(.bottom, 120)
            .frame(maxWidth: DS.contentMax)
            .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: vaultStore.filteredNotes)
        .alert("删除笔记", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let note = noteToDelete {
                    Task {
                        do {
                            try await vaultStore.deleteNote(note)
                        } catch {
                            vaultStore.lastError = "删除失败：\(error.localizedDescription)"
                        }
                    }
                }
                noteToDelete = nil
            }
        } message: {
            Text("确定要删除这条笔记吗？此操作不可撤销。")
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
                    .transition(.scale(scale: 0.5).combined(with: .opacity))

                Text("别看我")
                    .font(DS.page())
                    .foregroundColor(DS.textEmphasize)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .foregroundColor(DS.pro)

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
        .background(DS.bg.ignoresSafeArea())
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
