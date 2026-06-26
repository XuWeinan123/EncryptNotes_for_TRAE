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

    @Published private(set) var openWindows: Set<String> = []
    @Published private(set) var windowStates: [String: MacNoteWindowState] = [:]

    private let defaults: UserDefaults
    private let windowStateKeyPrefix = "mac.windowState."

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
                isPinned: true,
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

    func updateFrame(for noteId: String, frame: MacWindowFrame) {
        guard var state = windowStates[noteId] else { return }
        state.frame = frame
        windowStates[noteId] = state
        saveWindowState(for: noteId)
    }

    func closeAllWindows() {
        openWindows.removeAll()
    }

    private func defaultWindowFrame() -> MacWindowFrame {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: Double = 280
        let height: Double = 320
        let x = screen.midX - width / 2
        let y = screen.midY - height / 2
        return MacWindowFrame(x: x, y: y, width: width, height: height)
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
