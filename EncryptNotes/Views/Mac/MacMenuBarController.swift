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
    private var introWindow: NSWindow?

    private enum RecentMenuNote {
        case readable(Note)
        case locked(EncryptedNoteInfo)
    }

    private override init() {
        super.init()
    }

    func setup() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }

        statusItem?.isVisible = true
        statusItem?.length = NSStatusItem.squareLength

        if let button = statusItem?.button {
            configureStatusButton(button)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenRecentNote(_:)),
            name: .macOpenRecentNote,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleActivateMenuBarMenu),
            name: .macActivateMenuBarMenu,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureStatusButton(_ button: NSStatusBarButton) {
        button.toolTip = "Seal Note"
        button.imageScaling = .scaleProportionallyDown
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)

        if let image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Seal Note") {
            image.isTemplate = true
            button.title = ""
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            statusItem?.length = NSStatusItem.variableLength
            button.image = nil
            button.title = "别"
            button.imagePosition = .noImage
        }
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

        if case .loading = vaultStore.state {
            let loadingItem = NSMenuItem(title: "正在加载笔记…", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        } else {
            let recentItems = recentMenuNotes()

            for (index, recentItem) in recentItems.enumerated() {
                let item = menuItem(for: recentItem, index: index)
                menu.addItem(item)
            }

            if recentItems.isEmpty {
                let emptyItem = NSMenuItem(title: "暂无笔记", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
            }
        }

        let allNotesItem = NSMenuItem(title: "全部笔记…", action: #selector(showAllNotes), keyEquivalent: "")
        allNotesItem.target = self
        menu.addItem(allNotesItem)

        menu.addItem(.separator())

        let trashItem = NSMenuItem(
            title: "回收站…\(vaultStore.trashCount > 0 ? " (\(vaultStore.trashCount))" : "")",
            action: #selector(showTrash),
            keyEquivalent: ""
        )
        trashItem.target = self
        menu.addItem(trashItem)

        menu.addItem(.separator())

        if vaultStore.isKeyLoaded {
            let unloadKeyItem = NSMenuItem(title: "移除密钥引用", action: #selector(unloadKey), keyEquivalent: "")
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

        let quitItem = NSMenuItem(title: "退出Seal Note", action: #selector(quitApp), keyEquivalent: "q")
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
                    StickyNoteWindowManager.shared.showNote(note, at: mouseLocation, remembersNewNoteSize: true)
                }
            } catch {
                await MainActor.run {
                    showError(message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func handleOpenRecentNote(_ notification: Notification) {
        guard let index = notification.object as? Int else { return }
        openRecentNote(at: index)
    }

    @objc private func handleActivateMenuBarMenu() {
        NSApp.activate(ignoringOtherApps: true)
        statusItem?.button?.performClick(nil)
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

    private func recentMenuNotes() -> [RecentMenuNote] {
        let limit = settings.macRecentNotesLimit
        var items = vaultStore.readableNotes.prefix(limit).map { RecentMenuNote.readable($0) }
        if items.count < limit {
            let remaining = limit - items.count
            items.append(contentsOf: vaultStore.lockedEncryptedNotes.prefix(remaining).map { .locked($0) })
        }
        return items
    }

    private func menuItem(for recentItem: RecentMenuNote, index: Int) -> NSMenuItem {
        let item: NSMenuItem
        switch recentItem {
        case .readable(let note):
            let title = vaultStore.displayTitle(for: note, emptyTitle: "(空笔记)")
            let truncated = String(title.prefix(30))
            item = NSMenuItem(title: "\(note.isEncrypted ? "🔒" : "📝") \(truncated)", action: #selector(openNote(_:)), keyEquivalent: "")
            item.representedObject = note.id
        case .locked(let info):
            let truncated = String(info.title.prefix(30))
            item = NSMenuItem(title: "🔒 \(truncated)", action: #selector(openLockedNote(_:)), keyEquivalent: "")
            item.representedObject = info.id
        }
        if index < 3 {
            item.keyEquivalent = "\(index + 1)"
            item.keyEquivalentModifierMask = [.control, .command]
        }
        item.target = self
        return item
    }

    private func openRecentNote(at index: Int) {
        let items = recentMenuNotes()
        guard items.indices.contains(index) else { return }
        switch items[index] {
        case .readable(let note):
            openStickyNote(for: note)
        case .locked(let info):
            openLockedStickyNote(for: info)
        }
    }

    func openStickyNote(for note: Note) {
        windowStore.openWindow(for: note.id, isEncrypted: note.isEncrypted)
        StickyNoteWindowManager.shared.showNote(note)
    }

    func openLockedStickyNote(for info: EncryptedNoteInfo) {
        Task { @MainActor in
            do {
                let note = try await vaultStore.openEncryptedNote(info)
                openStickyNote(for: note)
            } catch {
                windowStore.openWindow(for: info.id)
                StickyNoteWindowManager.shared.showLockedNote(info, keyIssue: error)
            }
        }
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
        openAllNotesWindow()
    }

    func openAllNotesWindow() {
        if allNotesWindow == nil {
            let hostingView = NSHostingView(rootView: AllNotesView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
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
        openTrashWindow()
    }

    func openTrashWindow() {
        if trashWindow == nil {
            let hostingView = NSHostingView(rootView: TrashView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
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
        alert.messageText = "移除密钥前如何处理加密笔记？"
        alert.informativeText = "删除会永久移除加密笔记；解密和导出都需要当前密钥文件可用且匹配。"
        alert.addButton(withTitle: "永久删除加密笔记")
        alert.addButton(withTitle: "全部解密为明文")
        alert.addButton(withTitle: "解密导出并移除本地")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            confirmPermanentDeleteEncryptedNotes()
        case .alertSecondButtonReturn:
            Task { await runKeyRemovalAction { try await self.vaultStore.decryptAllEncryptedNotesAndRemoveKey() } }
        case .alertThirdButtonReturn:
            exportPlaintextAndRemoveEncryptedNotes()
        default:
            break
        }
    }

    private func confirmPermanentDeleteEncryptedNotes() {
        let alert = NSAlert()
        alert.messageText = "永久删除所有加密笔记？"
        alert.informativeText = "这个操作不会移到回收站，删除后无法恢复。"
        alert.addButton(withTitle: "永久删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await runKeyRemovalAction { try await self.vaultStore.permanentlyDeleteAllEncryptedNotes() } }
    }

    private func exportPlaintextAndRemoveEncryptedNotes() {
        let panel = NSSavePanel()
        panel.title = "导出解密后的明文笔记"
        panel.message = "导出成功后，本地加密笔记会被永久移除。"
        panel.nameFieldStringValue = "Seal Note-解密笔记.zip"
        panel.allowedContentTypes = [.init(filenameExtension: "zip")!]
        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        Task {
            do {
                _ = try await vaultStore.exportPlaintextEncryptedNotesAndRemoveLocalNotes(to: saveURL)
                StickyNoteWindowManager.shared.closeAllWindows()
            } catch {
                await MainActor.run {
                    showError(message: error.localizedDescription)
                }
            }
        }
    }

    private func runKeyRemovalAction(_ action: @escaping () async throws -> Int) async {
        do {
            _ = try await action()
            StickyNoteWindowManager.shared.closeAllWindows()
        } catch {
            await MainActor.run {
                showError(message: error.localizedDescription)
            }
        }
    }

    @objc private func showSettings() {
        openSettingsWindow()
    }

    func openSettingsWindow() {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: MacSettingsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 660),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "设置"
            window.contentView = hostingView
            window.contentMinSize = NSSize(width: 640, height: 660)
            window.contentMaxSize = NSSize(width: 640, height: 660)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openIntroWindowIfNeeded() {
        guard !settings.hideMacIntroOnLaunch else { return }
        if introWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 720),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            let hostingView = NSHostingView(rootView: MacIntroView {
                window.close()
            })
            window.title = ""
            window.contentView = hostingView
            window.contentMinSize = NSSize(width: 620, height: 720)
            window.contentMaxSize = NSSize(width: 620, height: 720)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            introWindow = window
        }
        introWindow?.makeKeyAndOrderFront(nil)
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
        } else if window == introWindow {
            introWindow = nil
        }
    }
}
