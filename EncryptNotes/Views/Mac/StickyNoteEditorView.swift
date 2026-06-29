import Foundation
import SwiftUI
import AppKit
import Combine

#if os(macOS)

struct StickyNoteEditorView: View {
    let note: Note

    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var windowStore = MacNoteWindowStore.shared
    @StateObject private var viewModel: StickyNoteEditorViewModel

    init(note: Note) {
        self.note = note
        _viewModel = StateObject(wrappedValue: StickyNoteEditorViewModel(note: note))
    }

    var body: some View {
        VStack(spacing: 0) {
            if #available(macOS 26.0, *) {
                editorContent
                    .toolbar { toolbarContent }
                    .toolbarRole(.editor)
            } else {
                editorContent
                    .toolbar { toolbarContent }
            }
        }
        .background(DS.bg)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: viewModel.forceClose) { _, shouldClose in
            if shouldClose { StickyNoteWindowManager.shared.closeWindow(for: note.id) }
        }
    }

    private var editorContent: some View {
        MacTextView(
            text: $viewModel.text,
            placeholder: "开始记录...",
            fontSize: CGFloat(settings.macEditorFontSize),
            autoFocus: true,
            onChange: { viewModel.textDidChange($0) },
            onSaveShortcut: { viewModel.saveImmediately() },
            onApplyShortcut: { viewModel.saveImmediately() },
            onFitToContent: { viewModel.fitWindowToContent() }
        )
        .padding(.horizontal, MacStickyEditorLayout.editorHorizontalInset)
        .padding(.bottom, MacStickyEditorLayout.editorBottomInset)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button {
                    copyContent()
                } label: { Label("复制全文", systemImage: "doc.on.doc") }
                Divider()
                Button {
                    viewModel.fitWindowToContent()
                } label: { Label("适应内容", systemImage: "arrow.up.left.and.arrow.down.right") }
                Divider()
                if let state = windowStore.windowState(for: note.id), state.isPinned {
                    Button {
                        windowStore.setPinned(for: note.id, isPinned: false)
                        StickyNoteWindowManager.shared.updateWindowLevel(for: note.id, isPinned: false)
                    } label: { Label("取消置顶", systemImage: "pin.slash") }
                } else {
                    Button {
                        windowStore.setPinned(for: note.id, isPinned: true)
                        StickyNoteWindowManager.shared.updateWindowLevel(for: note.id, isPinned: true)
                    } label: { Label("置顶", systemImage: "pin") }
                }
                Divider()
                Button(role: .destructive) {
                    viewModel.deleteNote()
                } label: { Label("删除", systemImage: "trash") }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func copyContent() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(viewModel.text, forType: .string)
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
    @Published var text: String
    @Published var forceClose = false

    let note: Note
    private var saveTask: Task<Void, Never>?
    private var didAppear = false

    init(note: Note) {
        self.note = note
        _text = Published(initialValue: note.body)
    }

    func onAppear() {
        guard !didAppear else { return }
        didAppear = true
    }

    func onDisappear() {
        saveTask?.cancel()
        commitSave()
    }

    func textDidChange(_ newText: String) {
        text = newText
        debouncedSave()
    }

    func saveImmediately() {
        saveTask?.cancel()
        commitSave()
    }

    func fitWindowToContent() {
        StickyNoteWindowManager.shared.fitWindowToContent(
            noteId: note.id,
            text: text,
            fontSize: CGFloat(SettingsStore.shared.macEditorFontSize)
        )
    }

    func deleteNote() {
        saveTask?.cancel()
        Task {
            do {
                try await VaultStore.shared.deleteNote(note)
                forceClose = true
            } catch {}
        }
    }

    private func debouncedSave() {
        saveTask?.cancel()
        let noteCopy = note
        let snapshot = text
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.commitSaveSnapshot(snapshot, note: noteCopy)
        }
    }

    private func commitSave() {
        commitSaveSnapshot(text, note: note)
    }

    private nonisolated func commitSaveSnapshot(_ snapshot: String, note: Note) {
        Task { @MainActor in
            _ = try? await VaultStore.shared.updateNote(note, body: snapshot)
        }
    }
}

// MARK: - MacTextView

struct MacTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat
    let autoFocus: Bool
    let onChange: (String) -> Void
    let onSaveShortcut: () -> Void
    let onApplyShortcut: () -> Void
    let onFitToContent: () -> Void

    init(
        text: Binding<String>,
        placeholder: String,
        fontSize: CGFloat,
        autoFocus: Bool = true,
        onChange: @escaping (String) -> Void,
        onSaveShortcut: @escaping () -> Void,
        onApplyShortcut: @escaping () -> Void,
        onFitToContent: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.autoFocus = autoFocus
        self.onChange = onChange
        self.onSaveShortcut = onSaveShortcut
        self.onApplyShortcut = onApplyShortcut
        self.onFitToContent = onFitToContent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> AutoFocusTextView {
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

        return textView
    }

    func updateNSView(_ nsView: AutoFocusTextView, context: Context) {
        context.coordinator.parent = self
        if nsView.isUpdating { return }
        nsView.isUpdating = true
        defer { nsView.isUpdating = false }

        if nsView.string != text {
            let selectedRanges = nsView.selectedRanges
            let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: text, fontSize: fontSize)
            nsView.textStorage?.setAttributedString(attributed)
            nsView.selectedRanges = selectedRanges
        } else {
            let paraStyle = MacMarkdownHighlighter.paragraphStyle(size: fontSize)
            let bodyFont = MacMarkdownHighlighter.bodyFont(size: fontSize)
            let baselineOff = MacMarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont)
            let fullRange = NSRange(location: 0, length: (nsView.string as NSString).length)
            if fullRange.length > 0 {
                nsView.textStorage?.addAttributes([
                    .font: bodyFont,
                    .paragraphStyle: paraStyle,
                    .baselineOffset: baselineOff
                ], range: fullRange)
                MacMarkdownHighlighter.applyMarkdownHighlighting(to: nsView)
            }
        }

        nsView.textContainerInset = MacStickyEditorLayout.textContainerInset(fontSize: fontSize)

        if nsView.placeholderLabel.string != placeholder {
            nsView.placeholderLabel.string = placeholder
        }
        updatePlaceholderVisibility(nsView)
        updatePlaceholderStyle(nsView, fontSize: fontSize)

        if autoFocus, nsView.window != nil, !nsView.didInitialFocus {
            nsView.didInitialFocus = true
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    private func updatePlaceholderStyle(_ textView: AutoFocusTextView, fontSize: CGFloat) {
        let bodyFont = MacMarkdownHighlighter.bodyFont(size: fontSize)
        let paraStyle = MacMarkdownHighlighter.paragraphStyle(size: fontSize)
        let baselineOff = MacMarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont)
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
            let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: text, fontSize: fontSize)
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = Self.typingAttributes(fontSize: fontSize)
            lastText = text
        }

        static func typingAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
            let bodyFont = MacMarkdownHighlighter.bodyFont(size: fontSize)
            return [
                .font: bodyFont,
                .foregroundColor: NSColor(DS.textBody),
                .paragraphStyle: MacMarkdownHighlighter.paragraphStyle(size: fontSize),
                .baselineOffset: MacMarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont)
            ]
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? AutoFocusTextView, !textView.isUpdating else { return }
            textView.isUpdating = true
            let newText = textView.string ?? ""
            parent.onChange(newText)
            lastText = newText
            MacMarkdownHighlighter.applyMarkdownHighlighting(to: textView)
            textView.typingAttributes = Self.typingAttributes(fontSize: parent.fontSize)
            parent.updatePlaceholderVisibility(textView)
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
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
        let ctrlOnly = ctrl && !cmd && !opt && !shift
        let ctrlShiftOnly = ctrl && shift && !cmd && !opt
        let cmdOptOnly = cmd && opt && !ctrl && !shift

        if cmdOnly && chars == "b" {
            applyFormat(.bold); return
        }
        if cmdOnly && chars == "i" {
            applyFormat(.italic); return
        }
        if cmdOnly && chars == "u" {
            applyFormat(.underline); return
        }
        if cmdOnly && chars == "k" {
            applyFormat(.link); return
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
        if ctrlOnly && chars == "`" {
            applyFormat(.inlineCode); return
        }
        if ctrlOnly && chars == "m" {
            applyFormat(.inlineMath); return
        }
        if ctrlShiftOnly && chars == "`" {
            applyFormat(.strike); return
        }
        if ctrlOnly && chars == "-" {
            applyFormat(.htmlComment); return
        }

        super.keyDown(with: event)
    }

    private func applyFormat(_ command: MacMarkdownFormatCommand) {
        let currentText = self.string ?? ""
        let selection = self.selectedRange()
        let result = MacMarkdownFormatter.apply(command: command, to: currentText, selection: selection)

        isUpdating = true
        let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: result.text, fontSize: (coordinator?.parent.fontSize) ?? 14)
        textStorage?.setAttributedString(attributed)
        self.setSelectedRange(result.selection)
        didChangeText()
        coordinator?.parent.onChange(result.text)
        MacMarkdownHighlighter.applyMarkdownHighlighting(to: self)
        typingAttributes = MacTextView.Coordinator.typingAttributes(fontSize: (coordinator?.parent.fontSize) ?? 14)
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
    static func applyMarkdownHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let selectedRanges = textView.selectedRanges

        let text = textView.string ?? ""
        let fontSize = textView.font?.pointSize ?? CGFloat(SettingsStore.shared.macEditorFontSize)

        let bodyFont = bodyFont(size: fontSize)
        let paraStyle = paragraphStyle(size: fontSize)
        let baselineOff = baselineOffset(size: fontSize, font: bodyFont)

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
