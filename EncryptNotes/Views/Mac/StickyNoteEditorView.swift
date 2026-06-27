import Foundation
import SwiftUI
import AppKit
import Combine

struct StickyNoteEditorView: View {
    @StateObject private var viewModel: StickyNoteEditorViewModel
    @ObservedObject private var syncStore = SyncStatusStore.shared

    private enum Layout {
        static let editorHorizontalInset = DS.s4
        static let editorBottomInset: CGFloat = 28
    }

    init(note: Note, isPreview: Bool = false) {
        _viewModel = StateObject(wrappedValue: StickyNoteEditorViewModel(note: note, isPreview: isPreview))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MacTextView(
                text: $viewModel.text,
                contentInsets: NSEdgeInsets(
                    top: 0,
                    left: Layout.editorHorizontalInset,
                    bottom: Layout.editorBottomInset,
                    right: Layout.editorHorizontalInset
                )
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .ignoresSafeArea()
        .dsMacStickyToolbarScrollEdge()
        .navigationTitle("")
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

@MainActor
final class StickyNoteEditorViewModel: ObservableObject {
    @Published var note: Note
    @Published var text: String
    @Published var isPinned: Bool
    @Published var showingDeleteConfirmation = false
    @Published var didCopy = false

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

    var windowTitle: String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return firstLine?.isEmpty == false ? firstLine! : ""
    }

    init(note: Note, isPreview: Bool = false) {
        self.note = note
        self.text = note.body
        self.isPreview = isPreview
        self.wasInitiallyEmpty = note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.isPinned = windowStore.windowState(for: note.id)?.isPinned ?? true

        $text
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if !self.isPreview {
                    StickyNoteWindowManager.shared.updateWindowTitle(for: self.note.id, title: self.windowTitle)
                }
                self.save()
            }
            .store(in: &cancellables)

        if !isPreview {
            StickyNoteWindowManager.shared.updateWindowTitle(for: note.id, title: windowTitle)
        }

        $isPinned
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.windowStore.setPinned(newValue, for: self.note.id)
                StickyNoteWindowManager.shared.updateWindowLevel(for: self.note.id, isPinned: newValue)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .macTextViewDidEndEditing)
            .sink { [weak self] _ in
                self?.saveImmediately()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .macWindowWillClose)
            .sink { [weak self] notification in
                guard let self = self,
                      let noteId = notification.userInfo?["noteId"] as? String,
                      noteId == self.note.id else { return }
                self.handleWindowWillClose()
            }
            .store(in: &cancellables)
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
                StickyNoteWindowManager.shared.closeWindow(for: note.id)
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    func save() {
        guard !isPreview else {
            note.body = text
            syncStore.setSaved()
            return
        }

        guard text != note.body else {
            syncStore.setSaved()
            return
        }

        saveTask?.cancel()

        syncStore.setSyncing()
        let bodyToSave = text
        let noteToUpdate = note

        saveTask = Task {
            do {
                try await vaultStore.updateNote(noteToUpdate, body: bodyToSave)
                if let updatedNote = vaultStore.readableNotes.first(where: { $0.id == noteToUpdate.id }) {
                    note = updatedNote
                }
                syncStore.setSaved()
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    func saveImmediately() {
        saveTask?.cancel()
        save()
    }

    private func handleWindowWillClose() {
        saveTask?.cancel()

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

        Task {
            do {
                try await vaultStore.discardEmptyNote(note)
                syncStore.setSaved()
                StickyNoteWindowManager.shared.closeWindow(for: note.id)
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

extension Notification.Name {
    static let macTextViewDidEndEditing = Notification.Name("macTextViewDidEndEditing")
    static let macWindowWillClose = Notification.Name("macWindowWillClose")
}

private final class AutoFocusTextView: NSTextView {
    var placeholder: String = "随便写点什么吧"
    private let placeholderColor = NSColor(DS.textSubtle)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            if window.firstResponder != self {
                window.makeFirstResponder(self)
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: MacTextViewMetrics.font,
            .foregroundColor: placeholderColor,
            .paragraphStyle: paragraphStyle
        ]

        let inset = textContainerInset
        let drawRect = bounds.insetBy(dx: inset.width + 4, dy: inset.height)
        (placeholder as NSString).draw(in: drawRect, withAttributes: attrs)
    }
}

private enum MacTextViewMetrics {
    static let font = NSFont.systemFont(ofSize: 14)
}

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
        applyToolbarTopInset()
    }

    private func applyToolbarTopInset() {
        let top: CGFloat
        if let window = window {
            top = max(0, window.frame.height - window.contentLayoutRect.height)
        } else {
            top = baseInsets.top
        }
        let target = NSEdgeInsets(top: top, left: baseInsets.left, bottom: baseInsets.bottom, right: baseInsets.right)
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
    var placeholder: String = "随便写点什么吧"
    var contentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

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
        scrollView.baseInsets = contentInsets

        let textView = AutoFocusTextView()
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = MacTextViewMetrics.font
        textView.textColor = NSColor(DS.textBody)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        Self.applyParagraphStyle(to: textView)
        textView.string = text
        Self.applyTextAttributes(to: textView)

        context.coordinator.textView = textView

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let scrollView = nsView as? ToolbarInsetScrollView,
              let textView = scrollView.documentView as? AutoFocusTextView else { return }

        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.baseInsets = contentInsets
        textView.placeholder = placeholder

        if textView.string != text && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            textView.string = text
            Self.applyParagraphStyle(to: textView)
            Self.applyTextAttributes(to: textView)
            context.coordinator.isUpdating = false
        }
        textView.needsDisplay = true
    }

    private static func applyParagraphStyle(to textView: NSTextView) {
        let paragraphStyle = NSMutableParagraphStyle()
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: MacTextViewMetrics.font,
            .foregroundColor: NSColor(DS.textBody),
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func applyTextAttributes(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let range = NSRange(location: 0, length: textStorage.length)
        guard range.length > 0 else { return }

        textStorage.addAttributes(textView.typingAttributes, range: range)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTextView
        weak var textView: NSTextView?
        var isUpdating = false

        init(_ parent: MacTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isUpdating else { return }
            isUpdating = true
            parent.text = textView.string
            isUpdating = false
            textView.needsDisplay = true
        }

        func textDidEndEditing(_ notification: Notification) {
            NotificationCenter.default.post(name: .macTextViewDidEndEditing, object: nil)
        }
    }
}

#if DEBUG
#Preview {
    StickyNoteEditorView(
        note: Note(
            id: "preview-sticky-note",
            vaultId: "preview-vault",
            body: "",
            createdAt: Date(timeIntervalSince1970: 1_782_532_980),
            updatedAt: Date(timeIntervalSince1970: 1_782_532_980),
            isEncrypted: false
        ),
        isPreview: true
    )
    .frame(width: 852, height: 1138)
}
#endif
