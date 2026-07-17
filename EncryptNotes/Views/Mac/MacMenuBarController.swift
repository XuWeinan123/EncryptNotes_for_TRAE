import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacMenuBarController: NSObject, NSMenuDelegate {
    static let shared = MacMenuBarController()

    private static let allNotesFrameAutosaveName = "SealNote.AllNotesWindow"
    private static let trashFrameAutosaveName = "SealNote.TrashWindow"

    var statusItem: NSStatusItem?
    private let vaultStore = VaultStore.shared
    private let windowStore = MacNoteWindowStore.shared
    private let shortcutStore = ShortcutStore.shared
    private let settings = SettingsStore.shared

    private var allNotesWindow: NSWindow?
    private var trashWindow: NSWindow?
    private var componentCatalogWindow: NSWindow?
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange),
            name: .appLanguageDidChange,
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
            button.title = "SN"
            button.imagePosition = .noImage
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu(menu)
    }

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let newNoteShortcut = shortcutStore.newNoteShortcut
        let newNoteItem = NSMenuItem(
            title: L10n.string("New Note"),
            action: #selector(handleNewNote),
            keyEquivalent: newNoteShortcut.keyEquivalent
        )
        newNoteItem.keyEquivalentModifierMask = ShortcutStore.eventModifierFlags(
            from: newNoteShortcut.modifiers
        )
        newNoteItem.target = self
        menu.addItem(newNoteItem)

        menu.addItem(.separator())

        if case .loading = vaultStore.state {
            let loadingItem = NSMenuItem(title: L10n.string("Loading Notes…"), action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        } else {
            let recentItems = recentMenuNotes()

            for (index, recentItem) in recentItems.enumerated() {
                let item = menuItem(for: recentItem, index: index)
                menu.addItem(item)
            }

            if recentItems.isEmpty {
                let emptyItem = NSMenuItem(title: L10n.string("No Notes"), action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
            }
        }

        let allNotesItem = NSMenuItem(title: L10n.string("All Notes (%lld)…", Int64(vaultStore.totalNoteCount)), action: #selector(showAllNotes), keyEquivalent: "")
        allNotesItem.target = self
        menu.addItem(allNotesItem)

        menu.addItem(.separator())

        let trashItem = NSMenuItem(
            title: vaultStore.trashCount > 0
                ? L10n.string("Trash (%lld)…", Int64(vaultStore.trashCount))
                : L10n.string("Trash"),
            action: #selector(showTrash),
            keyEquivalent: ""
        )
        trashItem.target = self
        menu.addItem(trashItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L10n.string("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.string("Quit"), action: #selector(quitApp), keyEquivalent: "q")
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
        let snapshot = MacNoteListSnapshotBuilder.make(
            readableNotes: vaultStore.readableNotes,
            lockedEncryptedNotes: vaultStore.lockedEncryptedNotes,
            excludingHexColorsFromTags: settings.excludeHexColorsFromTags,
            titleProvider: { vaultStore.displayTitle(for: $0, emptyTitle: "") }
        )
        return snapshot.recentItems(limit: settings.macRecentNotesLimit).map { item in
            switch item {
            case .readable(let note): return .readable(note)
            case .locked(let info): return .locked(info)
            }
        }
    }

    private func menuItem(for recentItem: RecentMenuNote, index: Int) -> NSMenuItem {
        let item: NSMenuItem
        switch recentItem {
        case .readable(let note):
            let title = vaultStore.displayTitle(for: note, emptyTitle: NoteTitleFormatter.emptyTitle)
            item = NSMenuItem(title: "\(note.isEncrypted ? "🔒" : "📝") \(title)", action: #selector(openNote(_:)), keyEquivalent: "")
            item.representedObject = note.id
        case .locked(let info):
            item = NSMenuItem(title: "🔒 \(info.title)", action: #selector(openLockedNote(_:)), keyEquivalent: "")
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
        openSettingsWindow(selectedTab: .key)
    }

    @objc private func showAllNotes() {
        openAllNotesWindow()
    }

    func openAllNotesWindow() {
        if allNotesWindow == nil {
            let hostingView = NSHostingView(rootView: AppLocalizedRoot { AllNotesView() })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                styleMask: [.titled, .closable, .resizable, .unifiedTitleAndToolbar, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.string("All Notes")
            window.contentView = hostingView
            if !window.setFrameUsingName(Self.allNotesFrameAutosaveName) {
                window.center()
            }
            constrainToVisibleScreen(window)
            _ = window.setFrameAutosaveName(Self.allNotesFrameAutosaveName)
            window.isReleasedWhenClosed = false
            window.delegate = self
            configureListWindowChrome(window)
            allNotesWindow = window
        }
        if let allNotesWindow {
            constrainToVisibleScreen(allNotesWindow)
        }
        allNotesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showTrash() {
        openTrashWindow()
    }

    func openTrashWindow() {
        if trashWindow == nil {
            let hostingView = NSHostingView(rootView: AppLocalizedRoot { TrashView() })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                styleMask: [.titled, .closable, .resizable, .unifiedTitleAndToolbar, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.string("Trash")
            window.contentView = hostingView
            if !window.setFrameUsingName(Self.trashFrameAutosaveName) {
                window.center()
            }
            _ = window.setFrameAutosaveName(Self.trashFrameAutosaveName)
            window.isReleasedWhenClosed = false
            window.delegate = self
            configureListWindowChrome(window)
            trashWindow = window
        }
        trashWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() {
        openSettingsWindow()
    }

    func openSettingsWindow(selectedTab: MacSettingsView.Tab = .general) {
        MacMainMenuController.shared.openSettings(selectedTab: selectedTab)
    }

    func openComponentCatalogWindow() {
        if componentCatalogWindow == nil {
            let hostingView = NSHostingView(rootView: AppLocalizedRoot { MacComponentCatalogView() })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                styleMask: [.titled, .closable, .resizable, .unifiedTitleAndToolbar, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.string("View Components")
            window.contentView = hostingView
            window.contentMinSize = NSSize(width: 680, height: 560)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            configureListWindowChrome(window)
            componentCatalogWindow = window
        }
        componentCatalogWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func restoreDefaultWindowSizes() {
        NSWindow.removeFrame(usingName: Self.allNotesFrameAutosaveName)
        NSWindow.removeFrame(usingName: Self.trashFrameAutosaveName)

        allNotesWindow?.setContentSize(NSSize(width: 640, height: 720))
        trashWindow?.setContentSize(NSSize(width: 640, height: 720))
        componentCatalogWindow?.setContentSize(NSSize(width: 760, height: 720))

        windowStore.restoreDefaultWindowSizes()
        StickyNoteWindowManager.shared.restoreDefaultWindowSizes()
    }

    private func configureListWindowChrome(_ window: NSWindow) {
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    private func constrainToVisibleScreen(_ window: NSWindow) {
        let screen = window.screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })
            ?? NSScreen.main
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame.insetBy(dx: DS.s2, dy: DS.s2)
        var frame = window.frame
        frame.size.width = min(frame.width, visibleFrame.width)
        frame.size.height = min(frame.height, visibleFrame.height)
        frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
        window.setFrame(frame, display: false)
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
            let hostingView = NSHostingView(rootView: AppLocalizedRoot {
                MacIntroView {
                    window.close()
                }
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
        alert.messageText = L10n.string("Something Went Wrong")
        alert.informativeText = message
        alert.addButton(withTitle: L10n.string("OK"))
        alert.runModal()
    }

    @objc private func handleLanguageDidChange() {
        if let menu = statusItem?.menu {
            buildMenu(menu)
        }
        allNotesWindow?.title = L10n.string("All Notes")
        trashWindow?.title = L10n.string("Trash")
        componentCatalogWindow?.title = L10n.string("View Components")
        MacMainMenuController.shared.installMainMenu()
    }
}

extension MacMenuBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == allNotesWindow {
            allNotesWindow = nil
        } else if window == trashWindow {
            trashWindow = nil
        } else if window == componentCatalogWindow {
            componentCatalogWindow = nil
        } else if window == introWindow {
            introWindow = nil
        }
    }
}
