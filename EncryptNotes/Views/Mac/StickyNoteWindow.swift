import Foundation
import SwiftUI
import AppKit

@MainActor
final class StickyNoteWindowManager: NSObject {
    static let shared = StickyNoteWindowManager()
    private static let minimumContentSize = CGSize(width: 200, height: 200)

    private var noteWindows: [String: NSWindow] = [:]

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

    func showNote(_ note: Note, at screenPoint: NSPoint? = nil) {
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

        let editorView = StickyNoteEditorView(note: note)
        let hostingView = NSHostingView(rootView: editorView)

        let window = StickyNoteWindow(
            contentRect: NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle(for: note.body)
        window.contentView = hostingView
        configure(window, noteId: note.id)
        applyWindowLevel(window, isPinned: isPinned)

        noteWindows[note.id] = window

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

    func showLockedNote(_ info: EncryptedNoteInfo) {
        if let existingWindow = noteWindows[info.id] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        MacNoteWindowStore.shared.openWindow(for: info.id)
        let windowState = MacNoteWindowStore.shared.windowState(for: info.id)
        let frame = windowState?.frame ?? defaultWindowFrame()
        let isPinned = windowState?.isPinned ?? true

        let lockedView = LockedStickyNoteView(noteInfo: info)
        let hostingView = NSHostingView(rootView: lockedView)

        let window = StickyNoteWindow(
            contentRect: NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "加密笔记"
        window.contentView = hostingView
        configure(window, noteId: info.id)
        applyWindowLevel(window, isPinned: isPinned)

        noteWindows[info.id] = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    func updateWindowLevel(for noteId: String, isPinned: Bool) {
        guard let window = noteWindows[noteId] else { return }
        applyWindowLevel(window, isPinned: isPinned)
    }

    func updateWindowTitle(for noteId: String, title: String) {
        noteWindows[noteId]?.title = title
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

    private func saveWindowFrame(_ window: NSWindow, noteId: String) {
        let frame = window.frame
        MacNoteWindowStore.shared.updateFrame(
            for: noteId,
            frame: MacWindowFrame(
                x: Double(frame.origin.x),
                y: Double(frame.origin.y),
                width: Double(max(Self.minimumContentSize.width, frame.size.width)),
                height: Double(max(Self.minimumContentSize.height, frame.size.height))
            )
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
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .none
        }
        installSoftScrollEdgeAccessoryIfAvailable(on: window)
        window.minSize = NSSize(
            width: Self.minimumContentSize.width,
            height: Self.minimumContentSize.height
        )
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }

    private func installSoftScrollEdgeAccessoryIfAvailable(on window: NSWindow) {
        guard #available(macOS 26.1, *) else { return }

        let accessory = SoftScrollEdgeTitlebarAccessoryController()
        accessory.layoutAttribute = .bottom
        accessory.automaticallyAdjustsSize = false
        accessory.preferredScrollEdgeEffectStyle = .soft
        window.addTitlebarAccessoryViewController(accessory)
    }

    private func windowTitle(for body: String) -> String {
        let firstLine = body
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return firstLine?.isEmpty == false ? firstLine! : ""
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

        NotificationCenter.default.post(name: .macWindowWillClose, object: nil, userInfo: ["noteId": id])
        saveWindowFrame(window, noteId: id)
        noteWindows.removeValue(forKey: id)
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
        }
    }
}

private final class StickyNoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@available(macOS 26.1, *)
private final class SoftScrollEdgeTitlebarAccessoryController: NSTitlebarAccessoryViewController {
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        self.view = view
    }
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
