import Foundation
import SwiftUI
import AppKit
import Carbon
import Combine

enum MarkdownShortcutAction: String, CaseIterable, Identifiable, Codable {
    case bold
    case italic
    case underline
    case inlineCode
    case inlineMath
    case strike
    case htmlComment
    case link

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bold: return "粗体"
        case .italic: return "斜体"
        case .underline: return "下划线"
        case .inlineCode: return "行内代码"
        case .inlineMath: return "行内公式"
        case .strike: return "删除线"
        case .htmlComment: return "HTML 注释"
        case .link: return "链接"
        }
    }

    var command: MacMarkdownFormatCommand {
        switch self {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .inlineCode: return .inlineCode
        case .inlineMath: return .inlineMath
        case .strike: return .strike
        case .htmlComment: return .htmlComment
        case .link: return .link
        }
    }

    var selector: Selector {
        switch self {
        case .bold: return Selector(("markdownBold:"))
        case .italic: return Selector(("markdownItalic:"))
        case .underline: return Selector(("markdownUnderline:"))
        case .inlineCode: return Selector(("markdownInlineCode:"))
        case .inlineMath: return Selector(("markdownInlineMath:"))
        case .strike: return Selector(("markdownStrike:"))
        case .htmlComment: return Selector(("markdownHTMLComment:"))
        case .link: return Selector(("markdownLink:"))
        }
    }
}

enum EditorShortcutAction: String, CaseIterable, Identifiable, Codable {
    case markdownPreview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdownPreview: return "切换 Markdown 预览"
        }
    }
}

struct MarkdownShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyEquivalent: String
}

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published var newNoteKey: (keyCode: UInt32, modifiers: UInt32)
    @Published private(set) var markdownShortcuts: [MarkdownShortcutAction: MarkdownShortcut]
    @Published private(set) var editorShortcuts: [EditorShortcutAction: MarkdownShortcut]

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let defaults: UserDefaults

    private let newNoteKeyDefaults = "mac.shortcut.newNote"
    private let markdownShortcutDefaults = "mac.shortcut.markdownFormatting"
    private let editorShortcutDefaults = "mac.shortcut.editorActions"
    fileprivate enum HotKeyID {
        static let newNote: UInt32 = 1
        static let openRecentBase: UInt32 = 10
        static let activateMenu: UInt32 = 20
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: newNoteKeyDefaults),
           let shortcut = try? JSONDecoder.decode(ShortcutData.self, from: data) {
            self.newNoteKey = (shortcut.keyCode, shortcut.modifiers)
        } else {
            self.newNoteKey = Self.defaultNewNoteShortcut
        }

        if let data = defaults.data(forKey: markdownShortcutDefaults),
           let stored = try? JSONDecoder.decode([String: MarkdownShortcut].self, from: data) {
            var shortcuts = Self.defaultMarkdownShortcuts
            for (rawValue, shortcut) in stored {
                if let action = MarkdownShortcutAction(rawValue: rawValue) {
                    shortcuts[action] = shortcut
                }
            }
            self.markdownShortcuts = shortcuts
        } else {
            self.markdownShortcuts = Self.defaultMarkdownShortcuts
        }

        if let data = defaults.data(forKey: editorShortcutDefaults),
           let stored = try? JSONDecoder.decode([String: MarkdownShortcut].self, from: data) {
            var shortcuts = Self.defaultEditorShortcuts
            for (rawValue, shortcut) in stored {
                if let action = EditorShortcutAction(rawValue: rawValue) {
                    shortcuts[action] = shortcut
                }
            }
            self.editorShortcuts = shortcuts
        } else {
            self.editorShortcuts = Self.defaultEditorShortcuts
        }

        registerHotKeys()
    }

    func registerHotKeys() {
        unregisterHotKeys()

        registerHotKey(id: HotKeyID.newNote, keyCode: newNoteKey.keyCode, modifiers: newNoteKey.modifiers)
        registerHotKey(id: HotKeyID.openRecentBase + 1, keyCode: 18, modifiers: UInt32(controlKey | cmdKey))
        registerHotKey(id: HotKeyID.openRecentBase + 2, keyCode: 19, modifiers: UInt32(controlKey | cmdKey))
        registerHotKey(id: HotKeyID.openRecentBase + 3, keyCode: 20, modifiers: UInt32(controlKey | cmdKey))
        registerHotKey(id: HotKeyID.activateMenu, keyCode: 50, modifiers: UInt32(controlKey | cmdKey))

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, &eventHandlerRef)
    }

    func unregisterHotKeys() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
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

    func shortcut(for action: MarkdownShortcutAction) -> MarkdownShortcut {
        markdownShortcuts[action] ?? Self.defaultMarkdownShortcuts[action]!
    }

    func shortcut(for action: EditorShortcutAction) -> MarkdownShortcut {
        editorShortcuts[action] ?? Self.defaultEditorShortcuts[action]!
    }

    func setMarkdownShortcut(_ shortcut: MarkdownShortcut, for action: MarkdownShortcutAction) {
        markdownShortcuts[action] = shortcut
        persistMarkdownShortcuts()
        MacMainMenuController.shared.installMainMenu()
    }

    func setEditorShortcut(_ shortcut: MarkdownShortcut, for action: EditorShortcutAction) {
        editorShortcuts[action] = shortcut
        persistEditorShortcuts()
    }

    func resetMarkdownShortcuts() {
        markdownShortcuts = Self.defaultMarkdownShortcuts
        defaults.removeObject(forKey: markdownShortcutDefaults)
        MacMainMenuController.shared.installMainMenu()
    }

    func resetEditorShortcuts() {
        editorShortcuts = Self.defaultEditorShortcuts
        defaults.removeObject(forKey: editorShortcutDefaults)
    }

    func resetAllShortcuts() {
        newNoteKey = Self.defaultNewNoteShortcut
        markdownShortcuts = Self.defaultMarkdownShortcuts
        editorShortcuts = Self.defaultEditorShortcuts
        defaults.removeObject(forKey: newNoteKeyDefaults)
        defaults.removeObject(forKey: markdownShortcutDefaults)
        defaults.removeObject(forKey: editorShortcutDefaults)
        registerHotKeys()
        MacMainMenuController.shared.installMainMenu()
    }

    func markdownAction(matching event: NSEvent) -> MarkdownShortcutAction? {
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        let keyCode = UInt32(event.keyCode)
        return MarkdownShortcutAction.allCases.first { action in
            let shortcut = shortcut(for: action)
            return shortcut.keyCode == keyCode && shortcut.modifiers == modifiers
        }
    }

    func editorAction(matching event: NSEvent) -> EditorShortcutAction? {
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        let keyCode = UInt32(event.keyCode)
        return EditorShortcutAction.allCases.first { action in
            let shortcut = shortcut(for: action)
            return shortcut.keyCode == keyCode && shortcut.modifiers == modifiers
        }
    }

    static var defaultMarkdownShortcuts: [MarkdownShortcutAction: MarkdownShortcut] {
        [
            .bold: MarkdownShortcut(keyCode: 11, modifiers: UInt32(cmdKey), keyEquivalent: "b"),
            .italic: MarkdownShortcut(keyCode: 34, modifiers: UInt32(cmdKey), keyEquivalent: "i"),
            .underline: MarkdownShortcut(keyCode: 32, modifiers: UInt32(cmdKey), keyEquivalent: "u"),
            .link: MarkdownShortcut(keyCode: 40, modifiers: UInt32(cmdKey), keyEquivalent: "k"),
            .inlineCode: MarkdownShortcut(keyCode: 50, modifiers: UInt32(controlKey), keyEquivalent: "`"),
            .inlineMath: MarkdownShortcut(keyCode: 46, modifiers: UInt32(controlKey), keyEquivalent: "m"),
            .strike: MarkdownShortcut(keyCode: 50, modifiers: UInt32(controlKey | shiftKey), keyEquivalent: "`"),
            .htmlComment: MarkdownShortcut(keyCode: 27, modifiers: UInt32(controlKey), keyEquivalent: "-")
        ]
    }

    static var defaultEditorShortcuts: [EditorShortcutAction: MarkdownShortcut] {
        [
            .markdownPreview: MarkdownShortcut(keyCode: 44, modifiers: UInt32(cmdKey), keyEquivalent: "/")
        ]
    }

    private static var defaultNewNoteShortcut: (keyCode: UInt32, modifiers: UInt32) {
        (keyCode: 6, modifiers: UInt32(controlKey | cmdKey))
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
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
        case 27: keyString = "-"
        case 31: keyString = "O"
        case 32: keyString = "U"
        case 34: keyString = "I"
        case 35: keyString = "P"
        case 36: keyString = "Return"
        case 37: keyString = "L"
        case 38: keyString = "J"
        case 40: keyString = "K"
        case 44: keyString = "/"
        case 45: keyString = "N"
        case 46: keyString = "M"
        case 48: keyString = "Tab"
        case 49: keyString = "Space"
        case 50: keyString = "`"
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

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyID = EventHotKeyID(signature: OSType(0x424B5730), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs[id] = ref
        }
    }

    private func persistMarkdownShortcuts() {
        let rawShortcuts = Dictionary(uniqueKeysWithValues: markdownShortcuts.map { ($0.key.rawValue, $0.value) })
        let data = try? JSONEncoder.encode(rawShortcuts)
        defaults.set(data, forKey: markdownShortcutDefaults)
    }

    private func persistEditorShortcuts() {
        let rawShortcuts = Dictionary(uniqueKeysWithValues: editorShortcuts.map { ($0.key.rawValue, $0.value) })
        let data = try? JSONEncoder.encode(rawShortcuts)
        defaults.set(data, forKey: editorShortcutDefaults)
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
        if hkID.id == ShortcutStore.HotKeyID.newNote {
            NotificationCenter.default.post(name: .macNewNote, object: nil)
        } else if hkID.id >= ShortcutStore.HotKeyID.openRecentBase + 1,
                  hkID.id <= ShortcutStore.HotKeyID.openRecentBase + 3 {
            let index = Int(hkID.id - ShortcutStore.HotKeyID.openRecentBase - 1)
            NotificationCenter.default.post(name: .macOpenRecentNote, object: index)
        } else if hkID.id == ShortcutStore.HotKeyID.activateMenu {
            NotificationCenter.default.post(name: .macActivateMenuBarMenu, object: nil)
        }
    }
    return noErr
}

extension Notification.Name {
    static let macNewNote = Notification.Name("macNewNote")
    static let macOpenRecentNote = Notification.Name("macOpenRecentNote")
    static let macActivateMenuBarMenu = Notification.Name("macActivateMenuBarMenu")
}
