import Foundation
import AppKit
import SwiftUI

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MacMenuBarController.shared
    private let shortcutStore = ShortcutStore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            menuBarController.statusItem?.button?.performClick(nil)
        }
        return true
    }
}
