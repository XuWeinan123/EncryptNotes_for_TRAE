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
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        configure(window, noteId: note.id)
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
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
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
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.minSize = NSSize(
            width: Self.minimumContentSize.width,
            height: Self.minimumContentSize.height
        )
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func defaultWindowFrame() -> MacWindowFrame {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = Double(MacNoteWindowStore.defaultWindowSize.width)
        let height = Double(MacNoteWindowStore.defaultWindowSize.height)
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

struct MacWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragRegionView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
