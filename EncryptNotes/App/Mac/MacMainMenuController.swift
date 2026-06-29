import Foundation
import AppKit
import SwiftUI

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
        menu.addItem(NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h", keyEquivalentModifierMask: [.command, .option]))
        menu.addItem(NSMenuItem(title: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func configureEditMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "撤销", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "重做", action: #selector(UndoManager.redo), keyEquivalent: "z", keyEquivalentModifierMask: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    }

    private func configureFormatMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let boldItem = NSMenuItem(title: "粗体", action: Selector(("markdownBold:")), keyEquivalent: "b")
        boldItem.target = nil
        menu.addItem(boldItem)

        let italicItem = NSMenuItem(title: "斜体", action: Selector(("markdownItalic:")), keyEquivalent: "i")
        italicItem.target = nil
        menu.addItem(italicItem)

        let underlineItem = NSMenuItem(title: "下划线", action: Selector(("markdownUnderline:")), keyEquivalent: "u")
        underlineItem.target = nil
        menu.addItem(underlineItem)

        menu.addItem(.separator())

        let codeItem = NSMenuItem(title: "行内代码", action: Selector(("markdownInlineCode:")), keyEquivalent: "`")
        codeItem.keyEquivalentModifierMask = .control
        codeItem.target = nil
        menu.addItem(codeItem)

        let mathItem = NSMenuItem(title: "行内公式", action: Selector(("markdownInlineMath:")), keyEquivalent: "m")
        mathItem.keyEquivalentModifierMask = .control
        mathItem.target = nil
        menu.addItem(mathItem)

        let strikeItem = NSMenuItem(title: "删除线", action: Selector(("markdownStrike:")), keyEquivalent: "`")
        strikeItem.keyEquivalentModifierMask = [.control, .shift]
        strikeItem.target = nil
        menu.addItem(strikeItem)

        let commentItem = NSMenuItem(title: "HTML 注释", action: Selector(("markdownHTMLComment:")), keyEquivalent: "-")
        commentItem.keyEquivalentModifierMask = .control
        commentItem.target = nil
        menu.addItem(commentItem)

        menu.addItem(.separator())

        let linkItem = NSMenuItem(title: "链接", action: Selector(("markdownLink:")), keyEquivalent: "k")
        linkItem.target = nil
        menu.addItem(linkItem)
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
