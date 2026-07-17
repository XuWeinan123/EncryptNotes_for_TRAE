import SwiftUI
import AppKit

@main
struct EncryptNotesMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    @ObservedObject private var settingsRouter = MacSettingsRouter.shared

    var body: some Scene {
        Settings {
            AppLocalizedRoot {
                MacSettingsView(selectedTab: $settingsRouter.selectedTab)
            }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink()
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
