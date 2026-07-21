import Foundation
import SwiftUI
import Combine
#if os(iOS)
import UIKit
import LocalAuthentication
#endif

/// 监听 scenePhase，控制隐私遮罩与（iOS）离开 App 时的非破坏性会话锁。
@MainActor
final class AppLockStore: ObservableObject {
    static let shared = AppLockStore()

    @Published var showPrivacyScreen: Bool = false
    /// True when encrypted notes are locked and awaiting re-authentication (P0-4).
    @Published private(set) var isSessionLocked: Bool = false

    private let vaultStore: VaultStore
    private let settings = SettingsStore.shared
    #if os(iOS)
    private let shield = PrivacyShieldWindowController()
    #endif

    private init() {
        self.vaultStore = VaultStore.shared
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            showPrivacyScreen = false
            #if os(iOS)
            shield.hide()
            if isSessionLocked {
                Task { await unlock() }
            }
            #endif
            Task { await vaultStore.handleEnterForeground() }
        case .inactive:
            if settings.hideContentOnBackground {
                showPrivacyScreen = true
                #if os(iOS)
                shield.show()   // covers presented sheets/covers in the app-switcher snapshot
                #endif
            }
        case .background:
            if settings.hideContentOnBackground {
                showPrivacyScreen = true
                #if os(iOS)
                shield.show()
                #endif
            }
            vaultStore.handleEnterBackground()
            #if os(iOS)
            if settings.lockSessionOnBackground && vaultStore.encryptedEntryCount > 0 {
                isSessionLocked = true
                Task { await vaultStore.lockSession() }
            }
            #endif
        @unknown default:
            break
        }
    }

    #if os(iOS)
    /// Re-authenticate (Face ID / passcode) then reload the key. If the device has no
    /// passcode configured, unlock directly.
    func unlock() async {
        guard isSessionLocked else { return }
        let context = LAContext()
        var authError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
            let succeeded: Bool = await withCheckedContinuation { continuation in
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁加密笔记") { success, _ in
                    continuation.resume(returning: success)
                }
            }
            guard succeeded else { return }
        }
        // No passcode set, or authentication succeeded.
        try? await vaultStore.unlockSession()
        isSessionLocked = false
    }
    #endif
}

#if os(iOS)
/// A window layered above every presented sheet/cover that shows the privacy screen,
/// so the app-switcher snapshot never leaks note content. The in-view ZStack mask only
/// covers HomeView — presented sheets sit above it — so a window-level shield is needed (P0-4).
@MainActor
final class PrivacyShieldWindowController {
    private var window: UIWindow?

    func show() {
        if let window {
            window.isHidden = false
            return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            ?? scenes.first else {
            return
        }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.isUserInteractionEnabled = false
        window.rootViewController = UIHostingController(rootView: PrivacyScreenView())
        window.isHidden = false
        self.window = window
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}
#endif
