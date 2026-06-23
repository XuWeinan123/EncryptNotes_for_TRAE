import SwiftUI
import UniformTypeIdentifiers

enum NoteEditorMode {
    case create
    case edit(Note)
}

struct NoteEditorView: View {
    let mode: NoteEditorMode
    let onSave: (String, Bool) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vaultStore = VaultStore.shared
    private let settings = SettingsStore.shared

    @State private var noteBody: String = ""
    @State private var isEncrypted: Bool = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    @State private var showFirstKeyPrompt = false
    @State private var showKeyImporter = false

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s3) {
                    Text(isEditing ? "继续整理这条想法" : "快速记下一闪而过的想法")
                        .font(DS.caption())
                        .foregroundColor(DS.textSecondary)

                    TextEditor(text: $noteBody)
                        .font(DS.bodyLg())
                        .foregroundColor(DS.textBody)
                        .frame(minHeight: 320)
                        .scrollContentBackground(.hidden)
                        .padding(DS.cardPadding)
                        .dsInputSurface()

                    if isEditing {
                        // 编辑时不提供明文 ↔ 加密转换
                        HStack(spacing: DS.s1) {
                            Image(systemName: isEncrypted ? "lock.open.fill" : "doc.text")
                                .font(.system(size: 12))
                            Text(isEncrypted ? "加密笔记" : "明文笔记")
                                .font(DS.caption())
                        }
                        .foregroundColor(DS.textSubtle)
                    } else {
                        encryptedToggle
                    }

                    HStack(spacing: DS.s1) {
                        Text("用")
                        Text("#tag")
                            .foregroundColor(DS.primary)
                        Text("把想法连接起来")
                    }
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                }
                .padding(.horizontal, DS.cardPadding)
                .padding(.top, DS.s4)
                .padding(.bottom, DS.s8)
                .frame(maxWidth: DS.contentMax, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .dsCanvasBackground()
            .navigationTitle(isEditing ? "编辑笔记" : "新建笔记")
            .navigationBarTitleDisplayMode(.inline)
            .dsLiquidGlassToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .dsToolbarButtonStyle()
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") { saveNote() }
                            .dsToolbarButtonStyle()
                            .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { configureInitialState() }
            .alert("保存失败", isPresented: $showError) {
                Button("确定") {}
            } message: {
                Text(errorMessage)
            }
            .alert("创建密钥", isPresented: $showFirstKeyPrompt) {
                Button("创建密钥") {
                    Task {
                        do {
                            try await vaultStore.createKey()
                            isEncrypted = true
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
                Button("导入密钥文件") { showKeyImporter = true }
                Button("继续写明文笔记", role: .cancel) {}
            } message: {
                Text("创建密钥后，可以保存加密笔记。\n密钥文件只会在本机读取，不会上传。")
            }
            .fileImporter(
                isPresented: $showKeyImporter,
                allowedContentTypes: [UTType(filenameExtension: "bkwkey") ?? .json],
                allowsMultipleSelection: false
            ) { result in
                handleKeyImport(result)
            }
        }
    }

    private var encryptedToggle: some View {
        Toggle(isOn: Binding(
            get: { isEncrypted },
            set: { newValue in handleEncryptedToggle(newValue) }
        )) {
            HStack(spacing: DS.s2) {
                Image(systemName: isEncrypted ? "lock.fill" : "lock.open")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isEncrypted ? DS.primary : DS.textSecondary)
                Text("加密笔记")
                    .font(DS.bodyLg())
                    .foregroundColor(DS.textBody)
            }
        }
        .tint(DS.primary)
        .padding(.horizontal, DS.cardPadding)
        .padding(.vertical, DS.s2)
        .dsInputSurface()
    }

    private func configureInitialState() {
        if case .edit(let note) = mode {
            noteBody = note.body
            isEncrypted = note.isEncrypted
        } else {
            // 新建模式：根据持久化偏好与密钥状态决定默认值
            if vaultStore.isKeyLoaded {
                isEncrypted = settings.preferredNoteMode == .encrypted
            } else {
                isEncrypted = false
            }

            // 首次创建笔记 + 未加载密钥 + 未处理过首次提示
            if !settings.hasSeenFirstKeyPrompt && !vaultStore.isKeyLoaded {
                showFirstKeyPrompt = true
                settings.hasSeenFirstKeyPrompt = true
            }
        }
    }

    private func handleEncryptedToggle(_ newValue: Bool) {
        if newValue && !vaultStore.isKeyLoaded {
            // 未加载密钥时尝试打开加密开关：提示创建或导入密钥
            showFirstKeyPrompt = true
        } else {
            isEncrypted = newValue
            // 持久化用户选择
            settings.preferredNoteMode = newValue ? .encrypted : .plain
        }
    }

    private func handleKeyImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    _ = try await vaultStore.importKeyFile(from: url)
                    isEncrypted = true
                } catch {
                    errorMessage = "导入密钥失败：\(error.localizedDescription)"
                    showError = true
                }
            }
        case .failure:
            break
        }
    }

    private func saveNote() {
        guard !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "正文不能为空"
            showError = true
            return
        }

        isSaving = true
        Task {
            do {
                try await onSave(noteBody, isEncrypted)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSaving = false
        }
    }
}
