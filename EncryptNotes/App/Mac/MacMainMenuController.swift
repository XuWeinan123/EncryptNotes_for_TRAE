import Foundation
import AppKit
import SwiftUI
import Carbon

@MainActor
final class MacMainMenuController: NSObject {
    static let shared = MacMainMenuController()

    private override init() {
        super.init()
    }

    func installMainMenu() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        NSApp.mainMenu = mainMenu

        if let appMenu = mainMenu.items.first(where: { $0.submenu?.items.contains(where: { $0.action == #selector(NSApplication.terminate(_:)) }) ?? false })?.submenu {
            configureAppMenu(appMenu)
        } else {
            let appMenuItem = NSMenuItem()
            let appMenu = NSMenu()
            configureAppMenu(appMenu)
            appMenuItem.submenu = appMenu
            mainMenu.addItem(appMenuItem)
        }

        if let editMenu = findMenu(in: mainMenu, containing: #selector(NSText.paste(_:))) {
            configureEditMenu(editMenu)
        } else {
            let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
            let editMenu = NSMenu(title: "编辑")
            configureEditMenu(editMenu)
            editMenuItem.submenu = editMenu
            mainMenu.addItem(editMenuItem)
        }

        if let formatMenu = findMenu(in: mainMenu, named: "格式") ?? findMenu(in: mainMenu, named: "Format") {
            configureFormatMenu(formatMenu)
        } else {
            let formatMenuItem = NSMenuItem(title: "格式", action: nil, keyEquivalent: "")
            let formatMenu = NSMenu(title: "格式")
            configureFormatMenu(formatMenu)
            formatMenuItem.submenu = formatMenu
            mainMenu.addItem(formatMenuItem)
        }

        if let noteMenu = findMenu(in: mainMenu, named: "便签") {
            configureNoteMenu(noteMenu)
        } else {
            let noteMenuItem = NSMenuItem(title: "便签", action: nil, keyEquivalent: "")
            let noteMenu = NSMenu(title: "便签")
            configureNoteMenu(noteMenu)
            noteMenuItem.submenu = noteMenu
            mainMenu.addItem(noteMenuItem)
        }
    }

    private func findMenu(in mainMenu: NSMenu, containing action: Selector) -> NSMenu? {
        for item in mainMenu.items {
            if let submenu = item.submenu {
                if submenu.items.contains(where: { $0.action == action }) {
                    return submenu
                }
            }
        }
        return nil
    }

    private func findMenu(in mainMenu: NSMenu, named name: String) -> NSMenu? {
        for item in mainMenu.items {
            if let submenu = item.submenu, submenu.title == name {
                return submenu
            }
        }
        return nil
    }

    private func configureAppMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let appName = ProcessInfo.processInfo.processName

        menu.addItem(NSMenuItem(title: "关于 \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(MacMainMenuController.showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "隐藏 \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthersItem)
        menu.addItem(NSMenuItem(title: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func configureEditMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "撤销", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "重做", action: #selector(UndoManager.redo), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    }

    private func configureFormatMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        addMarkdownItem(.bold, to: menu)
        addMarkdownItem(.italic, to: menu)
        addMarkdownItem(.underline, to: menu)

        menu.addItem(.separator())

        addMarkdownItem(.inlineCode, to: menu)
        addMarkdownItem(.inlineMath, to: menu)
        addMarkdownItem(.strike, to: menu)
        addMarkdownItem(.htmlComment, to: menu)

        menu.addItem(.separator())

        addMarkdownItem(.link, to: menu)
    }

    private func addMarkdownItem(_ action: MarkdownShortcutAction, to menu: NSMenu) {
        let shortcut = ShortcutStore.shared.shortcut(for: action)
        let item = NSMenuItem(title: action.title, action: action.selector, keyEquivalent: shortcut.keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask(from: shortcut.modifiers)
        item.target = nil
        menu.addItem(item)
    }

    private func modifierMask(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    private func configureNoteMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let saveItem = NSMenuItem(title: "保存", action: Selector(("markdownSave:")), keyEquivalent: "s")
        saveItem.target = nil
        menu.addItem(saveItem)

        let applyItem = NSMenuItem(title: "应用并保持打开", action: Selector(("markdownApply:")), keyEquivalent: "s")
        applyItem.keyEquivalentModifierMask = [.command, .shift]
        applyItem.target = nil
        menu.addItem(applyItem)

        menu.addItem(.separator())

        let fitItem = NSMenuItem(title: "适应内容", action: Selector(("markdownFitToContent:")), keyEquivalent: "f")
        fitItem.keyEquivalentModifierMask = [.command, .option]
        fitItem.target = nil
        menu.addItem(fitItem)
    }

    @objc private func showSettings(_ sender: Any?) {
        MacMenuBarController.shared.openSettingsWindow()
    }
}
