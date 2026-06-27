import Foundation
import SwiftUI
import AppKit
import Carbon
import Combine

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published var newNoteKey: (keyCode: UInt32, modifiers: UInt32)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let defaults: UserDefaults

    private let newNoteKeyDefaults = "mac.shortcut.newNote"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: newNoteKeyDefaults),
           let shortcut = try? JSONDecoder.decode(ShortcutData.self, from: data) {
            self.newNoteKey = (shortcut.keyCode, shortcut.modifiers)
        } else {
            self.newNoteKey = (keyCode: 6, modifiers: UInt32(controlKey | cmdKey))
        }

        registerHotKeys()
    }

    func registerHotKeys() {
        unregisterHotKeys()

        let hotKeyID = EventHotKeyID(signature: OSType(0x424B5730), id: 1)

        RegisterEventHotKey(
            newNoteKey.keyCode,
            newNoteKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, &eventHandlerRef)
    }

    func unregisterHotKeys() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handlerRef = eventHandlerRef {
            RemoveEventHandler(handlerRef)
            eventHandlerRef = nil
        }
    }

    func setNewNoteShortcut(keyCode: UInt32, modifiers: UInt32) {
        newNoteKey = (keyCode, modifiers)
        let data = try? JSONEncoder.encode(ShortcutData(keyCode: keyCode, modifiers: modifiers))
        defaults.set(data, forKey: newNoteKeyDefaults)
        registerHotKeys()
    }

    static func displayStringForKey(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        let keyString: String
        switch keyCode {
        case 0: keyString = "A"
        case 1: keyString = "S"
        case 2: keyString = "D"
        case 3: keyString = "F"
        case 4: keyString = "H"
        case 5: keyString = "G"
        case 6: keyString = "Z"
        case 7: keyString = "X"
        case 8: keyString = "C"
        case 9: keyString = "V"
        case 11: keyString = "B"
        case 12: keyString = "Q"
        case 13: keyString = "W"
        case 14: keyString = "E"
        case 15: keyString = "R"
        case 16: keyString = "Y"
        case 17: keyString = "T"
        case 31: keyString = "O"
        case 32: keyString = "U"
        case 34: keyString = "I"
        case 35: keyString = "P"
        case 36: keyString = "Return"
        case 37: keyString = "L"
        case 38: keyString = "J"
        case 40: keyString = "K"
        case 45: keyString = "N"
        case 46: keyString = "M"
        case 48: keyString = "Tab"
        case 49: keyString = "Space"
        case 51: keyString = "⌫"
        case 53: keyString = "Esc"
        case 123: keyString = "←"
        case 124: keyString = "→"
        case 125: keyString = "↓"
        case 126: keyString = "↑"
        default: keyString = "?"
        }
        parts.append(keyString)
        return parts.joined()
    }

    private struct ShortcutData: Codable {
        let keyCode: UInt32
        let modifiers: UInt32
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { (_, eventRef, _) -> OSStatus in
    guard let eventRef = eventRef else { return noErr }
    var hkID = EventHotKeyID()
    GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)

    DispatchQueue.main.async {
        if hkID.id == 1 {
            NotificationCenter.default.post(name: .macNewNote, object: nil)
        }
    }
    return noErr
}

extension Notification.Name {
    static let macNewNote = Notification.Name("macNewNote")
}
