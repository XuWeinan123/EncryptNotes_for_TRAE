import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

enum NoteEditorMode {
    case create
    case edit(Note)
}

struct NoteEditorView: View {
    let mode: NoteEditorMode
    let initialBody: String
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

    init(
        mode: NoteEditorMode,
        initialBody: String = "",
        onSave: @escaping (String, Bool) async throws -> Void
    ) {
        self.mode = mode
        self.initialBody = initialBody
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s3) {
                    Text(isEditing ? "继续整理这条想法" : "快速记下一闪而过的想法")
                        .font(DS.caption())
                        .foregroundColor(DS.textSecondary)

                    #if os(iOS)
                    NoteTextView(text: $noteBody, placeholder: "随便写点什么吧")
                        .frame(minHeight: 320)
                        .dsInputSurface()
                    #else
                    ZStack(alignment: .topLeading) {
                        if noteBody.isEmpty {
                            Text("随便写点什么吧")
                                .font(DS.bodyLg())
                                .foregroundColor(DS.textSubtle)
                                .padding(DS.cardPadding)
                        }

                        TextEditor(text: $noteBody)
                            .font(DS.bodyLg())
                            .foregroundColor(DS.textBody)
                            .scrollContentBackground(.hidden)
                            .padding(DS.cardPadding)
                    }
                    .frame(minHeight: 320)
                    .dsInputSurface()
                    #endif

                    if isEditing {
                        SWStatusBadge(
                            isEncrypted ? "加密笔记" : "明文笔记",
                            systemImage: isEncrypted ? "lock.open.fill" : "doc.text",
                            style: isEncrypted ? .success : .neutral
                        )
                    } else {
                        modePicker
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

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack(spacing: DS.s2) {
                SWTabButton(
                    title: "明文",
                    systemImage: "doc.text",
                    isSelected: !isEncrypted
                ) {
                    handleEncryptedToggle(false)
                }

                SWTabButton(
                    title: "加密",
                    systemImage: vaultStore.isKeyLoaded ? "lock.fill" : "lock.slash",
                    isSelected: isEncrypted,
                    isEnabled: vaultStore.isKeyLoaded
                ) {
                    handleEncryptedToggle(true)
                }
            }

            if !vaultStore.isKeyLoaded {
                Text("导入密钥文件后，可保存加密笔记。密钥文件只会在本机读取，不会上传。")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
        }
        .padding(.horizontal, DS.cardPadding)
        .padding(.vertical, DS.s3)
        .dsInputSurface()
    }

    private func configureInitialState() {
        if case .edit(let note) = mode {
            noteBody = note.body
            isEncrypted = note.isEncrypted
        } else {
            noteBody = initialBody
            if vaultStore.isKeyLoaded {
                isEncrypted = settings.preferredNoteMode == .encrypted
            } else {
                isEncrypted = false
            }

            if !settings.hasSeenFirstKeyPrompt && !vaultStore.isKeyLoaded {
                showFirstKeyPrompt = true
                settings.hasSeenFirstKeyPrompt = true
            }
        }
    }

    private func handleEncryptedToggle(_ newValue: Bool) {
        if newValue && !vaultStore.isKeyLoaded {
            showFirstKeyPrompt = true
        } else {
            isEncrypted = newValue
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

#if os(iOS)
private class PlaceholderTextView: UITextView {
    var placeholder: String = "" {
        didSet { placeholderLabel.text = placeholder }
    }
    private let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isEditable = true
        isSelectable = true
        backgroundColor = .clear
        isScrollEnabled = true
        alwaysBounceVertical = true
        autocapitalizationType = .sentences
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no
        autocorrectionType = .default

        let font = UIFont.systemFont(ofSize: 15)
        self.font = font

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.25
        typingAttributes = [
            .font: font,
            .foregroundColor: UIColor(DS.textBody),
            .paragraphStyle: paragraphStyle
        ]

        textContainerInset = UIEdgeInsets(top: DS.cardPadding, left: DS.cardPadding - 5, bottom: DS.cardPadding, right: DS.cardPadding - 5)

        placeholderLabel.textColor = UIColor(DS.textSubtle)
        placeholderLabel.font = font
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: DS.cardPadding),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.cardPadding),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.cardPadding)
        ])

        updatePlaceholderVisibility()
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }
}

private struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> PlaceholderTextView {
        let textView = PlaceholderTextView()
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.text = text
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        uiView.placeholder = placeholder
        if uiView.text != text && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            uiView.text = text

            let font = UIFont.systemFont(ofSize: 15)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.25
            uiView.typingAttributes = [
                .font: font,
                .foregroundColor: UIColor(DS.textBody),
                .paragraphStyle: paragraphStyle
            ]

            context.coordinator.isUpdating = false
        }
        uiView.updatePlaceholderVisibility()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        weak var textView: PlaceholderTextView?
        var isUpdating = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true
            text.wrappedValue = textView.text
            (textView as? PlaceholderTextView)?.updatePlaceholderVisibility()
            isUpdating = false
        }
    }
}
#endif
