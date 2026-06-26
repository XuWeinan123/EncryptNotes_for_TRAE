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
                window.level = state.isPinned ? .floating : .normal
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

        let window = NSWindow(
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
        window.level = isPinned ? .floating : .normal
        window.identifier = NSUserInterfaceItemIdentifier(rawValue: note.id)
        window.setFrameAutosaveName("")
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed

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
        let frame = windowState?.frame ?? MacWindowFrame(x: 200, y: 200, width: 280, height: 200)
        let isPinned = windowState?.isPinned ?? true

        let lockedView = LockedStickyNoteView(noteInfo: info)
        let hostingView = NSHostingView(rootView: lockedView)

        let window = NSWindow(
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
        window.level = isPinned ? .floating : .normal
        window.identifier = NSUserInterfaceItemIdentifier(rawValue: info.id)
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed

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
        window.level = isPinned ? .floating : .normal
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
        let width: Double = 280
        let height: Double = 320
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
            window.level = state.isPinned ? .floating : .normal
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        if let state = MacNoteWindowStore.shared.windowState(for: id), state.isPinned {
            window.level = .floating
        }
    }
}
