import Foundation
import SwiftUI
import Combine

/// 监听 scenePhase，控制隐私遮罩与可选的自动卸载密钥。
@MainActor
final class AppLockStore: ObservableObject {
    static let shared = AppLockStore()

    @Published var showPrivacyScreen: Bool = false

    private let vaultStore: VaultStore
    private let settings = SettingsStore.shared

    private init() {
        self.vaultStore = VaultStore.shared
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            showPrivacyScreen = false
            Task { await vaultStore.handleEnterForeground() }
        case .inactive:
            if settings.hideContentOnBackground {
                showPrivacyScreen = true
            }
        case .background:
            if settings.hideContentOnBackground {
                showPrivacyScreen = true
            }
            vaultStore.handleEnterBackground()
        @unknown default:
            break
        }
    }
}
