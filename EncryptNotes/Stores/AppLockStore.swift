import Foundation
import SwiftUI

@MainActor
final class AppLockStore: ObservableObject {
    static let shared = AppLockStore()

    @Published var isLocked: Bool = false
    @Published var showPrivacyScreen: Bool = false

    private let vaultStore: VaultStore

    private init() {
        self.vaultStore = VaultStore.shared
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            showPrivacyScreen = false
        case .inactive:
            showPrivacyScreen = true
        case .background:
            showPrivacyScreen = true
            vaultStore.lock()
            isLocked = true
        @unknown default:
            break
        }
    }

    func unlock() {
        isLocked = false
    }
}
