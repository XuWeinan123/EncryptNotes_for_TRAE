import SwiftUI
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
    let onSave: (String, Bool) async throws -> Note?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vaultStore = VaultStore.shared
    private let settings = SettingsStore.shared

    @State private var noteBody: String = ""
    @State private var isEncrypted: Bool = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var isPreviewing = false
    @State private var showDeleteConfirmation = false
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var persistedNote: Note?
    @State private var lastSavedBody = ""
    @State private var lastSavedEncrypted = false
    @State private var didConfigureInitialState = false

    @State private var showFirstKeyPrompt = false
    @State private var showKeySettings = false
    @State private var showTrashFromKeySettings = false

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingNote: Note? {
        if case .edit(let note) = mode { return note }
        return nil
    }

    private var currentPersistedNote: Note? {
        persistedNote ?? editingNote
    }

    private var hasUnsavedChanges: Bool {
        noteBody != lastSavedBody || isEncrypted != lastSavedEncrypted
    }

    init(
        mode: NoteEditorMode,
        initialBody: String = "",
        onSave: @escaping (String, Bool) async throws -> Note?
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
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    #if os(iOS)
                    Button { togglePreview() } label: {
                        Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isPreviewing ? DS.primaryDeep : DS.textSecondary)
                    }
                    .disabled(isSaving)
                    .accessibilityLabel(isPreviewing ? "返回编辑" : "Markdown 预览")
                    #endif

                    Menu {
                        Button {
                            copyNoteText()
                        } label: {
                            Label("复制正文", systemImage: "doc.on.doc")
                        }
                        .disabled(noteBody.isEmpty)

                        if let note = currentPersistedNote {
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

                    if !isEditing {
                        Button {
                            toggleEncryption()
                        } label: {
                            Image(systemName: isEncrypted ? "lock.fill" : "lock.open")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isEncrypted ? DS.primaryDeep : DS.textSecondary)
                        }
                        .disabled(isSaving)
                    }

                    if isSaving {
                        ProgressView()
                    }
                }
            }
            .onAppear { configureInitialState() }
            .onDisappear {
                persistBeforeViewDisappears()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    persistCurrentSnapshot()
                }
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
            .alert(keyPromptTitle, isPresented: $showFirstKeyPrompt) {
                Button("打开密钥设置") { showKeySettings = true }
                Button("取消", role: .cancel) {}
            } message: {
                Text(keyPromptMessage)
            }
            .fullScreenCover(isPresented: $showKeySettings) {
                SettingsView(
                    isPresented: $showKeySettings,
                    showTrash: $showTrashFromKeySettings,
                    initialRoute: .key
                )
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
                    NoteTextView(text: $noteBody, selectedRange: $editorSelection, placeholder: "写下想法，支持 Markdown 和 #标签")
                        .frame(maxWidth: .infinity, minHeight: 400, alignment: .topLeading)
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
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var markdownPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("写下想法，支持 Markdown 和 #标签")
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
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.line)
                .frame(height: 0.5)

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private func formatButton(_ systemImage: String, title: String, command: MacMarkdownFormatCommand) -> some View {
        Button {
            applyMarkdown(command)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.primaryDeep)
                .frame(width: 36, height: 36)
                .background(DS.surfaceCard.opacity(0.72))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(DS.line, lineWidth: 0.5)
                )
        }
        .accessibilityLabel(title)
        .buttonStyle(.plain)
    }
    #endif

    private func closeEditor() {
        persistCurrentSnapshot(dismissAfterSave: true)
    }

    private func persistBeforeViewDisappears() {
        guard didConfigureInitialState else { return }
        guard hasUnsavedChanges || shouldCreateInitialNote else { return }
        persistCurrentSnapshot()
    }

    private func persistCurrentSnapshot(dismissAfterSave: Bool = false) {
        Task { await saveCurrentSnapshot(dismissAfterSave: dismissAfterSave) }
    }

    @MainActor
    private func saveCurrentSnapshot(dismissAfterSave: Bool = false) async {
        guard didConfigureInitialState else {
            if dismissAfterSave { dismiss() }
            return
        }

        guard !isSaving else { return }

        let bodySnapshot = noteBody
        let encryptedSnapshot = isEncrypted
        let trimmedBody = bodySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteToUpdate = currentPersistedNote
        let shouldCreate = noteToUpdate == nil && !trimmedBody.isEmpty
        let shouldUpdate = noteToUpdate != nil && hasUnsavedChanges

        guard shouldCreate || shouldUpdate else {
            if dismissAfterSave { dismiss() }
            return
        }

        isSaving = true
        do {
            if let noteToUpdate {
                let updatedNote: Note
                if noteToUpdate.isEncrypted != encryptedSnapshot {
                    updatedNote = try await vaultStore.updateNoteMode(
                        noteToUpdate,
                        body: bodySnapshot,
                        mode: encryptedSnapshot ? .encrypted : .plain
                    )
                } else {
                    try await vaultStore.updateNote(noteToUpdate, body: bodySnapshot)
                    updatedNote = vaultStore.readableNotes.first(where: { $0.id == noteToUpdate.id }) ?? noteToUpdate
                }
                persistedNote = updatedNote
            } else if let createdNote = try await onSave(bodySnapshot, encryptedSnapshot) {
                persistedNote = createdNote
            }

            lastSavedBody = bodySnapshot
            lastSavedEncrypted = encryptedSnapshot
            isSaving = false

            if dismissAfterSave {
                dismiss()
            }
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
            showError = true
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
        guard let note = currentPersistedNote else { return }
        if mode == .encrypted && !vaultStore.isKeyLoaded {
            showFirstKeyPrompt = true
            return
        }
        isSaving = true
        Task {
            do {
                let updated = try await vaultStore.updateNoteMode(note, body: noteBody, mode: mode)
                persistedNote = updated
                isEncrypted = updated.isEncrypted
                lastSavedBody = noteBody
                lastSavedEncrypted = updated.isEncrypted
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSaving = false
        }
    }

    private func deleteCurrentNote() {
        guard let note = currentPersistedNote else { return }
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
        guard !didConfigureInitialState else { return }

        if case .edit(let note) = mode {
            noteBody = note.body
            isEncrypted = note.isEncrypted
            persistedNote = note
        } else {
            noteBody = initialBody
            if vaultStore.isKeyLoaded {
                isEncrypted = settings.preferredNoteMode == .encrypted
            } else {
                isEncrypted = false
            }

        }
        lastSavedBody = noteBody
        lastSavedEncrypted = isEncrypted
        didConfigureInitialState = true
    }

    private var shouldCreateInitialNote: Bool {
        currentPersistedNote == nil && !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var keyPromptTitle: String {
        #if os(iOS)
        if case .invalid = vaultStore.iosKeyStatus {
            return "密钥失效"
        }
        #endif
        return "需要密钥"
    }

    private var keyPromptMessage: String {
        #if os(iOS)
        if case .invalid = vaultStore.iosKeyStatus {
            return "当前本机密钥不可用，需要前往设置页重新导入密钥或处理加密笔记。"
        }
        #endif
        return "需要先前往设置页创建或加载密钥。"
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
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        let font = UIFont.systemFont(ofSize: 15)
        self.font = font

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.3
        typingAttributes = [
            .font: font,
            .foregroundColor: UIColor(DS.textBody),
            .paragraphStyle: paragraphStyle
        ]

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.widthTracksTextView = true
        textContainerInset = UIEdgeInsets(top: DS.cardPadding, left: DS.cardPadding, bottom: DS.cardPadding, right: DS.cardPadding)

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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PlaceholderTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - DS.cardPadding * 2
        let fittingSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let measuredSize = uiView.sizeThatFits(fittingSize)
        return CGSize(width: width, height: max(400, measuredSize.height))
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
