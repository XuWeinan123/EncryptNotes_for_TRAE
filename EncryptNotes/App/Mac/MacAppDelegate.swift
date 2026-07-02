import Foundation
import AppKit
import SwiftUI

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MacMenuBarController.shared
    private let shortcutStore = ShortcutStore.shared
    private let privacyLockCoordinator = MacPrivacyLockCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        privacyLockCoordinator.start()
        menuBarController.setup()
        MacMainMenuController.shared.installMainMenu()
        _ = shortcutStore
        menuBarController.openIntroWindowIfNeeded()

        Task {
            await VaultStore.shared.initialize()
            #if DEBUG
            if CommandLine.arguments.contains("--open-recent-note"),
               let note = VaultStore.shared.readableNotes.first(where: {
                   !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
               }) {
                StickyNoteWindowManager.shared.showNote(note)
            }
            if CommandLine.arguments.contains("--open-review-windows") {
                await MainActor.run {
                    menuBarController.openAllNotesWindow()
                    menuBarController.openTrashWindow()
                    menuBarController.openSettingsWindow()
                }
            }
            #endif
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        StickyNoteWindowManager.shared.closeAllWindows()
        shortcutStore.unregisterHotKeys()
        privacyLockCoordinator.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            menuBarController.statusItem?.button?.performClick(nil)
        }
        return true
    }
}

@MainActor
private final class MacPrivacyLockCoordinator {
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        observers = names.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    guard SettingsStore.shared.lockEncryptedNotesOnSleep else { return }
                    StickyNoteWindowManager.shared.temporarilyLockAllEncryptedNoteWindows()
                }
            }
        }
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspaceCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
}
