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
        _ = shortcutStore

        Task {
            await VaultStore.shared.initialize()
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
