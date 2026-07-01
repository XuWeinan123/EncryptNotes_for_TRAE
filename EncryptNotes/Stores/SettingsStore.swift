import Foundation
import SwiftUI
import Combine
#if os(macOS)
import ServiceManagement
#endif

enum MacTheme: String, CaseIterable, Identifiable, Codable {
    case pink
    case cyan
    case green

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green: return "绿色"
        case .pink: return "粉色"
        case .cyan: return "青色"
        }
    }
}

#if os(macOS)
enum MacAITitleProvider: String, CaseIterable, Identifiable, Codable {
    case deepSeek
    case gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .gemini: return "Gemini"
        }
    }

    var keychainAccount: String {
        switch self {
        case .deepSeek: return "mac.aiTitle.deepSeek"
        case .gemini: return "mac.aiTitle.gemini"
        }
    }
}
#endif

/// 用户偏好与隐私设置，基于 UserDefaults 持久化。
///
/// - seealso: PRD v0.2 5.6（新建模式持久记忆）、11.5（隐私保护）
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let macEditorFontSizeRange: ClosedRange<Double> = 12...18
    static let macEditorFontSizeStep: Double = 1
    static let defaultMacEditorFontSize: Double = 14
    static let defaultMacEditorLineHeightMultiple: Double = 1.25
    static let macEditorLineHeightRange: ClosedRange<Double> = 1.2...2.0
    static let defaultMacTheme: MacTheme = .pink
    static let macThemeDefaultsKey = "BKMacTheme"
    static let macRecentNotesLimitRange: ClosedRange<Int> = 3...12
    static let defaultMacRecentNotesLimit = 5
    #if os(macOS)
    static let defaultLaunchAtLogin = false
    static let defaultPinNewNotes = true
    static let defaultMacAITitleProvider: MacAITitleProvider = .deepSeek
    static let defaultMacAITitlePrompt = "请为以下笔记生成一个简洁标题，最多 20 个中文字符或 8 个英文单词。只返回标题，不要解释、不要引号、不要 Markdown。"
    #endif

    private let defaults: UserDefaults
    private let keychainStore: KeychainStore

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

    @Published var macEditorFontSize: Double {
        didSet {
            let clamped = Self.clampedFontSize(macEditorFontSize)
            if macEditorFontSize != clamped {
                macEditorFontSize = clamped
                return
            }
            defaults.set(macEditorFontSize, forKey: Keys.macEditorFontSize)
        }
    }

    @Published var macEditorLineHeightMultiple: Double {
        didSet {
            let clamped = Self.clampedLineHeightMultiple(macEditorLineHeightMultiple)
            if macEditorLineHeightMultiple != clamped {
                macEditorLineHeightMultiple = clamped
                return
            }
            defaults.set(macEditorLineHeightMultiple, forKey: Keys.macEditorLineHeightMultiple)
        }
    }

    @Published var copyAddsParagraphSpacing: Bool {
        didSet { defaults.set(copyAddsParagraphSpacing, forKey: Keys.copyAddsParagraphSpacing) }
    }

    @Published var autoDeleteEmptyNotes: Bool {
        didSet { defaults.set(autoDeleteEmptyNotes, forKey: Keys.autoDeleteEmptyNotes) }
    }

    @Published var macTheme: MacTheme {
        didSet { defaults.set(macTheme.rawValue, forKey: Self.macThemeDefaultsKey) }
    }

    @Published var macRecentNotesLimit: Int {
        didSet {
            let clamped = Self.clampedRecentNotesLimit(macRecentNotesLimit)
            if macRecentNotesLimit != clamped {
                macRecentNotesLimit = clamped
                return
            }
            defaults.set(macRecentNotesLimit, forKey: Keys.macRecentNotesLimit)
        }
    }

    #if os(macOS)
    @Published private(set) var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var pinNewNotesByDefault: Bool {
        didSet { defaults.set(pinNewNotesByDefault, forKey: Keys.pinNewNotesByDefault) }
    }

    @Published var macAITitleEnabled: Bool {
        didSet { defaults.set(macAITitleEnabled, forKey: Keys.macAITitleEnabled) }
    }

    @Published var macAITitleProvider: MacAITitleProvider {
        didSet { defaults.set(macAITitleProvider.rawValue, forKey: Keys.macAITitleProvider) }
    }

    @Published var macAITitlePrompt: String {
        didSet { defaults.set(macAITitlePrompt, forKey: Keys.macAITitlePrompt) }
    }

    @Published var macAITitleSkipsMarkdownHeading: Bool {
        didSet { defaults.set(macAITitleSkipsMarkdownHeading, forKey: Keys.macAITitleSkipsMarkdownHeading) }
    }
    #endif

    init(defaults: UserDefaults = .standard, keychainStore: KeychainStore? = nil) {
        self.defaults = defaults
        self.keychainStore = keychainStore ?? .shared
        self.preferredNoteMode = NoteMode(rawValue: defaults.string(forKey: Keys.preferredNoteMode) ?? "") ?? .plain
        self.hideContentOnBackground = defaults.object(forKey: Keys.hideContentOnBackground) as? Bool ?? true
        self.autoUnloadKeyOnForeground = defaults.object(forKey: Keys.autoUnloadKeyOnForeground) as? Bool ?? false
        self.hasSeenFirstKeyPrompt = defaults.bool(forKey: Keys.hasSeenFirstKeyPrompt)
        self.hasSeededDefaultNotes = defaults.bool(forKey: Keys.hasSeededDefaultNotes)

        let storedFontSize = defaults.double(forKey: Keys.macEditorFontSize)
        if storedFontSize > 0 {
            self.macEditorFontSize = Self.clampedFontSize(storedFontSize)
        } else {
            self.macEditorFontSize = Self.defaultMacEditorFontSize
        }

        let storedLineHeight = defaults.double(forKey: Keys.macEditorLineHeightMultiple)
        if storedLineHeight > 0 {
            self.macEditorLineHeightMultiple = Self.clampedLineHeightMultiple(storedLineHeight)
        } else {
            self.macEditorLineHeightMultiple = Self.defaultMacEditorLineHeightMultiple
        }

        self.copyAddsParagraphSpacing = defaults.object(forKey: Keys.copyAddsParagraphSpacing) as? Bool ?? false
        self.autoDeleteEmptyNotes = defaults.object(forKey: Keys.autoDeleteEmptyNotes) as? Bool ?? true
        self.macTheme = MacTheme(rawValue: defaults.string(forKey: Self.macThemeDefaultsKey) ?? "") ?? Self.defaultMacTheme
        let storedRecentNotesLimit = defaults.integer(forKey: Keys.macRecentNotesLimit)
        self.macRecentNotesLimit = storedRecentNotesLimit > 0
            ? Self.clampedRecentNotesLimit(storedRecentNotesLimit)
            : Self.defaultMacRecentNotesLimit
        #if os(macOS)
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? Self.defaultLaunchAtLogin
        self.pinNewNotesByDefault = defaults.object(forKey: Keys.pinNewNotesByDefault) as? Bool ?? Self.defaultPinNewNotes
        self.macAITitleEnabled = defaults.object(forKey: Keys.macAITitleEnabled) as? Bool ?? false
        self.macAITitleProvider = MacAITitleProvider(rawValue: defaults.string(forKey: Keys.macAITitleProvider) ?? "") ?? Self.defaultMacAITitleProvider
        let storedPrompt = defaults.string(forKey: Keys.macAITitlePrompt) ?? ""
        self.macAITitlePrompt = storedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultMacAITitlePrompt : storedPrompt
        self.macAITitleSkipsMarkdownHeading = defaults.object(forKey: Keys.macAITitleSkipsMarkdownHeading) as? Bool ?? false
        #endif
    }

    /// 用于测试：重置为默认值。
    func resetForTesting() {
        preferredNoteMode = .plain
        hideContentOnBackground = true
        autoUnloadKeyOnForeground = false
        hasSeenFirstKeyPrompt = false
        hasSeededDefaultNotes = false
        macEditorFontSize = Self.defaultMacEditorFontSize
        macEditorLineHeightMultiple = Self.defaultMacEditorLineHeightMultiple
        copyAddsParagraphSpacing = false
        autoDeleteEmptyNotes = true
        macTheme = Self.defaultMacTheme
        macRecentNotesLimit = Self.defaultMacRecentNotesLimit
        #if os(macOS)
        launchAtLogin = Self.defaultLaunchAtLogin
        pinNewNotesByDefault = Self.defaultPinNewNotes
        macAITitleEnabled = false
        macAITitleProvider = Self.defaultMacAITitleProvider
        macAITitlePrompt = Self.defaultMacAITitlePrompt
        macAITitleSkipsMarkdownHeading = false
        #endif
    }

    #if os(macOS)
    func setLaunchAtLogin(_ isEnabled: Bool) throws {
        do {
            if isEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            launchAtLogin = isEnabled
        } catch {
            throw error
        }
    }

    func resetMacAITitlePrompt() {
        macAITitlePrompt = Self.defaultMacAITitlePrompt
    }

    func saveMacAITitleAPIKey(_ key: String, for provider: MacAITitleProvider) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychainStore.deleteString(account: provider.keychainAccount)
        } else {
            try keychainStore.saveString(trimmed, account: provider.keychainAccount)
        }
        objectWillChange.send()
    }

    func loadMacAITitleAPIKey(for provider: MacAITitleProvider) -> String {
        (try? keychainStore.loadString(account: provider.keychainAccount)) ?? ""
    }

    func hasMacAITitleAPIKey(for provider: MacAITitleProvider) -> Bool {
        keychainStore.hasString(account: provider.keychainAccount)
    }
    #endif

    static func clampedFontSize(_ value: Double) -> Double {
        min(max(value.rounded(), macEditorFontSizeRange.lowerBound), macEditorFontSizeRange.upperBound)
    }

    static func clampedLineHeightMultiple(_ value: Double) -> Double {
        min(max(value, macEditorLineHeightRange.lowerBound), macEditorLineHeightRange.upperBound)
    }

    static func clampedRecentNotesLimit(_ value: Int) -> Int {
        min(max(value, macRecentNotesLimitRange.lowerBound), macRecentNotesLimitRange.upperBound)
    }

    private enum Keys {
        static let preferredNoteMode = "BKPreferredNoteMode"
        static let hideContentOnBackground = "BKHideContentOnBackground"
        static let autoUnloadKeyOnForeground = "BKAutoUnloadKeyOnForeground"
        static let hasSeenFirstKeyPrompt = "BKHasSeenFirstKeyPrompt"
        static let hasSeededDefaultNotes = "BKHasSeededDefaultNotes"
        static let macEditorFontSize = "BKMacEditorFontSize"
        static let macEditorLineHeightMultiple = "BKMacEditorLineHeightMultiple"
        static let copyAddsParagraphSpacing = "BKCopyAddsParagraphSpacing"
        static let autoDeleteEmptyNotes = "BKAutoDeleteEmptyNotes"
        static let macRecentNotesLimit = "BKMacRecentNotesLimit"
        #if os(macOS)
        static let launchAtLogin = "BKLaunchAtLogin"
        static let pinNewNotesByDefault = "BKPinNewNotesByDefault"
        static let macAITitleEnabled = "BKMacAITitleEnabled"
        static let macAITitleProvider = "BKMacAITitleProvider"
        static let macAITitlePrompt = "BKMacAITitlePrompt"
        static let macAITitleSkipsMarkdownHeading = "BKMacAITitleSkipsMarkdownHeading"
        #endif
    }
}
