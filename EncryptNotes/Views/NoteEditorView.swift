import SwiftUI
import UniformTypeIdentifiers
import MarkdownView

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
    @State private var isPreviewing = false
    @State private var showDiscardConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var editorSelection = NSRange(location: 0, length: 0)

    @State private var showFirstKeyPrompt = false
    @State private var showKeyImporter = false

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingNote: Note? {
        if case .edit(let note) = mode { return note }
        return nil
    }

    private var initialEffectiveBody: String {
        if case .edit(let note) = mode { return note.body }
        return initialBody
    }

    private var hasUnsavedChanges: Bool {
        noteBody != initialEffectiveBody || (editingNote == nil && isEncrypted != (vaultStore.isKeyLoaded && settings.preferredNoteMode == .encrypted))
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
            VStack(spacing: 0) {
                editorBody

                #if os(iOS)
                if !isPreviewing {
                    markdownFormatBar
                }
                #endif
            }
            .dsCanvasBackground()
            .navigationBarTitleDisplayMode(.inline)
            .dsLiquidGlassToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { closeEditor() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(isSaving)
                    .dsGlassToolbarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: DS.s2) {
                        #if os(iOS)
                        Button { togglePreview() } label: {
                            Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isPreviewing ? DS.primaryDeep : DS.textSecondary)
                        }
                        .disabled(isSaving)
                        .accessibilityLabel(isPreviewing ? "返回编辑" : "Markdown 预览")
                        .dsGlassToolbarButton()
                        #endif

                        Menu {
                            Button {
                                copyNoteText()
                            } label: {
                                Label("复制正文", systemImage: "doc.on.doc")
                            }
                            .disabled(noteBody.isEmpty)

                            if let note = editingNote {
                                Divider()
                                if note.isEncrypted {
                                    Button {
                                        convertCurrentNote(to: .plain)
                                    } label: {
                                        Label("转为明文笔记", systemImage: "lock.open")
                                    }
                                    .disabled(isSaving)
                                } else {
                                    Button {
                                        convertCurrentNote(to: .encrypted)
                                    } label: {
                                        Label("转为加密笔记", systemImage: "lock")
                                    }
                                    .disabled(isSaving)
                                }

                                Divider()
                                Button(role: .destructive) {
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("移到回收站", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .dsGlassToolbarButton()

                        if !isEditing {
                            Button {
                                toggleEncryption()
                            } label: {
                                Image(systemName: isEncrypted ? "lock.fill" : "lock.open")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(isEncrypted ? DS.primaryDeep : DS.textSecondary)
                            }
                            .disabled(isSaving)
                            .dsGlassToolbarButton()
                        }

                        if isSaving {
                            ProgressView()
                        } else {
                            Button { saveNote() } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .dsGlassToolbarButton(isProminent: true)
                        }
                    }
                }
            }
            .onAppear { configureInitialState() }
            .alert("放弃更改？", isPresented: $showDiscardConfirmation) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃", role: .destructive) { dismiss() }
            } message: {
                Text("当前笔记有未保存的修改，关闭后不会保留。")
            }
            .alert("删除这条笔记？", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    deleteCurrentNote()
                }
            } message: {
                Text("笔记将移到回收站，可以恢复。")
            }
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
                Button("导入密钥") { showKeyImporter = true }
                Button("继续写明文笔记", role: .cancel) {}
            } message: {
                Text("创建密钥后，可以保存加密笔记。\n密钥只会在本机读取，不会上传。")
            }
            .fileImporter(
                isPresented: $showKeyImporter,
                allowedContentTypes: [UTType(filenameExtension: "snkey") ?? .json],
                allowsMultipleSelection: false
            ) { result in
                handleKeyImport(result)
            }
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isPreviewing {
                    markdownPreview
                } else {
                    #if os(iOS)
                    NoteTextView(text: $noteBody, selectedRange: $editorSelection, placeholder: "随便写点什么吧")
                        .frame(minHeight: 360)
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
                    .frame(minHeight: 360)
                    #endif
                }
            }
            .padding(DS.cardPadding)
            .frame(maxWidth: DS.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var markdownPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("随便写点什么吧")
                    .font(DS.bodyLg())
                    .foregroundColor(DS.textSubtle)
                    .padding(DS.cardPadding)
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
                    .dsInputSurface(cornerRadius: DS.rMd)
            } else {
                MarkdownView(noteBody)
                    .font(.system(size: 15), for: .body)
                    .font(.system(size: 13, design: .monospaced), for: .codeBlock)
                    .markdownComponentSpacing(10)
                    .markdownMathRenderingEnabled()
                    .foregroundStyle(DS.textBody)
                    .padding(DS.cardPadding)
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
                    .dsInputSurface(cornerRadius: DS.rMd)
            }
        }
    }

    #if os(iOS)
    private var markdownFormatBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.s2) {
                formatButton("bold", title: "粗体", command: .bold)
                formatButton("italic", title: "斜体", command: .italic)
                formatButton("curlybraces", title: "代码", command: .inlineCode)
                formatButton("link", title: "链接", command: .link)
                formatButton("strikethrough", title: "删除线", command: .strike)
                formatButton("chevron.left.forwardslash.chevron.right", title: "注释", command: .htmlComment)
            }
            .padding(.horizontal, DS.cardPadding)
            .padding(.vertical, DS.s2)
        }
        .background(.regularMaterial)
    }

    private func formatButton(_ systemImage: String, title: String, command: MacMarkdownFormatCommand) -> some View {
        Button {
            applyMarkdown(command)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(title)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    #endif

    private func closeEditor() {
        if hasUnsavedChanges {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func togglePreview() {
        guard !isSaving else { return }
        isPreviewing.toggle()
    }

    private func copyNoteText() {
        #if os(iOS)
        UIPasteboard.general.string = noteBody
        #endif
    }

    private func applyMarkdown(_ command: MacMarkdownFormatCommand) {
        #if os(iOS)
        let result = MacMarkdownFormatter.apply(command: command, to: noteBody, selection: editorSelection)
        noteBody = result.text
        editorSelection = result.selection
        #endif
    }

    private func convertCurrentNote(to mode: NoteMode) {
        guard let note = editingNote else { return }
        if mode == .encrypted && !vaultStore.isKeyLoaded {
            showFirstKeyPrompt = true
            return
        }
        isSaving = true
        Task {
            do {
                let updated = try await vaultStore.updateNoteMode(note, body: noteBody, mode: mode)
                isEncrypted = updated.isEncrypted
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSaving = false
        }
    }

    private func deleteCurrentNote() {
        guard let note = editingNote else { return }
        Task {
            do {
                try await vaultStore.deleteNote(note)
                dismiss()
            } catch {
                errorMessage = "删除失败：\(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func toggleEncryption() {
        if isEncrypted {
            isEncrypted = false
            settings.preferredNoteMode = .plain
        } else {
            if !vaultStore.isKeyLoaded {
                showFirstKeyPrompt = true
            } else {
                isEncrypted = true
                settings.preferredNoteMode = .encrypted
            }
        }
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

private extension View {
    @ViewBuilder
    func dsGlassToolbarButton(isProminent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if isProminent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self
                .foregroundColor(isProminent ? DS.onPrimary : DS.textBody)
                .frame(width: 36, height: 36)
                .background(isProminent ? DS.primary : DS.surfaceSunken.opacity(0.6))
                .clipShape(Circle())
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
        isScrollEnabled = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = false
        autocapitalizationType = .sentences
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no
        autocorrectionType = .default

        let font = UIFont.systemFont(ofSize: 15)
        self.font = font

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.3
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

        layer.cornerRadius = DS.rMd
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(DS.line).cgColor

        updatePlaceholderVisibility()
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }
}

private struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    func makeUIView(context: Context) -> PlaceholderTextView {
        let textView = PlaceholderTextView()
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.text = text
        textView.selectedRange = selectedRange
        context.coordinator.textView = textView
        textView.backgroundColor = UIColor(DS.surfaceCard)
        return textView
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        uiView.placeholder = placeholder
        if uiView.text != text && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            uiView.text = text

            let font = UIFont.systemFont(ofSize: 15)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.3
            uiView.typingAttributes = [
                .font: font,
                .foregroundColor: UIColor(DS.textBody),
                .paragraphStyle: paragraphStyle
            ]

            context.coordinator.isUpdating = false
        }
        if uiView.selectedRange != selectedRange {
            uiView.selectedRange = selectedRange
        }
        uiView.updatePlaceholderVisibility()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var selectedRange: Binding<NSRange>
        weak var textView: PlaceholderTextView?
        var isUpdating = false

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            self.text = text
            self.selectedRange = selectedRange
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true
            text.wrappedValue = textView.text
            (textView as? PlaceholderTextView)?.updatePlaceholderVisibility()
            isUpdating = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            selectedRange.wrappedValue = textView.selectedRange
        }
    }
}
#endif
