import SwiftUI
import AppKit

@main
struct SealNoteMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            MacSettingsView()
        }
    }
}
