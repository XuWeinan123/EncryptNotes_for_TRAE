import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacMenuBarController: NSObject, NSMenuDelegate {
    static let shared = MacMenuBarController()

    var statusItem: NSStatusItem?
    private let vaultStore = VaultStore.shared
    private let windowStore = MacNoteWindowStore.shared
    private let shortcutStore = ShortcutStore.shared
    private let settings = SettingsStore.shared

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
            selector: #selector(handleNewNote),
            name: .macNewNote,
            object: nil
        )
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu(menu)
    }

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let newNoteItem = NSMenuItem(
            title: "新建笔记",
            action: #selector(handleNewNote),
            keyEquivalent: "z"
        )
        newNoteItem.keyEquivalentModifierMask = [.control, .command]
        newNoteItem.target = self
        menu.addItem(newNoteItem)

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

    @objc private func handleNewNote() {
        let mouseLocation = StickyNoteWindowManager.currentMouseLocation()
        let wantEncrypted = vaultStore.isKeyLoaded && settings.preferredNoteMode == .encrypted

        Task {
            do {
                let note = try await vaultStore.createNote(body: "", isEncrypted: wantEncrypted)
                await MainActor.run {
                    StickyNoteWindowManager.shared.showNote(note, at: mouseLocation)
                }
            } catch {
                await MainActor.run {
                    if case VaultError.freeLimitReached = error {
                        showError(message: "免费版最多保存 20 条笔记，请先删除部分笔记或升级 Pro。")
                    } else {
                        showError(message: error.localizedDescription)
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
