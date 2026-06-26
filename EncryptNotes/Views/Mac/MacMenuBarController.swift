import Foundation
import SwiftUI
import AppKit

@MainActor
final class MacMenuBarController: NSObject, NSMenuDelegate {
    static let shared = MacMenuBarController()

    var statusItem: NSStatusItem?
    private let vaultStore = VaultStore.shared
    private let windowStore = MacNoteWindowStore.shared
    private let shortcutStore = ShortcutStore.shared

    private var allNotesWindow: NSWindow?
    private var trashWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private override init() {
        super.init()
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "别看我")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu

        buildMenu(menu)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewPlainNote),
            name: .macNewPlainNote,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewEncryptedNote),
            name: .macNewEncryptedNote,
            object: nil
        )
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu(menu)
    }

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let newPlainItem = NSMenuItem(
            title: "新建明文笔记",
            action: #selector(handleNewPlainNote),
            keyEquivalent: "n"
        )
        newPlainItem.keyEquivalentModifierMask = [.option, .command]
        newPlainItem.target = self
        menu.addItem(newPlainItem)

        let newEncryptedItem = NSMenuItem(
            title: "新建加密笔记",
            action: #selector(handleNewEncryptedNote),
            keyEquivalent: "n"
        )
        newEncryptedItem.keyEquivalentModifierMask = [.option, .shift, .command]
        newEncryptedItem.target = self
        menu.addItem(newEncryptedItem)

        menu.addItem(.separator())

        let recentHeader = NSMenuItem(title: "最近笔记", action: nil, keyEquivalent: "")
        recentHeader.isEnabled = false
        menu.addItem(recentHeader)

        let recentNotes = Array(vaultStore.readableNotes.prefix(8))
        let lockedNotes = vaultStore.isKeyLoaded ? [] : Array(vaultStore.lockedEncryptedNotes.prefix(8))

        for note in recentNotes {
            let firstLine = note.body.components(separatedBy: .newlines).first { !$0.isEmpty } ?? "(空笔记)"
            let truncated = String(firstLine.prefix(40))
            let title = note.isEncrypted ? "🔒 \(truncated)" : "📝 \(truncated)"
            let item = NSMenuItem(title: title, action: #selector(openNote(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = note.id
            menu.addItem(item)
        }

        for info in lockedNotes.prefix(max(0, 8 - recentNotes.count)) {
            let item = NSMenuItem(title: "🔒 加密笔记 · 未加载密钥", action: #selector(openLockedNote(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = info.id
            menu.addItem(item)
        }

        if recentNotes.isEmpty && lockedNotes.isEmpty {
            let emptyItem = NSMenuItem(title: "暂无笔记", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(.separator())

        let allNotesItem = NSMenuItem(title: "全部笔记…", action: #selector(showAllNotes), keyEquivalent: "")
        allNotesItem.target = self
        menu.addItem(allNotesItem)

        let trashItem = NSMenuItem(
            title: "回收站…\(vaultStore.trashCount > 0 ? " (\(vaultStore.trashCount))" : "")",
            action: #selector(showTrash),
            keyEquivalent: ""
        )
        trashItem.target = self
        menu.addItem(trashItem)

        menu.addItem(.separator())

        if vaultStore.isKeyLoaded {
            let unloadKeyItem = NSMenuItem(title: "移除本机密钥", action: #selector(unloadKey), keyEquivalent: "")
            unloadKeyItem.target = self
            menu.addItem(unloadKeyItem)
        } else {
            let loadKeyItem = NSMenuItem(title: "加载密钥文件…", action: #selector(loadKeyFile), keyEquivalent: "")
            loadKeyItem.target = self
            menu.addItem(loadKeyItem)
        }

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出《别看我》", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func handleNewPlainNote() {
        Task {
            do {
                let note = try await vaultStore.createNote(body: "", isEncrypted: false)
                openStickyNote(for: note)
            } catch {
                showError(message: error.localizedDescription)
            }
        }
    }

    @objc private func handleNewEncryptedNote() {
        guard vaultStore.isKeyLoaded else {
            let alert = NSAlert()
            alert.messageText = "无法创建加密笔记"
            alert.informativeText = "加载密钥后才能创建加密笔记。"
            alert.addButton(withTitle: "加载密钥文件…")
            alert.addButton(withTitle: "创建新加密空间…")
            alert.addButton(withTitle: "取消")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                loadKeyFile()
            } else if response == .alertSecondButtonReturn {
                createNewVaultAndKey()
            }
            return
        }

        Task {
            do {
                let note = try await vaultStore.createNote(body: "", isEncrypted: true)
                openStickyNote(for: note)
            } catch {
                showError(message: error.localizedDescription)
            }
        }
    }

    private func createNewVaultAndKey() {
        let alert = NSAlert()
        alert.messageText = "创建新的加密空间？"
        alert.informativeText = "将生成新的密钥，你需要妥善保存密钥文件。如果 iCloud 中已有加密笔记，将无法使用新密钥解锁。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                do {
                    try await vaultStore.createKey()
                    let keyURL = try vaultStore.exportKeyFile()
                    await MainActor.run {
                        let savePanel = NSSavePanel()
                        savePanel.title = "保存密钥文件"
                        savePanel.message = "请立即将密钥文件保存到安全的位置。丢失密钥将无法解密加密笔记。密钥文件只会在本机读取，不会上传。"
                        savePanel.nameFieldStringValue = keyURL.lastPathComponent
                        savePanel.allowedContentTypes = [.init(filenameExtension: "bkwkey")!]
                        if savePanel.runModal() == .OK, let saveURL = savePanel.url {
                            try? FileManager.default.copyItem(at: keyURL, to: saveURL)
                        }
                        try? FileManager.default.removeItem(at: keyURL)

                        Task {
                            do {
                                let note = try await vaultStore.createNote(body: "", isEncrypted: true)
                                self.openStickyNote(for: note)
                            } catch {
                                self.showError(message: error.localizedDescription)
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.showError(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    @objc private func openNote(_ sender: NSMenuItem) {
        guard let noteId = sender.representedObject as? String,
              let note = vaultStore.readableNotes.first(where: { $0.id == noteId }) else { return }
        openStickyNote(for: note)
    }

    @objc private func openLockedNote(_ sender: NSMenuItem) {
        guard let noteId = sender.representedObject as? String,
              let info = vaultStore.lockedEncryptedNotes.first(where: { $0.id == noteId }) else { return }
        openLockedStickyNote(for: info)
    }

    func openStickyNote(for note: Note) {
        windowStore.openWindow(for: note.id, isEncrypted: note.isEncrypted)
        StickyNoteWindowManager.shared.showNote(note)
    }

    func openLockedStickyNote(for info: EncryptedNoteInfo) {
        windowStore.openWindow(for: info.id)
        StickyNoteWindowManager.shared.showLockedNote(info)
    }

    @objc func loadKeyFile() {
        let panel = NSOpenPanel()
        panel.title = "加载密钥文件"
        panel.message = "密钥文件只会在本机读取，不会上传。"
        panel.allowedContentTypes = [.init(filenameExtension: "bkwkey")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    _ = try await vaultStore.importKeyFile(from: url)
                } catch {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "无法加载密钥"
                        alert.informativeText = "无法使用这个密钥解锁当前加密空间。"
                        alert.addButton(withTitle: "确定")
                        alert.runModal()
                    }
                }
            }
        }
    }

    @objc private func showAllNotes() {
        if allNotesWindow == nil {
            let hostingView = NSHostingView(rootView: AllNotesView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "全部笔记"
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            allNotesWindow = window
        }
        allNotesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showTrash() {
        if trashWindow == nil {
            let hostingView = NSHostingView(rootView: TrashView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "回收站"
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            trashWindow = window
        }
        trashWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func unloadKey() {
        let alert = NSAlert()
        alert.messageText = "移除本机密钥？"
        alert.informativeText = "移除后，所有加密笔记将无法查看，直到重新加载密钥。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                try? await vaultStore.unloadKey()
                StickyNoteWindowManager.shared.closeAllWindows()
            }
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: MacSettingsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "设置"
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showError(message: String) {
        let alert = NSAlert()
        alert.messageText = "出错了"
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}

extension MacMenuBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == allNotesWindow {
            allNotesWindow = nil
        } else if window == trashWindow {
            trashWindow = nil
        } else if window == settingsWindow {
            settingsWindow = nil
        }
    }
}
