import Foundation
import SwiftUI
import AppKit
import Combine

struct MacWindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct MacNoteWindowState: Codable, Equatable {
    var noteId: String
    var isPinned: Bool
    var frame: MacWindowFrame
    var lastOpenedAt: Date
}

@MainActor
final class MacNoteWindowStore: ObservableObject {
    static let shared = MacNoteWindowStore()
    static let defaultWindowSize = CGSize(width: 400, height: 250)

    @Published private(set) var openWindows: Set<String> = []
    @Published private(set) var windowStates: [String: MacNoteWindowState] = [:]

    private let defaults: UserDefaults
    private let windowStateKeyPrefix = "mac.windowState."
    private let lastWindowSizeKey = "mac.lastStickyNoteWindowSize"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadWindowStates()
    }

    func isWindowOpen(for noteId: String) -> Bool {
        openWindows.contains(noteId)
    }

    func windowState(for noteId: String) -> MacNoteWindowState? {
        windowStates[noteId]
    }

    func openWindow(for noteId: String, isEncrypted: Bool = false) {
        openWindows.insert(noteId)

        if windowStates[noteId] == nil {
            let defaultFrame = defaultWindowFrame()
            windowStates[noteId] = MacNoteWindowState(
                noteId: noteId,
                isPinned: SettingsStore.shared.pinNewNotesByDefault,
                frame: defaultFrame,
                lastOpenedAt: Date()
            )
        } else {
            windowStates[noteId]?.lastOpenedAt = Date()
        }

        saveWindowState(for: noteId)
    }

    func closeWindow(for noteId: String) {
        openWindows.remove(noteId)
    }

    func togglePin(for noteId: String) {
        guard var state = windowStates[noteId] else { return }
        state.isPinned.toggle()
        windowStates[noteId] = state
        saveWindowState(for: noteId)
    }

    func setPinned(_ isPinned: Bool, for noteId: String) {
        guard var state = windowStates[noteId] else { return }
        state.isPinned = isPinned
        windowStates[noteId] = state
        saveWindowState(for: noteId)
    }

    func updateFrame(for noteId: String, frame: MacWindowFrame, remembersAsNewNoteSize: Bool = false) {
        guard var state = windowStates[noteId] else { return }
        state.frame = frame
        windowStates[noteId] = state
        if remembersAsNewNoteSize {
            saveLastWindowSize(width: frame.width, height: frame.height)
        }
        saveWindowState(for: noteId)
    }

    func closeAllWindows() {
        openWindows.removeAll()
    }

    private func defaultWindowFrame() -> MacWindowFrame {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = lastWindowSize()
        let width = size.width
        let height = size.height
        let x = screen.midX - width / 2
        let y = screen.midY - height / 2
        return MacWindowFrame(x: x, y: y, width: width, height: height)
    }

    func lastWindowSize() -> (width: Double, height: Double) {
        guard let data = defaults.data(forKey: lastWindowSizeKey),
              let frame = try? JSONDecoder.decode(MacWindowFrame.self, from: data) else {
            return (
                width: Double(Self.defaultWindowSize.width),
                height: Double(Self.defaultWindowSize.height)
            )
        }

        return (
            width: max(200, frame.width),
            height: max(200, frame.height)
        )
    }

    private func saveLastWindowSize(width: Double, height: Double) {
        let size = MacWindowFrame(x: 0, y: 0, width: width, height: height)
        if let data = try? JSONEncoder.encode(size) {
            defaults.set(data, forKey: lastWindowSizeKey)
        }
    }

    private func saveWindowState(for noteId: String) {
        guard let state = windowStates[noteId] else { return }
        if let data = try? JSONEncoder.encode(state) {
            defaults.set(data, forKey: windowStateKeyPrefix + noteId)
        }
    }

    private func loadWindowStates() {
        let prefix = windowStateKeyPrefix
        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix(prefix),
                  let data = value as? Data,
                  let state = try? JSONDecoder.decode(MacNoteWindowState.self, from: data) else {
                continue
            }
            windowStates[state.noteId] = state
        }
    }
}
