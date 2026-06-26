import Foundation
import SwiftUI
import AppKit
import Carbon

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published var newPlainNoteKey: (keyCode: UInt32, modifiers: UInt32)
    @Published var newEncryptedNoteKey: (keyCode: UInt32, modifiers: UInt32)

    private var plainHotKeyRef: EventHotKeyRef?
    private var encryptedHotKeyRef: EventHotKeyRef?
    private var hotKeyID = EventHotKeyID()
    private let defaults: UserDefaults

    private let plainKey = "mac.shortcut.newPlain"
    private let encryptedKey = "mac.shortcut.newEncrypted"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let plainData = defaults.data(forKey: plainKey),
           let plain = try? JSONDecoder().decode(ShortcutData.self, from: plainData) {
            self.newPlainNoteKey = (plain.keyCode, plain.modifiers)
        } else {
            self.newPlainNoteKey = (keyCode: 45, modifiers: UInt32(optionKey | commandKey))
        }

        if let encryptedData = defaults.data(forKey: encryptedKey),
           let encrypted = try? JSONDecoder().decode(ShortcutData.self, from: encryptedData) {
            self.newEncryptedNoteKey = (encrypted.keyCode, encrypted.modifiers)
        } else {
            self.newEncryptedNoteKey = (keyCode: 45, modifiers: UInt32(optionKey | shiftKey | commandKey))
        }

        registerHotKeys()
    }

    func registerHotKeys() {
        unregisterHotKeys()

        var hotKeyID1 = EventHotKeyID(signature: OSType(0x424B5731), id: 1)
        var hotKeyID2 = EventHotKeyID(signature: OSType(0x424B5732), id: 2)

        RegisterEventHotKey(
            newPlainNoteKey.keyCode,
            newPlainNoteKey.modifiers,
            hotKeyID1,
            GetApplicationEventTarget(),
            0,
            &plainHotKeyRef
        )

        RegisterEventHotKey(
            newEncryptedNoteKey.keyCode,
            newEncryptedNoteKey.modifiers,
            hotKeyID2,
            GetApplicationEventTarget(),
            0,
            &encryptedHotKeyRef
        )

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, _) -> OSStatus in
            guard let eventRef = eventRef else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)

            Task { @MainActor in
                if hkID.id == 1 {
                    NotificationCenter.default.post(name: .macNewPlainNote, object: nil)
                } else if hkID.id == 2 {
                    NotificationCenter.default.post(name: .macNewEncryptedNote, object: nil)
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    func unregisterHotKeys() {
        if let ref = plainHotKeyRef {
            UnregisterEventHotKey(ref)
            plainHotKeyRef = nil
        }
        if let ref = encryptedHotKeyRef {
            UnregisterEventHotKey(ref)
            encryptedHotKeyRef = nil
        }
    }

    func setNewPlainNoteShortcut(keyCode: UInt32, modifiers: UInt32) {
        newPlainNoteKey = (keyCode, modifiers)
        let data = try? JSONEncoder().encode(ShortcutData(keyCode: keyCode, modifiers: modifiers))
        defaults.set(data, forKey: plainKey)
        registerHotKeys()
    }

    func setNewEncryptedNoteShortcut(keyCode: UInt32, modifiers: UInt32) {
        newEncryptedNoteKey = (keyCode, modifiers)
        let data = try? JSONEncoder().encode(ShortcutData(keyCode: keyCode, modifiers: modifiers))
        defaults.set(data, forKey: encryptedKey)
        registerHotKeys()
    }

    static func displayStringForKey(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(commandKey) != 0 { parts.append("⌘") }

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

extension Notification.Name {
    static let macNewPlainNote = Notification.Name("macNewPlainNote")
    static let macNewEncryptedNote = Notification.Name("macNewEncryptedNote")
}
