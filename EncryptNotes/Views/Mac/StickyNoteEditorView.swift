import Foundation
import SwiftUI
import AppKit
import Combine

#if os(macOS)

struct StickyNoteEditorView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var syncStore = SyncStatusStore.shared
    @StateObject private var viewModel: StickyNoteEditorViewModel

    init(note: Note, isPreview: Bool = false) {
        _viewModel = StateObject(wrappedValue: StickyNoteEditorViewModel(note: note, isPreview: isPreview))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MacTextView(
                text: $viewModel.text,
                placeholder: "随便写点什么吧",
                fontSize: CGFloat(settings.macEditorFontSize),
                lineHeightMultiple: CGFloat(settings.macEditorLineHeightMultiple),
                autoFocus: true,
                onChange: { viewModel.textDidChange($0) },
                onSaveShortcut: { viewModel.saveImmediately() },
                onApplyShortcut: { viewModel.saveImmediately() },
                onFitToContent: { viewModel.fitWindowToContent() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, MacStickyEditorLayout.editorHorizontalInset)

            if !syncStore.isNetworkAvailable {
                Text("无网络")
                    .font(DS.caption())
                    .foregroundColor(DS.destructive)
                    .padding(.trailing, DS.s3)
                    .padding(.bottom, DS.s2)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        // 内容延伸到工具栏下方供系统玻璃采样；首行留白由 MacTextView 计算。
        .ignoresSafeArea(edges: .top)
        .dsMacStickyToolbarScrollEdge()
        .navigationTitle("")
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: viewModel.forceClose) { _, shouldClose in
            if shouldClose {
                StickyNoteWindowManager.shared.closeWindow(for: viewModel.note.id)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { viewModel.copyNoteText() }) {
                    Label(
                        viewModel.didCopy ? "已复制" : "复制",
                        systemImage: viewModel.didCopy ? "checkmark" : "square.on.square"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: DS.macToolbarIconWidth)
                }
                .help(viewModel.didCopy ? "已复制" : "复制")

                Menu {
                    Button(action: { viewModel.fitWindowToContent() }) {
                        Label("适应内容", systemImage: "arrow.up.left.and.arrow.down.right")
                    }

                    Divider()

                    Button(role: viewModel.isContentEmpty ? .destructive : nil,
                           action: { viewModel.deleteNote() }) {
                        Label("移到回收站", systemImage: "trash")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: DS.macToolbarIconWidth)
                }
                .menuIndicator(.hidden)
                .help("更多")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                if viewModel.isPinned {
                    Button(action: { viewModel.togglePin() }) {
                        Label("取消置顶", systemImage: "pin.fill")
                            .labelStyle(.iconOnly)
                            .frame(width: DS.macToolbarIconWidth)
                    }
                    .help("取消置顶")
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(DS.primary)
                } else {
                    Button(action: { viewModel.togglePin() }) {
                        Label("置顶", systemImage: "pin.fill")
                            .labelStyle(.iconOnly)
                            .frame(width: DS.macToolbarIconWidth)
                    }
                    .help("置顶")
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
            }
        }
        .alert(isPresented: $viewModel.showingDeleteConfirmation) {
            Alert(
                title: Text("删除这条笔记？"),
                message: Text("笔记将移到回收站，可以恢复。"),
                primaryButton: .destructive(Text("删除")) {
                    viewModel.confirmDelete()
                },
                secondaryButton: .cancel()
            )
        }
    }
}

enum MacStickyEditorLayout {
    static let editorHorizontalInset = DS.s4
    static let editorBottomInset: CGFloat = 28
    static let widthMultiplier: CGFloat = 30

    static func horizontalPadding(textContainerInsetWidth: CGFloat) -> CGFloat {
        editorHorizontalInset * 2 + textContainerInsetWidth * 2 + 8
    }

    static func textContainerInset(fontSize: CGFloat) -> NSSize {
        MacMarkdownHighlighter.textContainerInset(size: fontSize)
    }
}

@MainActor
final class StickyNoteEditorViewModel: ObservableObject {
    @Published var note: Note
    @Published var text: String
    @Published var isPinned: Bool
    @Published var showingDeleteConfirmation = false
    @Published var didCopy = false
    @Published var forceClose = false

    private let vaultStore = VaultStore.shared
    private let windowStore = MacNoteWindowStore.shared
    private let syncStore = SyncStatusStore.shared
    private let isPreview: Bool
    private let wasInitiallyEmpty: Bool
    private var saveTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var isContentEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(note: Note, isPreview: Bool = false) {
        self.note = note
        self.text = note.body
        self.isPreview = isPreview
        self.wasInitiallyEmpty = note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.isPinned = windowStore.windowState(for: note.id)?.isPinned ?? true

        $isPinned
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.windowStore.setPinned(newValue, for: self.note.id)
                StickyNoteWindowManager.shared.updateWindowLevel(for: self.note.id, isPinned: newValue)
            }
            .store(in: &cancellables)
    }

    func onDisappear() {
        saveTask?.cancel()
        guard !forceClose else { return }
        handleWindowWillClose()
    }

    func textDidChange(_ newText: String) {
        text = newText
        debouncedSave()
    }

    func copyNoteText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                self?.didCopy = false
            }
        }
    }

    func togglePin() {
        isPinned.toggle()
    }

    func deleteNote() {
        if isContentEmpty {
            discardEmptyNoteAndClose()
            return
        }
        showingDeleteConfirmation = true
    }

    func confirmDelete() {
        guard !isPreview else {
            text = ""
            note.body = ""
            return
        }

        Task {
            do {
                try await vaultStore.deleteNote(note)
                forceClose = true
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    func saveImmediately() {
        saveTask?.cancel()
        save()
    }

    func fitWindowToContent() {
        StickyNoteWindowManager.shared.fitWindowToContent(
            noteId: note.id,
            text: text,
            fontSize: CGFloat(SettingsStore.shared.macEditorFontSize)
        )
    }

    private func debouncedSave() {
        saveTask?.cancel()

        syncStore.setSyncing()
        let bodyToSave = text
        let noteToUpdate = note

        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveSnapshot(bodyToSave, note: noteToUpdate)
        }
    }

    private func save() {
        guard !isPreview else {
            note.body = text
            syncStore.setSaved()
            return
        }

        guard text != note.body else {
            syncStore.setSaved()
            return
        }

        syncStore.setSyncing()
        let bodyToSave = text
        let noteToUpdate = note

        Task {
            await saveSnapshot(bodyToSave, note: noteToUpdate)
        }
    }

    private func saveSnapshot(_ snapshot: String, note noteToUpdate: Note) async {
        do {
            try await vaultStore.updateNote(noteToUpdate, body: snapshot)
            if let updatedNote = vaultStore.readableNotes.first(where: { $0.id == noteToUpdate.id }) {
                note = updatedNote
            }
            syncStore.setSaved()
        } catch {
            syncStore.setFailed(message: error.localizedDescription)
        }
    }

    private func handleWindowWillClose() {
        guard !isPreview else {
            note.body = text
            syncStore.setSaved()
            return
        }

        guard wasInitiallyEmpty && isContentEmpty else {
            save()
            return
        }

        discardEmptyNote()
    }

    private func discardEmptyNoteAndClose() {
        guard !isPreview else {
            text = ""
            note.body = ""
            return
        }

        saveTask?.cancel()
        Task {
            do {
                try await vaultStore.discardEmptyNote(note)
                syncStore.setSaved()
                forceClose = true
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func discardEmptyNote() {
        Task {
            do {
                try await vaultStore.discardEmptyNote(note)
                syncStore.setSaved()
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }
}

// MARK: - MacTextView

/// 正文延伸到工具栏下方，同时按窗口实测标题栏高度补齐首行留白。
private final class ToolbarInsetScrollView: NSScrollView {
    var baseInsets = NSEdgeInsets() {
        didSet { applyToolbarTopInset() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyToolbarTopInset()
    }

    override func layout() {
        super.layout()
        if let textView = documentView as? NSTextView {
            syncDocumentSize(textView)
        }
        applyToolbarTopInset()
    }

    func syncDocumentSize(_ textView: NSTextView? = nil) {
        guard let textView = textView ?? documentView as? NSTextView else { return }
        guard let textContainer = textView.textContainer else { return }
        let width = max(1, contentView.bounds.width)
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textContainer)

        let usedHeight = textView.layoutManager?.usedRect(for: textContainer).height ?? 0
        let height = max(
            contentView.bounds.height,
            ceil(usedHeight + textView.textContainerInset.height * 2)
        )
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        if textView.frame != frame {
            textView.frame = frame
        }
    }

    private func applyToolbarTopInset() {
        let top: CGFloat
        if let window = window {
            top = max(0, window.frame.height - window.contentLayoutRect.height)
        } else {
            top = baseInsets.top
        }
        let target = NSEdgeInsets(
            top: top,
            left: baseInsets.left,
            bottom: MacStickyEditorLayout.editorBottomInset,
            right: baseInsets.right
        )
        guard !insetsEqual(contentInsets, target) else { return }
        contentInsets = target
        scrollerInsets = target
    }

    private func insetsEqual(_ a: NSEdgeInsets, _ b: NSEdgeInsets) -> Bool {
        a.top == b.top && a.left == b.left && a.bottom == b.bottom && a.right == b.right
    }
}

struct MacTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    let autoFocus: Bool
    let onChange: (String) -> Void
    let onSaveShortcut: () -> Void
    let onApplyShortcut: () -> Void
    let onFitToContent: () -> Void

    init(
        text: Binding<String>,
        placeholder: String,
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat,
        autoFocus: Bool = true,
        onChange: @escaping (String) -> Void,
        onSaveShortcut: @escaping () -> Void,
        onApplyShortcut: @escaping () -> Void,
        onFitToContent: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        self.autoFocus = autoFocus
        self.onChange = onChange
        self.onSaveShortcut = onSaveShortcut
        self.onApplyShortcut = onApplyShortcut
        self.onFitToContent = onFitToContent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let scrollView = ToolbarInsetScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.autoresizesSubviews = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = AutoFocusTextView()
        textView.coordinator = context.coordinator
        textView.isAutoFocusEnabled = autoFocus

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = MacStickyEditorLayout.textContainerInset(fontSize: fontSize)
        textView.drawsBackground = true
        textView.backgroundColor = .clear
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.layoutManager?.usesFontLeading = false

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
        }

        context.coordinator.configureTextView(textView, text: text, fontSize: fontSize)
        textView.delegate = context.coordinator

        if autoFocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let scrollView = nsView as? ToolbarInsetScrollView,
              let textView = scrollView.documentView as? AutoFocusTextView else { return }

        context.coordinator.parent = self
        scrollView.automaticallyAdjustsContentInsets = false

        if textView.isUpdating { return }
        textView.isUpdating = true
        defer { textView.isUpdating = false }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: text, fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
            textView.textStorage?.setAttributedString(attributed)
            textView.selectedRanges = selectedRanges
        } else {
            let paraStyle = MacMarkdownHighlighter.paragraphStyle(size: fontSize, multiple: lineHeightMultiple)
            let bodyFont = MacMarkdownHighlighter.bodyFont(size: fontSize)
            let baselineOff = MacMarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if fullRange.length > 0 {
                textView.textStorage?.addAttributes([
                    .font: bodyFont,
                    .paragraphStyle: paraStyle,
                    .baselineOffset: baselineOff
                ], range: fullRange)
                MacMarkdownHighlighter.applyMarkdownHighlighting(to: textView, lineHeightMultiple: lineHeightMultiple)
            }
        }

        textView.textContainerInset = MacStickyEditorLayout.textContainerInset(fontSize: fontSize)
        scrollView.syncDocumentSize(textView)

        if textView.placeholderLabel.string != placeholder {
            textView.placeholderLabel.string = placeholder
        }
        updatePlaceholderVisibility(textView)
        updatePlaceholderStyle(textView, fontSize: fontSize)

        if autoFocus, textView.window != nil, !textView.didInitialFocus {
            textView.didInitialFocus = true
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func updatePlaceholderStyle(_ textView: AutoFocusTextView, fontSize: CGFloat) {
        let bodyFont = MacMarkdownHighlighter.bodyFont(size: fontSize)
        let paraStyle = MacMarkdownHighlighter.paragraphStyle(size: fontSize, multiple: lineHeightMultiple)
        let baselineOff = MacMarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)
        textView.placeholderLabel.font = bodyFont
        textView.placeholderLabel.paragraphStyle = paraStyle
        textView.placeholderLabel.textColor = NSColor.placeholderTextColor
        textView.placeholderLabel.baselineOffset = baselineOff
    }

    private func updatePlaceholderVisibility(_ textView: AutoFocusTextView) {
        textView.placeholderLabel.isHidden = !textView.string.isEmpty
    }
}

// MARK: - Coordinator

extension MacTextView {
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTextView
        private var lastText: String = ""

        init(_ parent: MacTextView) {
            self.parent = parent
            super.init()
        }

        func configureTextView(_ textView: AutoFocusTextView, text: String, fontSize: CGFloat) {
            let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: text, fontSize: fontSize, lineHeightMultiple: fontSize == parent.fontSize ? parent.lineHeightMultiple : CGFloat(SettingsStore.defaultMacEditorLineHeightMultiple))
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = Self.typingAttributes(fontSize: fontSize, lineHeightMultiple: parent.lineHeightMultiple)
            lastText = text
        }

        static func typingAttributes(fontSize: CGFloat, lineHeightMultiple: CGFloat) -> [NSAttributedString.Key: Any] {
            let bodyFont = MacMarkdownHighlighter.bodyFont(size: fontSize)
            return [
                .font: bodyFont,
                .foregroundColor: NSColor(DS.textBody),
                .paragraphStyle: MacMarkdownHighlighter.paragraphStyle(size: fontSize, multiple: lineHeightMultiple),
                .baselineOffset: MacMarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)
            ]
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? AutoFocusTextView, !textView.isUpdating else { return }
            textView.isUpdating = true
            let newText = textView.string ?? ""
            parent.onChange(newText)
            lastText = newText
            MacMarkdownHighlighter.applyMarkdownHighlighting(to: textView, lineHeightMultiple: parent.lineHeightMultiple)
            textView.typingAttributes = Self.typingAttributes(fontSize: parent.fontSize, lineHeightMultiple: parent.lineHeightMultiple)
            parent.updatePlaceholderVisibility(textView)
            (textView.enclosingScrollView as? ToolbarInsetScrollView)?.syncDocumentSize(textView)
            textView.isUpdating = false
        }

        func textDidBeginEditing(_ notification: Notification) {}
        func textDidEndEditing(_ notification: Notification) {}
    }
}

// MARK: - AutoFocusTextView

final class AutoFocusTextView: NSTextView {
    var isAutoFocusEnabled = true
    var isUpdating = false
    var didInitialFocus = false
    weak var coordinator: MacTextView.Coordinator?

    let placeholderLabel = PlaceholderLabel()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, isAutoFocusEnabled, !didInitialFocus {
            didInitialFocus = true
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if placeholderLabel.superview == nil {
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(placeholderLabel)
            let containerInset = textContainerInset
            let linePadding = textContainer?.lineFragmentPadding ?? 0
            NSLayoutConstraint.activate([
                placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: containerInset.width + linePadding),
                placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: containerInset.height)
            ])
        }
    }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
            super.keyDown(with: event)
            return
        }

        let cmd = event.modifierFlags.contains(.command)
        let ctrl = event.modifierFlags.contains(.control)
        let opt = event.modifierFlags.contains(.option)
        let shift = event.modifierFlags.contains(.shift)

        let cmdOnly = cmd && !ctrl && !opt && !shift
        let cmdShiftOnly = cmd && shift && !ctrl && !opt
        let cmdOptOnly = cmd && opt && !ctrl && !shift

        if let action = ShortcutStore.shared.markdownAction(matching: event) {
            applyFormat(action.command); return
        }

        if cmdOnly && chars == "s" {
            coordinator?.parent.onSaveShortcut(); return
        }
        if cmdShiftOnly && chars == "s" {
            coordinator?.parent.onApplyShortcut(); return
        }
        if cmdOptOnly && chars == "f" {
            coordinator?.parent.onFitToContent(); return
        }

        super.keyDown(with: event)
    }

    private func applyFormat(_ command: MacMarkdownFormatCommand) {
        let currentText = self.string ?? ""
        let selection = self.selectedRange()
        let result = MacMarkdownFormatter.apply(command: command, to: currentText, selection: selection)

        isUpdating = true
        let fontSize = (coordinator?.parent.fontSize) ?? 14
        let lineHeightMultiple = (coordinator?.parent.lineHeightMultiple) ?? CGFloat(SettingsStore.defaultMacEditorLineHeightMultiple)
        let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: result.text, fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        textStorage?.setAttributedString(attributed)
        self.setSelectedRange(result.selection)
        didChangeText()
        coordinator?.parent.onChange(result.text)
        MacMarkdownHighlighter.applyMarkdownHighlighting(to: self, lineHeightMultiple: lineHeightMultiple)
        (enclosingScrollView as? ToolbarInsetScrollView)?.syncDocumentSize(self)
        typingAttributes = MacTextView.Coordinator.typingAttributes(fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        if let placeholder = self.subviews.first(where: { $0 is PlaceholderLabel }) as? PlaceholderLabel {
            placeholder.isHidden = !result.text.isEmpty
        }
        isUpdating = false
    }

    @objc func markdownBold(_ sender: Any?) { applyFormat(.bold) }
    @objc func markdownItalic(_ sender: Any?) { applyFormat(.italic) }
    @objc func markdownUnderline(_ sender: Any?) { applyFormat(.underline) }
    @objc func markdownInlineCode(_ sender: Any?) { applyFormat(.inlineCode) }
    @objc func markdownInlineMath(_ sender: Any?) { applyFormat(.inlineMath) }
    @objc func markdownStrike(_ sender: Any?) { applyFormat(.strike) }
    @objc func markdownHTMLComment(_ sender: Any?) { applyFormat(.htmlComment) }
    @objc func markdownLink(_ sender: Any?) { applyFormat(.link) }
    @objc func markdownSave(_ sender: Any?) { coordinator?.parent.onSaveShortcut() }
    @objc func markdownApply(_ sender: Any?) { coordinator?.parent.onApplyShortcut() }
    @objc func markdownFitToContent(_ sender: Any?) { coordinator?.parent.onFitToContent() }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard isEditable, window?.firstResponder == self else {
            return false
        }
        if let action = item.action {
            let markdownActions: [Selector] = [
                #selector(markdownBold(_:)),
                #selector(markdownItalic(_:)),
                #selector(markdownUnderline(_:)),
                #selector(markdownInlineCode(_:)),
                #selector(markdownInlineMath(_:)),
                #selector(markdownStrike(_:)),
                #selector(markdownHTMLComment(_:)),
                #selector(markdownLink(_:)),
                #selector(markdownSave(_:)),
                #selector(markdownApply(_:)),
                #selector(markdownFitToContent(_:))
            ]
            if markdownActions.contains(action) {
                return true
            }
        }
        return super.validateUserInterfaceItem(item)
    }
}

final class PlaceholderLabel: NSTextField {
    var paragraphStyle: NSParagraphStyle = .default
    var baselineOffset: CGFloat = 0

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        stringValue = ""
        font = .systemFont(ofSize: 14)
        textColor = .placeholderTextColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    var string: String {
        get { stringValue }
        set {
            stringValue = newValue
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? .systemFont(ofSize: 14),
                .foregroundColor: textColor ?? .placeholderTextColor,
                .paragraphStyle: paragraphStyle,
                .baselineOffset: baselineOffset
            ]
            attributedStringValue = NSAttributedString(string: newValue, attributes: attributes)
        }
    }
}

extension MacMarkdownHighlighter {
    static func applyMarkdownHighlighting(to textView: NSTextView, lineHeightMultiple: CGFloat) {
        guard let textStorage = textView.textStorage else { return }
        let selectedRanges = textView.selectedRanges

        let text = textView.string ?? ""
        let fontSize = textView.font?.pointSize ?? CGFloat(SettingsStore.shared.macEditorFontSize)

        let bodyFont = bodyFont(size: fontSize)
        let paraStyle = paragraphStyle(size: fontSize, multiple: lineHeightMultiple)
        let baselineOff = baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: bodyFont,
            .foregroundColor: NSColor(DS.textBody),
            .paragraphStyle: paraStyle,
            .baselineOffset: baselineOff
        ], range: fullRange)

        let spans = highlight(text)
        for span in spans {
            let attrs = attributes(for: span.role, fontSize: fontSize)
            var merged = attrs
            if merged[.paragraphStyle] == nil {
                merged[.paragraphStyle] = paraStyle
            }
            if merged[.baselineOffset] == nil {
                merged[.baselineOffset] = baselineOff
            }
            textStorage.addAttributes(merged, range: span.range)
        }

        textStorage.endEditing()
        textView.selectedRanges = selectedRanges
        textView.typingAttributes = [
            .font: bodyFont,
            .foregroundColor: NSColor(DS.textBody),
            .paragraphStyle: paraStyle,
            .baselineOffset: baselineOff
        ]
    }
}

#endif
