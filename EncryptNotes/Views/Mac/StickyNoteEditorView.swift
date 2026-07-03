import Foundation
import SwiftUI
import AppKit
import Combine
import Carbon
import MarkdownView
import UniformTypeIdentifiers

#if os(macOS)

private extension View {
    @ViewBuilder
    func macKeyboardShortcut(_ shortcut: MarkdownShortcut) -> some View {
        if let key = shortcut.keyEquivalent.first {
            keyboardShortcut(KeyEquivalent(key), modifiers: SwiftUI.EventModifiers(carbonModifiers: shortcut.modifiers))
        } else {
            self
        }
    }
}

private extension SwiftUI.EventModifiers {
    init(carbonModifiers: UInt32) {
        var modifiers: SwiftUI.EventModifiers = []
        if carbonModifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        self = modifiers
    }
}

struct StickyNoteEditorView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var shortcutStore = ShortcutStore.shared
    @ObservedObject private var syncStore = SyncStatusStore.shared
    @StateObject private var viewModel: StickyNoteEditorViewModel
    @State private var isToolbarHovering = false
    @State private var isFindBarVisible = false
    @State private var isMarkdownPreviewing = false

    init(note: Note, isPreview: Bool = false, startsLocked: Bool = false, initialKeyIssue: Error? = nil) {
        _viewModel = StateObject(wrappedValue: StickyNoteEditorViewModel(
            note: note,
            isPreview: isPreview,
            startsLocked: startsLocked,
            initialKeyIssue: initialKeyIssue
        ))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isMarkdownPreviewing {
                MacMarkdownPreview(
                    text: viewModel.text,
                    fontSize: CGFloat(settings.macEditorFontSize),
                    lineHeightMultiple: CGFloat(settings.macEditorLineHeightMultiple)
                )
                .background(MacMarkdownPreviewShortcutMonitor(
                    noteId: viewModel.note.id,
                    onCopy: { viewModel.copyNoteText() },
                    onTogglePreview: { toggleMarkdownPreview() }
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MacTextView(
                    text: $viewModel.text,
                    placeholder: "随便写点什么吧",
                    fontSize: CGFloat(settings.macEditorFontSize),
                    lineHeightMultiple: CGFloat(settings.macEditorLineHeightMultiple),
                    autoFocus: true,
                    isEditable: !viewModel.isContentLocked,
                    onChange: { viewModel.textDidChange($0) },
                    onSaveShortcut: { viewModel.saveImmediately() },
                    onApplyShortcut: { viewModel.saveImmediately() },
                    onFitToContent: { viewModel.fitWindowToContent() },
                    onCopyShortcut: { viewModel.copyNoteText() },
                    onFindShortcut: { toggleFindInterface() },
                    onToggleMarkdownPreview: { toggleMarkdownPreview() },
                    onIncreaseFontSize: { adjustFontSize(by: 1) },
                    onDecreaseFontSize: { adjustFontSize(by: -1) },
                    onFindVisibilityChange: { isVisible in
                        isFindBarVisible = isVisible
                        updateSystemToolbarBackground(
                            isActive: isVisible || isToolbarHovering,
                            showsSeparator: isVisible
                        )
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 0) {
                MacToolbarHoverRegion { hovering in
                    setToolbarHovering(hovering)
                }
                .frame(height: MacStickyEditorLayout.toolbarHoverRegionHeight)

                Spacer(minLength: 0)
            }
            .allowsHitTesting(true)

            if viewModel.isContentLocked {
                lockedContentOverlay
            }

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
        .onAppear { viewModel.presentInitialKeyIssueIfNeeded() }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: viewModel.forceClose) { _, shouldClose in
            if shouldClose {
                StickyNoteWindowManager.shared.closeWindow(for: viewModel.note.id)
            }
        }
        .onChange(of: viewModel.isContentLocked) { _, locked in
            if locked {
                isMarkdownPreviewing = false
                hideFindInterface()
            }
        }
        .onChange(of: viewModel.isEncryptionToggling) { _, isToggling in
            if isToggling {
                isMarkdownPreviewing = false
            }
        }
        .toolbar {
            ToolbarSpacer()
            ToolbarItem(placement: .primaryAction) {
                Button(action: { toggleMarkdownPreview() }) {
                    Label(
                        isMarkdownPreviewing ? "返回编辑" : "预览",
                        systemImage: isMarkdownPreviewing ? "stop.fill" : "play.fill"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: DS.macToolbarIconWidth)
                }
                .disabled(viewModel.isContentLocked || viewModel.isEncryptionToggling)
                .macKeyboardShortcut(markdownPreviewShortcut)
                .help(isMarkdownPreviewing ? "返回编辑" : "Markdown 预览")
            }
            ToolbarSpacer()
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.note.isEncrypted {
                    Button(action: { toggleEncryptionLock() }) {
                        Label(
                            viewModel.isContentLocked ? "解锁" : "上锁",
                            systemImage: viewModel.isContentLocked ? "lock.fill" : "lock.open.fill"
                        )
                        .labelStyle(.iconOnly)
                        .frame(width: DS.macToolbarIconWidth)
                    }
                    .disabled(viewModel.isEncryptionToggling)
                    .help(viewModel.isContentLocked ? "解锁" : "上锁")
                }

                Button(action: { viewModel.copyNoteText() }) {
                    Label(
                        viewModel.didCopy ? "已复制" : "复制",
                        systemImage: viewModel.didCopy ? "checkmark" : "square.on.square"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: DS.macToolbarIconWidth)
                }
                .disabled(viewModel.isContentLocked)
                .help(viewModel.didCopy ? "已复制" : "复制")

                Menu {
                    Button(action: { viewModel.fitWindowToContent() }) {
                        Label("适应内容", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(viewModel.isContentLocked)
                    
                    Button(action: { toggleFindInterface() }) {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(viewModel.isContentLocked || isMarkdownPreviewing)

                    if viewModel.note.isEncrypted {
                        Divider()

                        Button(action: { viewModel.decryptPermanently() }) {
                            Label("转为明文笔记", systemImage: "lock.open")
                        }
                        .disabled(viewModel.isContentLocked || viewModel.isEncryptionToggling)
                    } else {
                        Divider()

                        Button(action: { viewModel.encryptAndLock() }) {
                            Label("转为加密笔记", systemImage: "lock")
                        }
                        .disabled(viewModel.isContentLocked || viewModel.isEncryptionToggling)
                    }

                    Divider()

                    Button(role: .destructive, action: { viewModel.deleteNote() }) {
                        Label("移到回收站", systemImage: "trash")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: DS.macToolbarIconWidth)
                }
                .disabled(viewModel.isContentLocked)
                .menuIndicator(.hidden)
                .help("更多")
            }
            ToolbarSpacer()
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
        .alert("需要密钥", isPresented: $viewModel.showingKeyIssueAlert) {
            Button("打开密钥设置") {
                MacMenuBarController.shared.openSettingsWindow(selectedTab: .key)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(viewModel.keyIssueMessage)
        }
    }

    private var lockedContentOverlay: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)

            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(DS.textSubtle)
                .accessibilityLabel("已上锁")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func adjustFontSize(by delta: Double) {
        settings.macEditorFontSize = SettingsStore.clampedFontSize(settings.macEditorFontSize + delta)
    }

    private var markdownPreviewShortcut: MarkdownShortcut {
        shortcutStore.shortcut(for: .markdownPreview)
    }

    private func toggleMarkdownPreview() {
        guard !viewModel.isContentLocked, !viewModel.isEncryptionToggling else { return }
        if isMarkdownPreviewing {
            isMarkdownPreviewing = false
        } else {
            viewModel.saveImmediately()
            hideFindInterface()
            isMarkdownPreviewing = true
        }
    }

    private func toggleEncryptionLock() {
        if isMarkdownPreviewing {
            isMarkdownPreviewing = false
        }
        viewModel.toggleEncryptionLock()
    }

    private func setToolbarHovering(_ hovering: Bool) {
        guard isToolbarHovering != hovering else { return }
        isToolbarHovering = hovering
        updateSystemToolbarBackground(
            isActive: hovering || isFindBarVisible,
            showsSeparator: isFindBarVisible
        )
    }

    private func updateSystemToolbarBackground(isActive: Bool, showsSeparator: Bool) {
        guard let window = editorWindow() else { return }
        AutoFocusTextView.setFindToolbarActive(isActive, showsSeparator: showsSeparator, in: window)
    }

    private func toggleFindInterface() {
        guard !viewModel.isContentLocked, !isMarkdownPreviewing else { return }
        guard let window = NSApp.keyWindow else { return }
        guard let textView = editorTextView(in: window) else {
            let sender = FindPanelActionSender(tag: NSTextFinder.Action.showFindInterface.rawValue)
            AutoFocusTextView.setFindToolbarActive(true, showsSeparator: true, in: window)
            NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
            return
        }

        let scrollView = textView.enclosingScrollView as? ToolbarInsetScrollView
        let action: NSTextFinder.Action = scrollView?.isFindBarVisible == true
            ? .hideFindInterface
            : .showFindInterface
        let sender = FindPanelActionSender(tag: action.rawValue)

        AutoFocusTextView.setFindToolbarActive(
            action == .showFindInterface,
            showsSeparator: action == .showFindInterface,
            in: window
        )
        textView.performFindPanelAction(sender)
        DispatchQueue.main.async {
            scrollView?.syncFindToolbarAppearance()
        }
    }

    private func hideFindInterface() {
        guard let window = editorWindow(),
              let textView = editorTextView(in: window) else { return }
        let sender = FindPanelActionSender(tag: NSTextFinder.Action.hideFindInterface.rawValue)
        AutoFocusTextView.setFindToolbarActive(false, showsSeparator: false, in: window)
        textView.performFindPanelAction(sender)
        (textView.enclosingScrollView as? ToolbarInsetScrollView)?.syncFindToolbarAppearance()
        isFindBarVisible = false
    }

    private func editorTextView(in window: NSWindow) -> AutoFocusTextView? {
        if let textView = window.firstResponder as? AutoFocusTextView {
            return textView
        }
        return window.contentView?.firstDescendant(of: AutoFocusTextView.self)
    }

    private func editorWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == viewModel.note.id } ?? NSApp.keyWindow
    }
}

private final class FindPanelActionSender: NSObject {
    @objc let tag: Int

    init(tag: Int) {
        self.tag = tag
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}

enum MacStickyEditorLayout {
    static let editorHorizontalInset = DS.s4
    static let editorBottomInset: CGFloat = 28
    static let widthMultiplier: CGFloat = 30
    static let glyphSafetyInset: CGFloat = 3
    static let toolbarHoverRegionHeight: CGFloat = 72

    static func horizontalPadding(textContainerInsetWidth: CGFloat) -> CGFloat {
        textContainerInsetWidth * 2 + 8
    }

    static func textContainerInset(fontSize: CGFloat) -> NSSize {
        let baseInset = MacMarkdownHighlighter.textContainerInset(size: fontSize)
        return NSSize(
            width: baseInset.width + editorHorizontalInset,
            height: baseInset.height
        )
    }
}

private struct MacMarkdownPreview: View {
    let text: String
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    @State private var titlebarHeight: CGFloat = MacStickyEditorLayout.toolbarHoverRegionHeight

    private var previewFont: Font {
        .system(size: fontSize)
    }

    private var codeFont: Font {
        .system(size: max(11, fontSize - 1), design: .monospaced)
    }

    private var verticalSpacing: CGFloat {
        max(8, fontSize * (lineHeightMultiple - 0.7))
    }

    private var textInset: NSSize {
        MacStickyEditorLayout.textContainerInset(fontSize: fontSize)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("随便写点什么吧")
                        .font(previewFont)
                        .foregroundColor(Color(nsColor: .placeholderTextColor))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownView(text)
                        .font(previewFont, for: .body)
                        .font(codeFont, for: .codeBlock)
                        .markdownComponentSpacing(verticalSpacing)
                        .markdownMathRenderingEnabled()
                        .foregroundStyle(Color(nsColor: .textColor))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, titlebarHeight + textInset.height)
            .padding(.horizontal, textInset.width)
            .padding(.bottom, MacStickyEditorLayout.editorBottomInset)
        }
        .scrollIndicators(.hidden)
        .background(MacTitlebarHeightReader(height: $titlebarHeight))
    }
}

private struct MacTitlebarHeightReader: NSViewRepresentable {
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> MacTitlebarHeightProbeView {
        let view = MacTitlebarHeightProbeView()
        view.onHeightChange = { height = $0 }
        return view
    }

    func updateNSView(_ nsView: MacTitlebarHeightProbeView, context: Context) {
        nsView.onHeightChange = { height = $0 }
        nsView.updateHeight()
    }
}

private final class MacTitlebarHeightProbeView: NSView {
    var onHeightChange: ((CGFloat) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHeight()
    }

    override func layout() {
        super.layout()
        updateHeight()
    }

    func updateHeight() {
        guard let window else { return }
        let height = max(0, window.frame.height - window.contentLayoutRect.height)
        onHeightChange?(height)
    }
}

private struct MacMarkdownPreviewShortcutMonitor: NSViewRepresentable {
    let noteId: String
    let onCopy: () -> Void
    let onTogglePreview: () -> Void

    func makeNSView(context: Context) -> MacMarkdownPreviewShortcutMonitorView {
        let view = MacMarkdownPreviewShortcutMonitorView()
        view.noteId = noteId
        view.onCopy = onCopy
        view.onTogglePreview = onTogglePreview
        return view
    }

    func updateNSView(_ nsView: MacMarkdownPreviewShortcutMonitorView, context: Context) {
        nsView.noteId = noteId
        nsView.onCopy = onCopy
        nsView.onTogglePreview = onTogglePreview
    }

    static func dismantleNSView(_ nsView: MacMarkdownPreviewShortcutMonitorView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

private final class MacMarkdownPreviewShortcutMonitorView: NSView {
    var noteId = ""
    var onCopy: (() -> Void)?
    var onTogglePreview: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else {
            installMonitorIfNeeded()
        }
    }

    deinit {
        removeMonitor()
    }

    func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isEventInCurrentNoteWindow(event) else { return event }
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return event }

        let flags = event.modifierFlags
        let cmd = flags.contains(.command)
        let ctrl = flags.contains(.control)
        let opt = flags.contains(.option)

        if cmd, !ctrl, !opt, chars.lowercased() == "c" {
            onCopy?()
            return nil
        }

        if let action = ShortcutStore.shared.editorAction(matching: event) {
            switch action {
            case .markdownPreview:
                onTogglePreview?()
                return nil
            }
        }

        return event
    }

    private func isEventInCurrentNoteWindow(_ event: NSEvent) -> Bool {
        if let eventWindow = event.window {
            return eventWindow === window || eventWindow.identifier?.rawValue == noteId
        }
        return NSApp.keyWindow === window || NSApp.keyWindow?.identifier?.rawValue == noteId
    }
}

private struct MacToolbarHoverRegion: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> ToolbarHoverTrackingView {
        let view = ToolbarHoverTrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: ToolbarHoverTrackingView, context: Context) {
        nsView.onHover = onHover
    }
}

private final class ToolbarHoverTrackingView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var pendingHoverOn: DispatchWorkItem?
    private var pendingHoverOff: DispatchWorkItem?
    private var isHovering = false
    private var mouseMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaRef = area
        addTrackingArea(area)
        updateHoverForCurrentMouseLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(withWindowPoint: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(withWindowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        scheduleHoverOff()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            pendingHoverOn?.cancel()
            pendingHoverOn = nil
            pendingHoverOff?.cancel()
            pendingHoverOff = nil
            removeMouseMonitor()
            setHovering(false)
        } else {
            installMouseMonitor()
            DispatchQueue.main.async { [weak self] in
                self?.updateHoverForCurrentMouseLocation()
            }
        }
    }

    deinit {
        removeMouseMonitor()
    }

    private func scheduleHoverOn() {
        pendingHoverOff?.cancel()
        pendingHoverOff = nil
        pendingHoverOn?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.containsCurrentMouseLocation() else { return }
            self.setHovering(true)
        }
        pendingHoverOn = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
    }

    private func showHoverImmediately() {
        pendingHoverOff?.cancel()
        pendingHoverOff = nil
        pendingHoverOn?.cancel()
        pendingHoverOn = nil
        setHovering(true)
    }

    private func scheduleHoverOff() {
        pendingHoverOn?.cancel()
        pendingHoverOn = nil
        pendingHoverOff?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.containsCurrentMouseLocation() else { return }
            self.setHovering(false)
        }
        pendingHoverOff = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func containsCurrentMouseLocation() -> Bool {
        guard let window else { return false }
        let pointInWindow = window.mouseLocationOutsideOfEventStream
        let pointInView = convert(pointInWindow, from: nil)
        return bounds.contains(pointInView)
    }

    private func installMouseMonitor() {
        removeMouseMonitor()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            self?.updateHover(with: event)
            return event
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func updateHoverForCurrentMouseLocation() {
        guard let window else { return }
        updateHover(withWindowPoint: window.mouseLocationOutsideOfEventStream)
    }

    private func updateHover(with event: NSEvent) {
        guard let window, event.window == window else { return }
        updateHover(withWindowPoint: event.locationInWindow)
    }

    private func updateHover(withWindowPoint pointInWindow: NSPoint) {
        let pointInView = convert(pointInWindow, from: nil)
        if bounds.contains(pointInView) {
            showHoverImmediately()
        } else if isHovering {
            scheduleHoverOff()
        }
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        onHover?(hovering)
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
    @Published var isContentLocked = false
    @Published var ciphertextPreview = ""
    @Published var isEncryptionToggling = false
    @Published var showingKeyIssueAlert = false
    @Published var keyIssueMessage = "请前往密钥设置处理。"

    private let vaultStore = VaultStore.shared
    private let windowStore = MacNoteWindowStore.shared
    private let settings = SettingsStore.shared
    private let syncStore = SyncStatusStore.shared
    private let aiTitleService = MacAITitleService()
    private let isPreview: Bool
    private var saveTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var initialKeyIssue: Error?

    var isContentEmpty: Bool {
        let body = isContentLocked ? note.body : text
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(note: Note, isPreview: Bool = false, startsLocked: Bool = false, initialKeyIssue: Error? = nil) {
        self.note = note
        self.text = note.body
        self.isPreview = isPreview
        self.isPinned = windowStore.windowState(for: note.id)?.isPinned ?? true
        self.isContentLocked = startsLocked
        self.initialKeyIssue = initialKeyIssue

        $isPinned
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.windowStore.setPinned(newValue, for: self.note.id)
                StickyNoteWindowManager.shared.updateWindowLevel(for: self.note.id, isPinned: newValue)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sealNoteLockEncryptedNote)
            .sink { [weak self] notification in
                guard let self else { return }
                if let noteId = notification.object as? String, noteId != self.note.id { return }
                self.temporarilyLockContent()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sealNotePresentKeyIssue)
            .sink { [weak self] notification in
                guard let self else { return }
                guard let noteId = notification.object as? String, noteId == self.note.id else { return }
                let error = notification.userInfo?["error"] as? Error ?? CryptoError.keyNotFound
                self.presentKeyIssue(error)
            }
            .store(in: &cancellables)
    }

    func presentInitialKeyIssueIfNeeded() {
        guard let error = initialKeyIssue else { return }
        initialKeyIssue = nil
        presentKeyIssue(error)
    }

    func onDisappear() {
        guard !forceClose else { return }
        handleWindowWillClose()
    }

    func textDidChange(_ newText: String) {
        guard !isContentLocked else { return }
        text = newText
        debouncedSave()
    }

    func copyNoteText() {
        guard !isContentLocked else { return }
        let copiedText = settings.copyAddsParagraphSpacing
            ? MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: text)
            : text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedText, forType: .string)

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

    func toggleEncryptionLock() {
        guard !isEncryptionToggling else { return }
        if isContentLocked {
            unlockEncryptedContent()
        } else {
            temporarilyLockContent()
        }
    }

    func deleteNote() {
        if isContentEmpty {
            discardEmptyNoteAndClose(body: text)
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
        guard !isContentLocked else {
            syncStore.setSaved()
            return
        }
        saveTask?.cancel()
        save()
    }

    func fitWindowToContent() {
        guard !isContentLocked else { return }
        StickyNoteWindowManager.shared.fitWindowToContent(
            noteId: note.id,
            text: text,
            fontSize: CGFloat(SettingsStore.shared.macEditorFontSize)
        )
    }

    func decryptPermanently() {
        guard note.isEncrypted, !isContentLocked else { return }
        saveTask?.cancel()
        isEncryptionToggling = true
        syncStore.setSyncing()
        let noteToDecrypt = note

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isEncryptionToggling = false }
            do {
                let updatedNote = try await self.vaultStore.decryptNotePermanently(noteToDecrypt)
                self.note = updatedNote
                self.text = updatedNote.body
                self.isContentLocked = false
                self.syncStore.setSaved()
            } catch {
                if self.isKeyIssue(error) {
                    self.presentKeyIssue(error)
                    return
                }
                self.syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    func encryptAndLock() {
        lockContent()
    }

    private func debouncedSave() {
        guard !isContentLocked else { return }
        saveTask?.cancel()

        syncStore.setSyncing()
        let bodyToSave = text
        let noteToUpdate = note

        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            _ = await self?.saveSnapshot(bodyToSave, note: noteToUpdate)
        }
    }

    private func save() {
        guard !isContentLocked else {
            syncStore.setSaved()
            return
        }
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
            _ = await saveSnapshot(bodyToSave, note: noteToUpdate)
        }
    }

    private func saveSnapshot(_ snapshot: String, note noteToUpdate: Note) async -> Bool {
        do {
            try await vaultStore.updateNote(noteToUpdate, body: snapshot)
            if let updatedNote = vaultStore.readableNotes.first(where: { $0.id == noteToUpdate.id }) {
                note = updatedNote
            }
            syncStore.setSaved()
            return true
        } catch {
            if isKeyIssue(error) {
                presentKeyIssue(error)
                return false
            }
            syncStore.setFailed(message: error.localizedDescription)
            return false
        }
    }

    private func lockContent() {
        guard !isPreview else { return }
        guard vaultStore.isKeyLoaded else {
            presentKeyIssue(CryptoError.keyNotFound)
            return
        }

        guard !note.isEncrypted else {
            temporarilyLockContent()
            return
        }

        saveTask?.cancel()
        isEncryptionToggling = true
        syncStore.setSyncing()

        let bodyToEncrypt = text
        let noteToEncrypt = note
        let start = Date()
        print("Seal Note encryption start note=\(noteToEncrypt.id) bytes=\(bodyToEncrypt.utf8.count)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isEncryptionToggling = false }
            do {
                let result = try await self.vaultStore.encryptNoteForEditing(noteToEncrypt, body: bodyToEncrypt)
                let elapsed = Date().timeIntervalSince(start) * 1000
                print("Seal Note encryption end note=\(noteToEncrypt.id) elapsed_ms=\(String(format: "%.2f", elapsed))")
                self.note = result.note
                self.ciphertextPreview = result.ciphertext
                self.text = bodyToEncrypt
                self.isContentLocked = true
                self.syncStore.setSaved()
            } catch {
                let elapsed = Date().timeIntervalSince(start) * 1000
                print("Seal Note encryption failed note=\(noteToEncrypt.id) elapsed_ms=\(String(format: "%.2f", elapsed)) error=\(error.localizedDescription)")
                if self.isKeyIssue(error) {
                    self.presentKeyIssue(error)
                    return
                }
                self.syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func temporarilyLockContent() {
        guard note.isEncrypted, !isContentLocked else { return }
        saveTask?.cancel()
        ciphertextPreview = ""
        isContentLocked = true
        syncStore.setSaved()
    }

    private func unlockEncryptedContent() {
        let noteToDecrypt = note
        let start = Date()
        isEncryptionToggling = true
        print("Seal Note decryption start note=\(noteToDecrypt.id)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isEncryptionToggling = false }
            do {
                let decrypted = try await self.vaultStore.decryptEncryptedNoteBody(noteToDecrypt)
                let elapsed = Date().timeIntervalSince(start) * 1000
                print("Seal Note decryption end note=\(noteToDecrypt.id) elapsed_ms=\(String(format: "%.2f", elapsed))")
                self.note = Note(
                    id: noteToDecrypt.id,
                    body: decrypted,
                    createdAt: noteToDecrypt.createdAt,
                    updatedAt: noteToDecrypt.updatedAt,
                    isEncrypted: true
                )
                self.ciphertextPreview = ""
                self.text = decrypted
                self.isContentLocked = false
                self.syncStore.setSaved()
            } catch {
                let elapsed = Date().timeIntervalSince(start) * 1000
                print("Seal Note decryption failed note=\(noteToDecrypt.id) elapsed_ms=\(String(format: "%.2f", elapsed)) error=\(error.localizedDescription)")
                if self.isKeyIssue(error) {
                    self.presentKeyIssue(error)
                    return
                }
                self.syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func presentKeyIssue(_ error: Error) {
        keyIssueMessage = keyIssueMessage(for: error)
        showingKeyIssueAlert = true
        syncStore.setFailed(message: keyIssueMessage)
    }

    private func isKeyIssue(_ error: Error) -> Bool {
        if error is VaultKeyFileError { return true }
        if let cryptoError = error as? CryptoError {
            switch cryptoError {
            case .keyNotFound: return true
            default: return false
            }
        }
        return false
    }

    private func keyIssueMessage(for error: Error) -> String {
        if let keyError = error as? VaultKeyFileError {
            switch keyError {
            case .fileMissing:
                return "找不到密钥。请前往密钥设置处理。"
            case .fileMoved:
                return "密钥已不在原位置。请前往密钥设置处理。"
            case .permissionDenied:
                return "无法读取密钥。请前往密钥设置处理。"
            case .invalidFile:
                return "密钥格式无效。请前往密钥设置处理。"
            case .unsupportedFileExtension:
                return "请选择有效的 Seal Note 密钥。"
            case .keyReplaced:
                return "密钥已被替换或内容被修改。请前往密钥设置处理。"
            case .keyMismatch:
                return "密钥不匹配，无法解锁当前加密笔记。请前往密钥设置处理。"
            case .keyAlreadyConfigured:
                return "已经配置了密钥引用。"
            case .encryptedNotesExist:
                return "仍有加密笔记，请先在密钥设置中处理。"
            }
        }

        return "请先前往密钥设置处理。"
    }

    private func handleWindowWillClose() {
        saveTask?.cancel()
        guard !isContentLocked else {
            syncStore.setSaved()
            return
        }
        let snapshot = text
        guard !isPreview else {
            note.body = snapshot
            syncStore.setSaved()
            return
        }

        guard settings.autoDeleteEmptyNotes && snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveAndGenerateTitleOnClose(snapshot: snapshot, canGenerateTitle: !vaultStore.hasStableTitle(for: note))
            return
        }

        discardEmptyNote(body: snapshot)
    }

    private func saveAndGenerateTitleOnClose(snapshot: String, canGenerateTitle: Bool) {
        let noteToUpdate = note
        syncStore.setSyncing()

        Task {
            let didSave: Bool
            if snapshot == noteToUpdate.body {
                syncStore.setSaved()
                didSave = true
            } else {
                didSave = await saveSnapshot(snapshot, note: noteToUpdate)
            }

            guard didSave,
                  let savedNote = vaultStore.readableNotes.first(where: { $0.id == noteToUpdate.id }) else {
                return
            }
            if canGenerateTitle {
                await generateAITitleIfNeeded(for: savedNote, body: snapshot)
            }
        }
    }

    private func generateAITitleIfNeeded(for savedNote: Note, body: String) async {
        guard settings.macAITitleEnabled else { return }
        guard syncStore.isNetworkAvailable else { return }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if settings.macAITitleSkipsMarkdownHeading,
           NoteTitleFormatter.firstNonEmptyLineIsMarkdownHeading(in: body) {
            return
        }

        let provider = settings.macAITitleProvider
        let apiKey = settings.loadMacAITitleAPIKey(for: provider)
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            let title = try await aiTitleService.generateTitle(
                for: body,
                provider: provider,
                apiKey: apiKey,
                prompt: settings.macAITitlePrompt
            )
            try await vaultStore.renameNote(savedNote, title: title)
        } catch {
            // Title generation is opportunistic; note saving must remain the source of truth.
        }
    }

    private func discardEmptyNoteAndClose(body: String) {
        guard !isPreview else {
            text = ""
            note.body = ""
            return
        }

        saveTask?.cancel()
        Task {
            do {
                try await vaultStore.discardEmptyNote(note, body: body)
                syncStore.setSaved()
                forceClose = true
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func discardEmptyNote(body: String) {
        Task {
            do {
                try await vaultStore.discardEmptyNote(note, body: body)
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
    var onFindVisibilityChange: ((Bool) -> Void)?
    private var lastFindBarVisibility: Bool?

    override var isFindBarVisible: Bool {
        didSet {
            syncFindToolbarAppearance()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyToolbarTopInset()
        syncFindToolbarAppearance()
    }

    override func layout() {
        super.layout()
        if let textView = documentView as? NSTextView {
            syncDocumentSize(textView)
        }
        applyToolbarTopInset()
        syncFindToolbarAppearance()
    }

    func syncDocumentSize(_ textView: NSTextView? = nil) {
        guard let textView = textView ?? documentView as? NSTextView else { return }
        guard let textContainer = textView.textContainer else { return }
        let width = max(1, contentView.bounds.width)
        let textWidth = max(
            1,
            width - textView.textContainerInset.width * 2 - MacStickyEditorLayout.glyphSafetyInset
        )
        textContainer.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
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

    func preservingVisibleOrigin(_ changes: () -> Void) {
        let origin = contentView.bounds.origin
        changes()
        let maxY = max(0, documentView?.bounds.height ?? 0 - contentView.bounds.height)
        let maxX = max(0, documentView?.bounds.width ?? 0 - contentView.bounds.width)
        let boundedOrigin = NSPoint(
            x: min(max(0, origin.x), maxX),
            y: min(max(0, origin.y), maxY)
        )
        contentView.scroll(to: boundedOrigin)
        reflectScrolledClipView(contentView)
    }

    func syncFindToolbarAppearance() {
        guard window != nil else { return }
        guard lastFindBarVisibility != isFindBarVisible else { return }
        lastFindBarVisibility = isFindBarVisible
        if let onFindVisibilityChange {
            onFindVisibilityChange(isFindBarVisible)
        } else {
            AutoFocusTextView.setFindToolbarActive(
                isFindBarVisible,
                showsSeparator: isFindBarVisible,
                in: window
            )
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
    let isEditable: Bool
    let onChange: (String) -> Void
    let onSaveShortcut: () -> Void
    let onApplyShortcut: () -> Void
    let onFitToContent: () -> Void
    let onCopyShortcut: () -> Void
    let onFindShortcut: () -> Void
    let onToggleMarkdownPreview: () -> Void
    let onIncreaseFontSize: () -> Void
    let onDecreaseFontSize: () -> Void
    let onFindVisibilityChange: (Bool) -> Void

    init(
        text: Binding<String>,
        placeholder: String,
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat,
        autoFocus: Bool = true,
        isEditable: Bool = true,
        onChange: @escaping (String) -> Void,
        onSaveShortcut: @escaping () -> Void,
        onApplyShortcut: @escaping () -> Void,
        onFitToContent: @escaping () -> Void,
        onCopyShortcut: @escaping () -> Void,
        onFindShortcut: @escaping () -> Void,
        onToggleMarkdownPreview: @escaping () -> Void,
        onIncreaseFontSize: @escaping () -> Void,
        onDecreaseFontSize: @escaping () -> Void,
        onFindVisibilityChange: @escaping (Bool) -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        self.autoFocus = autoFocus
        self.isEditable = isEditable
        self.onChange = onChange
        self.onSaveShortcut = onSaveShortcut
        self.onApplyShortcut = onApplyShortcut
        self.onFitToContent = onFitToContent
        self.onCopyShortcut = onCopyShortcut
        self.onFindShortcut = onFindShortcut
        self.onToggleMarkdownPreview = onToggleMarkdownPreview
        self.onIncreaseFontSize = onIncreaseFontSize
        self.onDecreaseFontSize = onDecreaseFontSize
        self.onFindVisibilityChange = onFindVisibilityChange
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
        scrollView.onFindVisibilityChange = onFindVisibilityChange

        let textView = AutoFocusTextView()
        textView.coordinator = context.coordinator
        textView.isAutoFocusEnabled = autoFocus

        textView.isEditable = isEditable
        textView.isSelectable = isEditable
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
        textView.usesFindBar = true
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
        scrollView.onFindVisibilityChange = onFindVisibilityChange
        textView.isEditable = isEditable
        textView.isSelectable = isEditable

        // IME composition uses marked text; rewriting textStorage here cancels Chinese candidates.
        if textView.hasMarkedText() {
            textView.textContainerInset = MacStickyEditorLayout.textContainerInset(fontSize: fontSize)
            scrollView.syncDocumentSize(textView)
            if textView.placeholderLabel.string != placeholder {
                textView.placeholderLabel.string = placeholder
            }
            updatePlaceholderVisibility(textView)
            updatePlaceholderStyle(textView, fontSize: fontSize)
            return
        }

        if textView.isUpdating { return }
        textView.isUpdating = true
        defer { textView.isUpdating = false }

        let targetInset = MacStickyEditorLayout.textContainerInset(fontSize: fontSize)
        let needsExternalTextReplace = textView.string != text
        let needsStyleRefresh = context.coordinator.needsStyleRefresh(
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        let needsInsetRefresh = !NSEqualSizes(textView.textContainerInset, targetInset)

        if needsExternalTextReplace {
            let selectedRanges = textView.selectedRanges
            let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: text, fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
            scrollView.preservingVisibleOrigin {
                textView.textStorage?.setAttributedString(attributed)
                textView.selectedRanges = selectedRanges
            }
            context.coordinator.markStyleRendered(fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        } else if needsStyleRefresh {
            let paraStyle = MacMarkdownHighlighter.paragraphStyle(size: fontSize, multiple: lineHeightMultiple)
            let bodyFont = MacMarkdownHighlighter.bodyFont(size: fontSize)
            let baselineOff = MacMarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if fullRange.length > 0 {
                scrollView.preservingVisibleOrigin {
                    textView.textStorage?.addAttributes([
                        .font: bodyFont,
                        .paragraphStyle: paraStyle,
                        .baselineOffset: baselineOff
                    ], range: fullRange)
                    MacMarkdownHighlighter.applyMarkdownHighlighting(to: textView, lineHeightMultiple: lineHeightMultiple)
                }
            }
            context.coordinator.markStyleRendered(fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        }

        if needsInsetRefresh {
            textView.textContainerInset = targetInset
        }
        if needsExternalTextReplace || needsStyleRefresh || needsInsetRefresh {
            scrollView.preservingVisibleOrigin {
                scrollView.syncDocumentSize(textView)
            }
        }

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
        private var lastRenderedFontSize: CGFloat = 0
        private var lastRenderedLineHeightMultiple: CGFloat = 0

        init(_ parent: MacTextView) {
            self.parent = parent
            super.init()
        }

        func configureTextView(_ textView: AutoFocusTextView, text: String, fontSize: CGFloat) {
            let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: text, fontSize: fontSize, lineHeightMultiple: fontSize == parent.fontSize ? parent.lineHeightMultiple : CGFloat(SettingsStore.defaultMacEditorLineHeightMultiple))
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = Self.typingAttributes(fontSize: fontSize, lineHeightMultiple: parent.lineHeightMultiple)
            lastText = text
            lastRenderedFontSize = fontSize
            lastRenderedLineHeightMultiple = parent.lineHeightMultiple
        }

        func needsStyleRefresh(fontSize: CGFloat, lineHeightMultiple: CGFloat) -> Bool {
            lastRenderedFontSize != fontSize || lastRenderedLineHeightMultiple != lineHeightMultiple
        }

        func markStyleRendered(fontSize: CGFloat, lineHeightMultiple: CGFloat) {
            lastRenderedFontSize = fontSize
            lastRenderedLineHeightMultiple = lineHeightMultiple
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
            // Defer binding writes and highlighting until the IME commits marked text.
            if textView.hasMarkedText() {
                parent.updatePlaceholderVisibility(textView)
                (textView.enclosingScrollView as? ToolbarInsetScrollView)?.syncDocumentSize(textView)
                return
            }

            textView.isUpdating = true
            let newText = textView.string
            parent.onChange(newText)
            lastText = newText
            let scrollView = textView.enclosingScrollView as? ToolbarInsetScrollView
            MacMarkdownHighlighter.applyMarkdownHighlighting(to: textView, lineHeightMultiple: parent.lineHeightMultiple)
            markStyleRendered(fontSize: parent.fontSize, lineHeightMultiple: parent.lineHeightMultiple)
            textView.typingAttributes = Self.typingAttributes(fontSize: parent.fontSize, lineHeightMultiple: parent.lineHeightMultiple)
            parent.updatePlaceholderVisibility(textView)
            scrollView?.syncDocumentSize(textView)
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

    override func performFindPanelAction(_ sender: Any?) {
        if !isEditable, findActionTag(from: sender) != NSTextFinder.Action.hideFindInterface.rawValue {
            return
        }
        updateToolbarAppearanceForFindAction(sender)
        super.performFindPanelAction(sender)
        DispatchQueue.main.async { [weak self] in
            (self?.enclosingScrollView as? ToolbarInsetScrollView)?.syncFindToolbarAppearance()
        }
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

        if !isEditable {
            if (cmdOnly && ["c", "f", "s"].contains(chars.lowercased()))
                || (cmdShiftOnly && ["c", "s"].contains(chars.lowercased()))
                || (cmdOptOnly && chars.lowercased() == "f") {
                return
            }
            super.keyDown(with: event)
            return
        }

        if !cmd && !ctrl && !opt && !shift && event.keyCode == 36 {
            if completeMarkdownCodeFence() { return }
            if continueMarkdownList() { return }
        }

        if let action = ShortcutStore.shared.markdownAction(matching: event) {
            applyFormat(action.command); return
        }

        if let action = ShortcutStore.shared.editorAction(matching: event) {
            switch action {
            case .markdownPreview:
                coordinator?.parent.onToggleMarkdownPreview(); return
            }
        }

        if cmdShiftOnly && chars.lowercased() == "c" {
            coordinator?.parent.onCopyShortcut(); return
        }
        if cmdOnly && chars.lowercased() == "f" {
            coordinator?.parent.onFindShortcut(); return
        }
        if cmd && !ctrl && !opt && (chars == "+" || chars == "=") {
            coordinator?.parent.onIncreaseFontSize(); return
        }
        if cmdOnly && chars == "-" {
            coordinator?.parent.onDecreaseFontSize(); return
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

    static func setFindToolbarActive(_ isActive: Bool, showsSeparator: Bool, in window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = !isActive
        window.backgroundColor = isActive ? .white : .textBackgroundColor
        window.titlebarSeparatorStyle = showsSeparator ? .line : .automatic
    }

    private func updateToolbarAppearanceForFindAction(_ sender: Any?) {
        guard let tag = findActionTag(from: sender) else { return }
        if tag == NSTextFinder.Action.showFindInterface.rawValue {
            Self.setFindToolbarActive(true, showsSeparator: true, in: window)
        } else if tag == NSTextFinder.Action.hideFindInterface.rawValue {
            Self.setFindToolbarActive(false, showsSeparator: false, in: window)
        }
    }

    private func findActionTag(from sender: Any?) -> Int? {
        if let sender = sender as? NSMenuItem {
            return sender.tag
        }
        if let sender = sender as? NSControl {
            return sender.tag
        }
        if let sender = sender as? NSObject,
           sender.responds(to: #selector(getter: FindPanelActionSender.tag)) {
            return sender.value(forKey: "tag") as? Int
        }
        return nil
    }

        private func completeMarkdownCodeFence() -> Bool {
        guard isEditable else { return false }
        guard !hasMarkedText() else { return false }
        guard let result = MacMarkdownFormatter.completeCodeFenceIfNeeded(in: string, selection: selectedRange()) else {
            return false
        }
        applyTextResult(result.text, selection: result.selection)
        return true
    }

        private func continueMarkdownList() -> Bool {
        guard isEditable else { return false }
        guard !hasMarkedText() else { return false }
        guard let result = MacMarkdownFormatter.continueListIfNeeded(in: string, selection: selectedRange()) else {
            return false
        }
        applyTextResult(result.text, selection: result.selection)
        return true
    }

        private func applyFormat(_ command: MacMarkdownFormatCommand) {
        guard isEditable else { return }
        guard !hasMarkedText() else { return }

        let currentText = self.string
        let selection = self.selectedRange()
        let result = MacMarkdownFormatter.apply(command: command, to: currentText, selection: selection)

        applyTextResult(result.text, selection: result.selection)
    }

    private func applyTextResult(_ text: String, selection: NSRange) {
        isUpdating = true
        let fontSize = (coordinator?.parent.fontSize) ?? 14
        let lineHeightMultiple = (coordinator?.parent.lineHeightMultiple) ?? CGFloat(SettingsStore.defaultMacEditorLineHeightMultiple)
        let oldText = string
        let change = replacementChange(from: oldText, to: text)
        let scrollView = enclosingScrollView as? ToolbarInsetScrollView
        guard shouldChangeText(in: change.range, replacementString: change.replacement) else {
            isUpdating = false
            return
        }

        textStorage?.replaceCharacters(in: change.range, with: change.replacement)
        setSelectedRange(selection)
        didChangeText()
        coordinator?.parent.onChange(text)
        if let scrollView {
            scrollView.preservingVisibleOrigin {
                MacMarkdownHighlighter.applyMarkdownHighlighting(to: self, lineHeightMultiple: lineHeightMultiple)
                scrollView.syncDocumentSize(self)
            }
        } else {
            MacMarkdownHighlighter.applyMarkdownHighlighting(to: self, lineHeightMultiple: lineHeightMultiple)
        }
        typingAttributes = MacTextView.Coordinator.typingAttributes(fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        coordinator?.markStyleRendered(fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        if let placeholder = self.subviews.first(where: { $0 is PlaceholderLabel }) as? PlaceholderLabel {
            placeholder.isHidden = !text.isEmpty
        }
        isUpdating = false
    }

    private func replacementChange(from oldText: String, to newText: String) -> (range: NSRange, replacement: String) {
        let old = oldText as NSString
        let new = newText as NSString
        var prefix = 0
        while prefix < old.length,
              prefix < new.length,
              old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }

        var suffix = 0
        while suffix < old.length - prefix,
              suffix < new.length - prefix,
              old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) {
            suffix += 1
        }

        let oldLength = old.length - prefix - suffix
        let newLength = new.length - prefix - suffix
        let replacement = new.substring(with: NSRange(location: prefix, length: newLength))
        return (NSRange(location: prefix, length: oldLength), replacement)
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
        guard !textView.hasMarkedText() else { return }

        let selectedRanges = textView.selectedRanges

        let text = textView.string
        let fontSize = textView.font?.pointSize ?? CGFloat(SettingsStore.shared.macEditorFontSize)

        let bodyFont = bodyFont(size: fontSize)
        let paraStyle = paragraphStyle(size: fontSize, multiple: lineHeightMultiple)
        let baselineOff = baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let undoManager = textView.undoManager
        let wasUndoRegistrationEnabled = undoManager?.isUndoRegistrationEnabled ?? false
        if wasUndoRegistrationEnabled {
            undoManager?.disableUndoRegistration()
        }
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
        if wasUndoRegistrationEnabled {
            undoManager?.enableUndoRegistration()
        }
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
