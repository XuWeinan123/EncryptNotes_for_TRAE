import Foundation
import SwiftUI
import Combine

/// 用户偏好与隐私设置，基于 UserDefaults 持久化。
///
/// - seealso: PRD v0.2 5.6（新建模式持久记忆）、11.5（隐私保护）
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    @Published var preferredNoteMode: NoteMode {
        didSet { defaults.set(preferredNoteMode.rawValue, forKey: Keys.preferredNoteMode) }
    }

    @Published var hideContentOnBackground: Bool {
        didSet { defaults.set(hideContentOnBackground, forKey: Keys.hideContentOnBackground) }
    }

    @Published var autoUnloadKeyOnForeground: Bool {
        didSet { defaults.set(autoUnloadKeyOnForeground, forKey: Keys.autoUnloadKeyOnForeground) }
    }

    @Published var hasSeenFirstKeyPrompt: Bool {
        didSet { defaults.set(hasSeenFirstKeyPrompt, forKey: Keys.hasSeenFirstKeyPrompt) }
    }

    @Published var hasSeededDefaultNotes: Bool {
        didSet { defaults.set(hasSeededDefaultNotes, forKey: Keys.hasSeededDefaultNotes) }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferredNoteMode = NoteMode(rawValue: defaults.string(forKey: Keys.preferredNoteMode) ?? "") ?? .plain
        self.hideContentOnBackground = defaults.object(forKey: Keys.hideContentOnBackground) as? Bool ?? true
        self.autoUnloadKeyOnForeground = defaults.object(forKey: Keys.autoUnloadKeyOnForeground) as? Bool ?? false
        self.hasSeenFirstKeyPrompt = defaults.bool(forKey: Keys.hasSeenFirstKeyPrompt)
        self.hasSeededDefaultNotes = defaults.bool(forKey: Keys.hasSeededDefaultNotes)
    }

    /// 用于测试：重置为默认值。
    func resetForTesting() {
        preferredNoteMode = .plain
        hideContentOnBackground = true
        autoUnloadKeyOnForeground = false
        hasSeenFirstKeyPrompt = false
        hasSeededDefaultNotes = false
    }

    private enum Keys {
        static let preferredNoteMode = "BKPreferredNoteMode"
        static let hideContentOnBackground = "BKHideContentOnBackground"
        static let autoUnloadKeyOnForeground = "BKAutoUnloadKeyOnForeground"
        static let hasSeenFirstKeyPrompt = "BKHasSeenFirstKeyPrompt"
        static let hasSeededDefaultNotes = "BKHasSeededDefaultNotes"
    }
}
