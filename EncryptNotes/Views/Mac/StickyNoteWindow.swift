import Foundation
import SwiftUI
import AppKit

extension Notification.Name {
    static let sealNoteLockEncryptedNote = Notification.Name("SealNoteLockEncryptedNote")
    static let sealNotePresentKeyIssue = Notification.Name("SealNotePresentKeyIssue")
}

@MainActor
final class StickyNoteWindowManager: NSObject {
    static let shared = StickyNoteWindowManager()
    private static let minimumContentSize = CGSize(width: 200, height: 200)
    // 统一标题栏负责稳定 toolbar placement；fullSizeContentView 让内容延伸到玻璃下方。
    static let windowStyleMask: NSWindow.StyleMask =
        [.titled, .closable, .resizable, .unifiedTitleAndToolbar, .fullSizeContentView]

    private var noteWindows: [String: NSWindow] = [:]
    private var noteIdsRememberingNewNoteSize = Set<String>()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidBecomeActive() {
        for (noteId, window) in noteWindows {
            if let state = MacNoteWindowStore.shared.windowState(for: noteId) {
                applyWindowLevel(window, isPinned: state.isPinned)
            }
        }
    }

    func showNote(_ note: Note, at screenPoint: NSPoint? = nil, remembersNewNoteSize: Bool = false) {
        if let existingWindow = noteWindows[note.id] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        MacNoteWindowStore.shared.openWindow(for: note.id, isEncrypted: note.isEncrypted)
        let windowState = MacNoteWindowStore.shared.windowState(for: note.id)
        var frame = windowState?.frame ?? defaultWindowFrame()
        let isPinned = windowState?.isPinned ?? true

        if let point = screenPoint {
            let size = NSSize(width: frame.width, height: frame.height)
            frame = windowFrameNearMouse(screenPoint: point, size: size)
        }

        let editorView = AppLocalizedRoot {
            StickyNoteEditorView(note: note)
        }
        let hostingView = NSHostingView(rootView: editorView)

        let frameRect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        let window = StickyNoteWindow(
            contentRect: NSWindow.contentRect(forFrameRect: frameRect, styleMask: Self.windowStyleMask),
            styleMask: Self.windowStyleMask,
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.contentView = hostingView
        configure(window, noteId: note.id)
        applyWindowLevel(window, isPinned: isPinned)

        noteWindows[note.id] = window
        if remembersNewNoteSize {
            noteIdsRememberingNewNoteSize.insert(note.id)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func windowFrameNearMouse(screenPoint: NSPoint, size: NSSize) -> MacWindowFrame {
        var mouseScreen: NSScreen? = nil
        for screen in NSScreen.screens {
            if NSPointInRect(screenPoint, screen.frame) {
                mouseScreen = screen
                break
            }
        }
        let screen = mouseScreen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let offset: CGFloat = 8
        var x = screenPoint.x - size.width / 2
        var y = screenPoint.y - size.height - offset

        if x < visibleFrame.minX + 8 { x = visibleFrame.minX + 8 }
        if x + size.width > visibleFrame.maxX - 8 { x = visibleFrame.maxX - size.width - 8 }
        if y < visibleFrame.minY + 8 {
            y = screenPoint.y + offset
            if y + size.height > visibleFrame.maxY - 8 {
                y = visibleFrame.midY - size.height / 2
            }
        }
        if y + size.height > visibleFrame.maxY - 8 {
            y = visibleFrame.maxY - size.height - 8
        }

        return MacWindowFrame(
            x: Double(x),
            y: Double(y),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    static func currentMouseLocation() -> NSPoint {
        NSEvent.mouseLocation
    }

    func showLockedNote(_ info: EncryptedNoteInfo, keyIssue: Error = CryptoError.keyNotFound) {
        if let existingWindow = noteWindows[info.id] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            presentKeyIssue(keyIssue, for: info.id)
            return
        }

        MacNoteWindowStore.shared.openWindow(for: info.id)
        let windowState = MacNoteWindowStore.shared.windowState(for: info.id)
        let frame = windowState?.frame ?? defaultWindowFrame()
        let isPinned = windowState?.isPinned ?? true

        let lockedNote = Note(
            id: info.id,
            body: info.ciphertextPreview,
            createdAt: info.updatedAt,
            updatedAt: info.updatedAt,
            isEncrypted: true
        )
        let editorView = AppLocalizedRoot {
            StickyNoteEditorView(note: lockedNote, startsLocked: true, initialKeyIssue: keyIssue)
        }
        let hostingView = NSHostingView(rootView: editorView)

        let frameRect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        let window = StickyNoteWindow(
            contentRect: NSWindow.contentRect(forFrameRect: frameRect, styleMask: Self.windowStyleMask),
            styleMask: Self.windowStyleMask,
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.contentView = hostingView
        configure(window, noteId: info.id)
        applyWindowLevel(window, isPinned: isPinned)

        noteWindows[info.id] = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentKeyIssue(_ error: Error, for noteId: String) {
        NotificationCenter.default.post(
            name: .sealNotePresentKeyIssue,
            object: noteId,
            userInfo: ["error": error]
        )
    }

    func closeWindow(for noteId: String) {
        guard let window = noteWindows[noteId] else { return }
        window.close()
    }

    func closeAllWindows() {
        for (_, window) in noteWindows {
            window.close()
        }
        noteWindows.removeAll()
        MacNoteWindowStore.shared.closeAllWindows()
    }

    func restoreDefaultWindowSizes() {
        let size = MacNoteWindowStore.defaultWindowSize
        for (noteId, window) in noteWindows {
            var frame = window.frame
            frame.size = size
            window.setFrame(frame, display: true, animate: true)
            saveWindowFrame(window, noteId: noteId, persistImmediately: true)
        }
    }

    func temporarilyLockAllEncryptedNoteWindows() {
        NotificationCenter.default.post(name: .sealNoteLockEncryptedNote, object: nil)
    }

    func fitWindowToContent(noteId: String, text: String, fontSize: CGFloat) {
        guard let window = noteWindows[noteId] else { return }
        let textContainerInset = MacStickyEditorLayout.textContainerInset(fontSize: fontSize)
        let horizontalPadding = MacStickyEditorLayout.horizontalPadding(textContainerInsetWidth: textContainerInset.width)
        let targetWidth = MacStickyEditorLayout.fittedWindowWidth(fontSize: fontSize)

        let textWidth = max(10, targetWidth - horizontalPadding)
        let measuredHeight = measureTextHeight(text: text, width: textWidth, fontSize: fontSize)
        let verticalPadding = textContainerInset.height * 2 + DS.s4 + MacStickyEditorLayout.editorBottomInset
        let contentHeight = measuredHeight + verticalPadding

        var targetHeight = max(MacStickyEditorLayout.minimumFittedWindowHeight(fontSize: fontSize), contentHeight)
        targetHeight = min(targetWidth * 4 / 3, targetHeight)

        let finalWidth = max(Self.minimumContentSize.width, targetWidth)
        let finalHeight = max(Self.minimumContentSize.height, targetHeight)

        let oldFrame = window.frame
        var newOrigin = NSPoint(
            x: oldFrame.origin.x,
            y: oldFrame.maxY - finalHeight
        )

        if let screen = window.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            if newOrigin.x < vf.minX + 8 { newOrigin.x = vf.minX + 8 }
            if newOrigin.x + finalWidth > vf.maxX - 8 { newOrigin.x = vf.maxX - finalWidth - 8 }
            if newOrigin.y < vf.minY + 8 { newOrigin.y = vf.minY + 8 }
            if newOrigin.y + finalHeight > vf.maxY - 8 { newOrigin.y = vf.maxY - finalHeight - 8 }
        }

        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: finalWidth, height: finalHeight))
        window.setFrame(newFrame, display: true, animate: true)
        saveWindowFrame(window, noteId: noteId, persistImmediately: false)
    }

    private func measureTextHeight(text: String, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(
            text: text,
            fontSize: fontSize,
            lineHeightMultiple: CGFloat(SettingsStore.shared.macEditorLineHeightMultiple)
        )
        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.glyphRange(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return usedRect.height
    }

    func updateWindowLevel(for noteId: String, isPinned: Bool) {
        guard let window = noteWindows[noteId] else { return }
        applyWindowLevel(window, isPinned: isPinned)
    }

    private func applyWindowLevel(_ window: NSWindow, isPinned: Bool) {
        window.level = isPinned ? .floating : .normal
        if isPinned {
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
        }
    }

    private func saveWindowFrame(_ window: NSWindow, noteId: String, persistImmediately: Bool = false) {
        let frame = window.frame
        MacNoteWindowStore.shared.updateFrame(
            for: noteId,
            frame: MacWindowFrame(
                x: Double(frame.origin.x),
                y: Double(frame.origin.y),
                width: Double(max(Self.minimumContentSize.width, frame.size.width)),
                height: Double(max(Self.minimumContentSize.height, frame.size.height))
            ),
            remembersAsNewNoteSize: noteIdsRememberingNewNoteSize.contains(noteId),
            persistImmediately: persistImmediately
        )
    }

    private func configure(_ window: NSWindow, noteId: String) {
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(rawValue: noteId)
        window.setFrameAutosaveName("")
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.isOpaque = true
        window.backgroundColor = .textBackgroundColor
        window.hasShadow = true
        // 可见标题区是 .primaryAction 工具栏项稳定停靠尾部的布局锚点。
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.minSize = NSSize(
            width: Self.minimumContentSize.width,
            height: Self.minimumContentSize.height
        )
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    private func defaultWindowFrame() -> MacWindowFrame {
        let lastSize = MacNoteWindowStore.shared.lastWindowSize()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = lastSize.width
        let height = lastSize.height
        let x = screen.midX - width / 2
        let y = screen.midY - height / 2
        return MacWindowFrame(x: x, y: y, width: width, height: height)
    }
}

extension StickyNoteWindowManager: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(Self.minimumContentSize.width, frameSize.width),
            height: max(Self.minimumContentSize.height, frameSize.height)
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }

        saveWindowFrame(window, noteId: id, persistImmediately: true)
        noteWindows.removeValue(forKey: id)
        noteIdsRememberingNewNoteSize.remove(id)
        MacNoteWindowStore.shared.closeWindow(for: id)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        saveWindowFrame(window, noteId: id)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        saveWindowFrame(window, noteId: id)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        if let state = MacNoteWindowStore.shared.windowState(for: id) {
            applyWindowLevel(window, isPinned: state.isPinned)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        if let state = MacNoteWindowStore.shared.windowState(for: id), state.isPinned {
            applyWindowLevel(window, isPinned: true)
        } else if SettingsStore.shared.lockUnpinnedEncryptedNotesOnBackground {
            NotificationCenter.default.post(name: .sealNoteLockEncryptedNote, object: id)
        }
    }
}

private final class StickyNoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct MacWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragRegionView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
