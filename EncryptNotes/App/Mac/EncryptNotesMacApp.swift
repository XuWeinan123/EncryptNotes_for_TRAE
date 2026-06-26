import SwiftUI
import AppKit

@main
struct EncryptNotesMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            MacSettingsView()
        }
    }
}
