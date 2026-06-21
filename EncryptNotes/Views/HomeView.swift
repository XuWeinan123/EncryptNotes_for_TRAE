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
            NoteEditorView(mode: .create) { title, body, tags in
                try await vaultStore.createNote(title: title, body: body, tags: tags)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedNote) { note in
            NoteEditorView(mode: .edit(note)) { title, body, tags in
                try await vaultStore.updateNote(note, title: title, body: body, tags: tags)
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
            showPrivacyScreen = true
            if case .unlocked = vaultStore.state {
                vaultStore.lock()
            }
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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("这台设备还没有密钥")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("导入密钥文件后，笔记将在本机解密显示。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showKeyImporter = true
            } label: {
                Text("导入密钥文件")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Text("密钥文件只会在本机读取，不会上传。")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            lockedNoteList
        }
    }

    @ViewBuilder
    private var lockedNoteList: some View {
        if case .locked(let files) = vaultStore.state, !files.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("已加密笔记")
                    .font(.headline)
                    .padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(files) { file in
                            EncryptedCardView(info: file)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct UnlockingView: View {
    let progress: UnlockProgress

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text("正在本机解析密钥")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("密钥文件不会上传。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("正在解密笔记 \(progress.current) / \(progress.total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct UnlockedHomeView: View {
    @StateObject private var vaultStore = VaultStore.shared
    @Binding var showSettings: Bool
    @Binding var showNewNoteEditor: Bool
    @Binding var selectedNote: Note?

    @State private var noteToDelete: Note?
    @State private var showDeleteConfirmation = false
    @State private var showPaywall = false

    var body: some View {
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

            BottomComposerView(
                onCreateNote: {
                    if !purchaseStore.isPro && vaultStore.notes.count >= 20 {
                        showPaywall = true
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showNewNoteEditor = true
                        }
                    }
                },
                isDisabled: false
            )
            .transition(.move(edge: .bottom))
        }
        .animation(.easeInOut(duration: 0.3), value: vaultStore.filteredNotes.count)
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

    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("已解锁")
                        .font(.headline)
                    Text("当前笔记已在本机解密显示。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            if !vaultStore.allTags.isEmpty {
                tagFilter
            }

            searchBar
        }
    }

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vaultStore.allTags, id: \.self) { tag in
                    TagChip(
                        tag: tag,
                        isSelected: vaultStore.selectedTag == tag
                    ) {
                        if vaultStore.selectedTag == tag {
                            vaultStore.selectedTag = nil
                        } else {
                            vaultStore.selectedTag = tag
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索笔记", text: $vaultStore.searchText)
                .textFieldStyle(.plain)

            if !vaultStore.searchText.isEmpty {
                Button {
                    vaultStore.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("暂无笔记")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("点击下方按钮创建第一条笔记")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vaultStore.filteredNotes) { note in
                    NoteCardView(note: note)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedNote = note
                            }
                        }
                        .contextMenu {
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
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
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .animation(.easeInOut(duration: 0.25), value: vaultStore.filteredNotes)
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

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

struct PrivacyScreenView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))

                Text("别看我")
                    .font(.title)
                    .fontWeight(.bold)
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
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("出错了")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("重试", action: retryAction)
                .buttonStyle(.borderedProminent)

            Spacer()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
