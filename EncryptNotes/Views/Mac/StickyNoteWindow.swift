import Foundation
import SwiftUI
import AppKit

@MainActor
final class StickyNoteWindowManager: NSObject {
    static let shared = StickyNoteWindowManager()

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

    func showNote(_ note: Note) {
        if let existingWindow = noteWindows[note.id] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        MacNoteWindowStore.shared.openWindow(for: note.id, isEncrypted: note.isEncrypted)
        let windowState = MacNoteWindowStore.shared.windowState(for: note.id)
        let frame = windowState?.frame ?? defaultWindowFrame()
        let isPinned = windowState?.isPinned ?? true

        let editorView = StickyNoteEditorView(note: note)
        let hostingView = NSHostingView(rootView: editorView)

        let window = StickyNoteWindow(
            contentRect: NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(rawValue: note.id)
        window.setFrameAutosaveName("")
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        applyWindowLevel(window, isPinned: isPinned)

        noteWindows[note.id] = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(rawValue: info.id)
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
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
                width: Double(frame.size.width),
                height: Double(frame.size.height)
            )
        )
    }

    private func defaultWindowFrame() -> MacWindowFrame {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: Double = 400
        let height: Double = 250
        let x = screen.midX - width / 2
        let y = screen.midY - height / 2
        return MacWindowFrame(x: x, y: y, width: width, height: height)
    }
}

extension StickyNoteWindowManager: NSWindowDelegate {
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
