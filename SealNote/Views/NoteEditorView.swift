import SwiftUI
import Combine

#if os(iOS)
import UIKit
import MarkdownView
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
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var session: EditorSession

    @State private var noteBody: String = ""
    @State private var isEncrypted: Bool = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var persistedNote: Note?
    @State private var lastSavedBody = ""
    @State private var lastSavedEncrypted = false
    @State private var didConfigureInitialState = false
    @State private var didDiscardEmptyNote = false
    @State private var shouldSkipDisappearPersistence = false
    @State private var isMarkdownPreviewing = false

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
        session.hasUnsavedChanges
    }

    init(
        mode: NoteEditorMode,
        initialBody: String = "",
        onSave: @escaping (String, Bool) async throws -> Note?
    ) {
        self.mode = mode
        self.initialBody = initialBody
        self.onSave = onSave

        // Existing notes must be present before SwiftUI creates the underlying
        // UITextView. Injecting a full body from `onAppear` causes UIKit to
        // rebuild attributed text while SwiftUI is measuring the sheet, which
        // can lock the main thread in repeated text/layout updates.
        if case .edit(let note) = mode {
            _noteBody = State(initialValue: note.body)
            _isEncrypted = State(initialValue: note.isEncrypted)
            _persistedNote = State(initialValue: note)
            _lastSavedBody = State(initialValue: note.body)
            _lastSavedEncrypted = State(initialValue: note.isEncrypted)
            _didConfigureInitialState = State(initialValue: true)
        }

        let editingNote: Note? = { if case .edit(let note) = mode { return note } else { return nil } }()
        _session = StateObject(wrappedValue: EditorSession(
            initialNote: editingNote,
            initialBody: editingNote?.body ?? initialBody,
            initialEncrypted: editingNote?.isEncrypted ?? false,
            autoDiscardEmpty: { SettingsStore.shared.autoDeleteEmptyNotes },
            create: onSave,
            update: { note, body in
                try await VaultStore.shared.updateNote(note, body: body)
                return VaultStore.shared.readableNotes.first(where: { $0.id == note.id }) ?? note
            },
            convert: { note, body, mode in
                try await VaultStore.shared.updateNoteMode(note, body: body, mode: mode)
            },
            discardEmpty: { note, body in
                try await VaultStore.shared.discardEmptyNote(note, body: body)
            }
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(iOS)
                if isMarkdownPreviewing {
                    markdownPreview
                } else {
                    editorBody
                }
                #else
                editorBody
                #endif

                #if os(iOS)
                if !isMarkdownPreviewing {
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
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isMarkdownPreviewing.toggle()
                        }
                    } label: {
                        Image(systemName: isMarkdownPreviewing ? "pencil" : "eye")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel(isMarkdownPreviewing ? "返回编辑" : "Markdown 预览")
                    .disabled(isSaving)

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
            .onChange(of: noteBody) { _, _ in
                guard didConfigureInitialState else { return }
                session.noteDidChange(body: noteBody, isEncrypted: isEncrypted)
            }
            .onChange(of: isEncrypted) { _, _ in
                guard didConfigureInitialState else { return }
                session.noteDidChange(body: noteBody, isEncrypted: isEncrypted)
            }
            .onChange(of: session.isSaving) { _, saving in isSaving = saving }
            .onChange(of: session.persistedNote) { _, note in persistedNote = note }
            .onChange(of: session.lastSaveError) { _, err in
                if let err { errorMessage = err; showError = true }
            }
            .onDisappear {
                persistBeforeViewDisappears()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active && !shouldSkipDisappearPersistence {
                    flushInBackground()
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
        .interactiveDismissDisabled(
            isSaving || hasUnsavedChanges || shouldCreateInitialNote || shouldDiscardEmptyExistingNote
        )
        .sheet(isPresented: $showTrashFromKeySettings) {
            TrashView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        #if os(iOS)
        // Self-scrolling UITextView fills the space above the format bar — no outer
        // ScrollView / sizeThatFits measurement (P1-1).
        NoteTextView(
            text: $noteBody,
            selectedRange: $editorSelection,
            placeholder: "写下想法，支持 Markdown 和 #标签",
            fontSize: CGFloat(settings.macEditorFontSize),
            lineHeightMultiple: CGFloat(settings.macEditorLineHeightMultiple)
        )
        .frame(maxWidth: DS.contentMax)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
            }
            .padding(DS.cardPadding)
            .frame(maxWidth: DS.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        #endif
    }

    #if os(iOS)
    private var markdownPreview: some View {
        ScrollView {
            Group {
                if noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("随便写点什么吧")
                        .font(.system(size: CGFloat(settings.macEditorFontSize)))
                        .foregroundColor(DS.textSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownView(noteBody)
                        .font(.system(size: CGFloat(settings.macEditorFontSize)), for: .body)
                        .font(
                            .system(size: max(11, CGFloat(settings.macEditorFontSize) - 1), design: .monospaced),
                            for: .codeBlock
                        )
                        .markdownComponentSpacing(
                            max(8, CGFloat(settings.macEditorFontSize) * (CGFloat(settings.macEditorLineHeightMultiple) - 0.7))
                        )
                        .markdownMathRenderingEnabled()
                        .foregroundStyle(DS.textBody)
                        .headingStyle(DS.textEmphasize, for: .h1)
                        .headingStyle(DS.textEmphasize, for: .h2)
                        .headingStyle(DS.textEmphasize, for: .h3)
                        .headingStyle(DS.textEmphasize, for: .h4)
                        .headingStyle(DS.textEmphasize, for: .h5)
                        .headingStyle(DS.textEmphasize, for: .h6)
                        .tint(DS.primaryDeep)
                        .tint(DS.link, for: .link)
                        .tint(DS.link, for: .blockQuote)
                        .tint(DS.primaryDeep, for: .inlineCodeBlock)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DS.cardPadding * 2)
            .frame(maxWidth: DS.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }
    #endif

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
                    formatButton("underline", title: "下划线", command: .underline)
                    formatButton("curlybraces", title: "代码", command: .inlineCode)
                    formatButton("function", title: "行内公式", command: .inlineMath)
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
        persistCurrentSnapshot(dismissAfterSave: true, discardEmptyIfNeeded: true)
    }

    /// Flush pending edits when leaving the foreground, protected by a background task so
    /// the write survives the iOS suspension window (P0-5).
    private func flushInBackground() {
        #if os(iOS)
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        Task {
            await session.flush(reason: .background)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        #endif
    }

    private func persistBeforeViewDisappears() {
        guard didConfigureInitialState else { return }
        guard !shouldSkipDisappearPersistence else { return }
        if showKeySettings {
            if hasUnsavedChanges || shouldCreateInitialNote {
                persistCurrentSnapshot()
            }
            return
        }
        guard hasUnsavedChanges || shouldCreateInitialNote || shouldDiscardEmptyExistingNote else { return }
        persistCurrentSnapshot(discardEmptyIfNeeded: true)
    }

    private func persistCurrentSnapshot(
        dismissAfterSave: Bool = false,
        discardEmptyIfNeeded: Bool = false
    ) {
        Task {
            await saveCurrentSnapshot(
                dismissAfterSave: dismissAfterSave,
                discardEmptyIfNeeded: discardEmptyIfNeeded
            )
        }
    }

    @MainActor
    private func saveCurrentSnapshot(
        dismissAfterSave: Bool = false,
        discardEmptyIfNeeded: Bool = false
    ) async {
        guard didConfigureInitialState else {
            if dismissAfterSave { dismiss() }
            return
        }
        // The EditorSession is the sole writer (debounced, one-in-flight, newest wins).
        if discardEmptyIfNeeded {
            await session.close()   // flush pending edits + apply the auto-discard-empty rule
        } else {
            await session.flush(reason: .background)
        }
        persistedNote = session.persistedNote
        lastSavedBody = noteBody
        lastSavedEncrypted = isEncrypted
        if dismissAfterSave { dismiss() }
    }

    private func copyNoteText() {
        #if os(iOS)
        UIPasteboard.general.string = settings.copyAddsParagraphSpacing
            ? MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: noteBody)
            : noteBody
        #endif
    }

    private func applyMarkdown(_ command: MacMarkdownFormatCommand) {
        #if os(iOS)
        let linkURL: String?
        if case .link = command {
            linkURL = MacMarkdownFormatter.webURL(fromClipboardString: UIPasteboard.general.string)
        } else {
            linkURL = nil
        }
        let result = MacMarkdownFormatter.apply(
            command: command,
            to: noteBody,
            selection: editorSelection,
            linkURL: linkURL
        )
        noteBody = result.text
        editorSelection = result.selection
        #endif
    }

    private func convertCurrentNote(to mode: NoteMode) {
        guard currentPersistedNote != nil else { return }
        if mode == .encrypted && !vaultStore.isKeyLoaded {
            showFirstKeyPrompt = true
            return
        }
        // Flush + convert in place; the editor stays open (P0-5 — no dismiss).
        Task {
            do {
                try await session.convertMode(to: mode)
                if let converted = session.persistedNote {
                    persistedNote = converted
                    isEncrypted = converted.isEncrypted
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func deleteCurrentNote() {
        guard let note = currentPersistedNote else { return }
        Task {
            do {
                try await vaultStore.deleteNote(note)
                shouldSkipDisappearPersistence = true
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

    private var shouldDiscardEmptyExistingNote: Bool {
        settings.autoDeleteEmptyNotes
            && !didDiscardEmptyNote
            && currentPersistedNote != nil
            && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    private(set) var editorFontSize: CGFloat = 15
    private(set) var editorLineHeightMultiple: CGFloat = 1.3

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
        showsVerticalScrollIndicator = true
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        isFindInteractionEnabled = true
        autocapitalizationType = .sentences
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no
        autocorrectionType = .default
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        let font = UIFont.systemFont(ofSize: editorFontSize)
        self.font = font
        typingAttributes = MacMarkdownHighlighter.iosTypingAttributes(
            fontSize: editorFontSize,
            lineHeightMultiple: editorLineHeightMultiple
        )

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

    func applyMarkdownHighlighting(
        text newText: String,
        selectedRange range: NSRange,
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat
    ) {
        editorFontSize = fontSize
        editorLineHeightMultiple = lineHeightMultiple
        placeholderLabel.font = UIFont.systemFont(ofSize: fontSize)
        let attributed = MacMarkdownHighlighter.makeIOSHighlightedAttributedString(
            text: newText,
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        let preservedContentOffset = contentOffset
        let undoManager = undoManager
        let shouldRestoreUndoRegistration = undoManager?.isUndoRegistrationEnabled == true
        if shouldRestoreUndoRegistration {
            undoManager?.disableUndoRegistration()
        }
        textStorage.setAttributedString(attributed)
        if shouldRestoreUndoRegistration, undoManager?.isUndoRegistrationEnabled == false {
            undoManager?.enableUndoRegistration()
        }
        typingAttributes = MacMarkdownHighlighter.iosTypingAttributes(
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        selectedRange = safeRange(range, in: newText)
        setContentOffset(preservedContentOffset, animated: false)
        updatePlaceholderVisibility()
    }

    /// Re-highlight only the paragraph around the caret, in place — no `setAttributedString`
    /// per keystroke (P1-1). Spans are computed globally so fences/tables stay correct.
    func applyIncrementalHighlighting() {
        let ns = text as NSString
        typingAttributes = MacMarkdownHighlighter.iosTypingAttributes(
            fontSize: editorFontSize,
            lineHeightMultiple: editorLineHeightMultiple
        )
        guard ns.length > 0 else { return }
        let caret = min(max(0, selectedRange.location), ns.length)
        let dirtyRange = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        MacMarkdownHighlighter.applyIOSHighlighting(
            to: textStorage,
            text: text,
            dirtyRange: dirtyRange,
            fontSize: editorFontSize,
            lineHeightMultiple: editorLineHeightMultiple
        )
    }

    func usesStyle(fontSize: CGFloat, lineHeightMultiple: CGFloat) -> Bool {
        editorFontSize == fontSize && editorLineHeightMultiple == lineHeightMultiple
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func safeRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(range.length, maxLength))
    }
}

private struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var placeholder: String
    var fontSize: CGFloat
    var lineHeightMultiple: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    func makeUIView(context: Context) -> PlaceholderTextView {
        let textView = PlaceholderTextView()
        textView.placeholder = placeholder
        // Configure the initial attributed text before installing the delegate.
        // `textStorage.setAttributedString` can synchronously emit
        // `textViewDidChange`; installing the delegate first would make that
        // callback reapply the attributed text recursively and freeze the UI.
        context.coordinator.isUpdating = true
        textView.applyMarkdownHighlighting(
            text: text,
            selectedRange: selectedRange,
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        textView.selectedRange = selectedRange
        context.coordinator.isUpdating = false
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.backgroundColor = UIColor(DS.surfaceCard)
        return textView
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        uiView.placeholder = placeholder
        let styleChanged = !uiView.usesStyle(
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        if (uiView.text != text || styleChanged) && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            uiView.applyMarkdownHighlighting(
                text: text,
                selectedRange: selectedRange,
                fontSize: fontSize,
                lineHeightMultiple: lineHeightMultiple
            )
            context.coordinator.isUpdating = false
        }
        if uiView.selectedRange != selectedRange {
            context.coordinator.isUpdating = true
            uiView.selectedRange = selectedRange
            context.coordinator.isUpdating = false
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

        // ponytail: single threshold + debounce
        private static let largeDocThreshold = 30_000
        private var highlightWorkItem: DispatchWorkItem?

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true
            let newText = textView.text ?? ""
            let newSelection = textView.selectedRange
            text.wrappedValue = newText
            selectedRange.wrappedValue = newSelection
            if textView.markedTextRange != nil {
                (textView as? PlaceholderTextView)?.updatePlaceholderVisibility()
                isUpdating = false
                return
            }
            if let ptv = textView as? PlaceholderTextView {
                scheduleIncrementalHighlight(for: ptv)
                ptv.updatePlaceholderVisibility()
            }
            isUpdating = false
        }

        private func scheduleIncrementalHighlight(for textView: PlaceholderTextView) {
            highlightWorkItem?.cancel()
            if (textView.text as NSString).length <= Self.largeDocThreshold {
                textView.applyIncrementalHighlighting()
            } else {
                // Large document: debounce; typing still shows via typingAttributes meanwhile.
                let work = DispatchWorkItem { [weak textView] in textView?.applyIncrementalHighlighting() }
                highlightWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n", range.length == 0,
                  textView.markedTextRange == nil,
                  let textView = textView as? PlaceholderTextView else {
                return true
            }

            let currentText = textView.text ?? ""
            let currentSelection = NSRange(location: range.location, length: 0)
            let result: MacMarkdownFormatResult?
            if let completion = MacMarkdownFormatter.completeCodeFenceIfNeeded(
                in: currentText,
                selection: currentSelection
            ) {
                result = MacMarkdownFormatResult(
                    text: completion.text,
                    selection: completion.selection
                )
            } else if let continuation = MacMarkdownFormatter.continueListIfNeeded(
                in: currentText,
                selection: currentSelection
            ) {
                result = MacMarkdownFormatResult(
                    text: continuation.text,
                    selection: continuation.selection
                )
            } else {
                result = nil
            }

            guard let result else { return true }
            isUpdating = true
            text.wrappedValue = result.text
            selectedRange.wrappedValue = result.selection
            textView.applyMarkdownHighlighting(
                text: result.text,
                selectedRange: result.selection,
                fontSize: textView.editorFontSize,
                lineHeightMultiple: textView.editorLineHeightMultiple
            )
            isUpdating = false
            return false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating else { return }
            selectedRange.wrappedValue = textView.selectedRange
        }
    }
}
#endif

/// Owns the editor's autosave lifecycle (P0-5): debounced saves so edits survive an app
/// kill, a single in-flight save where the newest revision always wins (no dropped
/// concurrent saves), an idempotent `close()`, and mode conversion that never dismisses.
/// Persistence is injected as closures so the logic is testable without a store.
@MainActor
final class EditorSession: ObservableObject {
    enum FlushReason { case debounce, background, close, convert, delete }

    @Published private(set) var persistedNote: Note?
    @Published private(set) var isSaving: Bool = false
    @Published var lastSaveError: String?

    private let debounceInterval: TimeInterval
    private let autoDiscardEmpty: () -> Bool
    private let create: (String, Bool) async throws -> Note?
    private let update: (Note, String) async throws -> Note
    private let convert: (Note, String, NoteMode) async throws -> Note
    private let discardEmpty: (Note, String) async throws -> Void

    private var currentBody: String
    private var currentEncrypted: Bool
    private var revision = 0
    private var savedRevision = 0
    private var debounceTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var closeRequested = false

    init(
        initialNote: Note?,
        initialBody: String = "",
        initialEncrypted: Bool = false,
        debounceInterval: TimeInterval = 0.5,
        autoDiscardEmpty: @escaping () -> Bool = { false },
        create: @escaping (String, Bool) async throws -> Note?,
        update: @escaping (Note, String) async throws -> Note,
        convert: @escaping (Note, String, NoteMode) async throws -> Note,
        discardEmpty: @escaping (Note, String) async throws -> Void
    ) {
        self.persistedNote = initialNote
        self.currentBody = initialBody
        self.currentEncrypted = initialEncrypted
        self.debounceInterval = debounceInterval
        self.autoDiscardEmpty = autoDiscardEmpty
        self.create = create
        self.update = update
        self.convert = convert
        self.discardEmpty = discardEmpty
    }

    var hasUnsavedChanges: Bool { revision != savedRevision }

    func noteDidChange(body: String, isEncrypted: Bool) {
        currentBody = body
        currentEncrypted = isEncrypted
        revision += 1
        debounceTask?.cancel()
        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.flush(reason: .debounce)
        }
    }

    /// Persist until `savedRevision == revision`. A single drain loop does the saving;
    /// concurrent callers await the same drain, so there is never a double-save.
    func flush(reason: FlushReason) async {
        debounceTask?.cancel()
        if savedRevision == revision { return }
        let task: Task<Void, Never>
        if let drainTask {
            task = drainTask
        } else {
            let created = Task { [weak self] in
                guard let self else { return }
                await self.drainLoop()
            }
            drainTask = created
            task = created
        }
        await task.value
    }

    private func drainLoop() async {
        isSaving = true
        while savedRevision != revision {
            let target = revision
            let body = currentBody
            let encrypted = currentEncrypted
            do {
                if let note = persistedNote {
                    if note.isEncrypted != encrypted {
                        persistedNote = try await convert(note, body, encrypted ? .encrypted : .plain)
                    } else {
                        persistedNote = try await update(note, body)
                    }
                } else if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Create-mode with nothing to save: mark caught up, create nothing.
                } else {
                    persistedNote = try await create(body, encrypted)
                }
                savedRevision = max(savedRevision, target)
                lastSaveError = nil
            } catch {
                lastSaveError = error.localizedDescription
                break   // leave savedRevision behind; a later change/flush retries
            }
        }
        isSaving = false
        drainTask = nil
    }

    /// Idempotent. Flushes pending edits, then applies the auto-discard-empty rule.
    func close() async {
        guard !closeRequested else { return }
        closeRequested = true
        debounceTask?.cancel()
        await flush(reason: .close)
        if autoDiscardEmpty(),
           let note = persistedNote,
           currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? await discardEmpty(note, currentBody)
            persistedNote = nil
        }
    }

    /// Flush pending edits, then convert the note's mode. Never dismisses (P0-5).
    func convertMode(to mode: NoteMode) async throws {
        await flush(reason: .convert)
        guard let note = persistedNote else { return }
        persistedNote = try await convert(note, currentBody, mode)
        savedRevision = revision
    }
}
