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

#if os(iOS)
enum IOSAppIconChoice: String, CaseIterable, Identifiable {
    case primary
    case cyan
    case green

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary: return "粉色"
        case .cyan: return "青色"
        case .green: return "绿色"
        }
    }

    var iconName: String? {
        switch self {
        case .primary: return nil
        case .cyan: return "Icon2"
        case .green: return "Icon3"
        }
    }

    static func choice(for iconName: String?) -> IOSAppIconChoice {
        switch iconName {
        case "Icon2": return .cyan
        case "Icon3": return .green
        default: return .primary
        }
    }
}
#endif

#if os(macOS)
struct VaultKeyFileReference: Codable, Equatable {
    let bookmarkData: Data
    let displayPath: String
    let keyId: String?
    let keyFingerprint: String?

    init(bookmarkData: Data, displayPath: String, keyId: String? = nil, keyFingerprint: String? = nil) {
        self.bookmarkData = bookmarkData
        self.displayPath = displayPath
        self.keyId = keyId
        self.keyFingerprint = keyFingerprint
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
    static let defaultMacEditorLineHeightMultiple: Double = 1.5
    static let macEditorLineHeightRange: ClosedRange<Double> = 1.2...2.0
    static let defaultMacTheme: MacTheme = .pink
    static let macThemeDefaultsKey = "SNMacTheme"
    static let macRecentNotesLimitOptions = [5, 10, 15]
    static let defaultMacRecentNotesLimit = 5
    #if os(macOS)
    static let defaultLaunchAtLogin = false
    static let defaultPinNewNotes = true
    static let defaultLockEncryptedNotesOnSleep = true
    static let defaultLockUnpinnedEncryptedNotesOnBackground = true
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

    @Published var autoRenameNotesOnSave: Bool {
        didSet { defaults.set(autoRenameNotesOnSave, forKey: Keys.autoRenameNotesOnSave) }
    }

    @Published var excludeHexColorsFromTags: Bool {
        didSet { defaults.set(excludeHexColorsFromTags, forKey: Keys.excludeHexColorsFromTags) }
    }

    @Published var maintenanceLoggingEnabled: Bool {
        didSet {
            defaults.set(maintenanceLoggingEnabled, forKey: Keys.maintenanceLoggingEnabled)
            MaintenanceLogStore.shared.record(
                maintenanceLoggingEnabled ? "maintenance_logging_enabled" : "maintenance_logging_disabled"
            )
        }
    }

    @Published var macTheme: MacTheme {
        didSet {
            defaults.set(macTheme.rawValue, forKey: Self.macThemeDefaultsKey)
            #if os(macOS)
            MacAppIconController.shared.apply(theme: macTheme)
            #endif
        }
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

    @Published var iOSAppIconName: String? {
        didSet {
            if let iOSAppIconName {
                defaults.set(iOSAppIconName, forKey: Keys.iOSAppIconName)
            } else {
                defaults.removeObject(forKey: Keys.iOSAppIconName)
            }
        }
    }

    #if os(macOS)
    @Published private(set) var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var pinNewNotesByDefault: Bool {
        didSet { defaults.set(pinNewNotesByDefault, forKey: Keys.pinNewNotesByDefault) }
    }

    @Published var lockEncryptedNotesOnSleep: Bool {
        didSet { defaults.set(lockEncryptedNotesOnSleep, forKey: Keys.lockEncryptedNotesOnSleep) }
    }

    @Published var lockUnpinnedEncryptedNotesOnBackground: Bool {
        didSet { defaults.set(lockUnpinnedEncryptedNotesOnBackground, forKey: Keys.lockUnpinnedEncryptedNotesOnBackground) }
    }

    @Published private(set) var vaultKeyFileReference: VaultKeyFileReference? {
        didSet {
            if let vaultKeyFileReference,
               let data = try? JSONEncoder.default.encode(vaultKeyFileReference) {
                defaults.set(data, forKey: Keys.vaultKeyFileReference)
            } else {
                defaults.removeObject(forKey: Keys.vaultKeyFileReference)
            }
        }
    }

    @Published var hideMacIntroOnLaunch: Bool {
        didSet { defaults.set(hideMacIntroOnLaunch, forKey: Keys.hideMacIntroOnLaunch) }
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
        self.autoRenameNotesOnSave = defaults.object(forKey: Keys.autoRenameNotesOnSave) as? Bool ?? false
        self.excludeHexColorsFromTags = defaults.object(forKey: Keys.excludeHexColorsFromTags) as? Bool ?? true
        self.maintenanceLoggingEnabled = defaults.object(forKey: Keys.maintenanceLoggingEnabled) as? Bool ?? false
        self.macTheme = MacTheme(rawValue: defaults.string(forKey: Self.macThemeDefaultsKey) ?? "") ?? Self.defaultMacTheme
        let storedRecentNotesLimit = defaults.integer(forKey: Keys.macRecentNotesLimit)
        self.macRecentNotesLimit = storedRecentNotesLimit > 0
            ? Self.clampedRecentNotesLimit(storedRecentNotesLimit)
            : Self.defaultMacRecentNotesLimit
        self.iOSAppIconName = defaults.string(forKey: Keys.iOSAppIconName)
        #if os(macOS)
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? Self.defaultLaunchAtLogin
        self.pinNewNotesByDefault = defaults.object(forKey: Keys.pinNewNotesByDefault) as? Bool ?? Self.defaultPinNewNotes
        self.lockEncryptedNotesOnSleep = defaults.object(forKey: Keys.lockEncryptedNotesOnSleep) as? Bool ?? Self.defaultLockEncryptedNotesOnSleep
        self.lockUnpinnedEncryptedNotesOnBackground = defaults.object(forKey: Keys.lockUnpinnedEncryptedNotesOnBackground) as? Bool ?? Self.defaultLockUnpinnedEncryptedNotesOnBackground
        if let referenceData = defaults.data(forKey: Keys.vaultKeyFileReference),
           let reference = try? JSONDecoder.default.decode(VaultKeyFileReference.self, from: referenceData) {
            self.vaultKeyFileReference = reference
        } else {
            self.vaultKeyFileReference = nil
        }
        self.hideMacIntroOnLaunch = defaults.object(forKey: Keys.hideMacIntroOnLaunch) as? Bool ?? false
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
        autoRenameNotesOnSave = false
        excludeHexColorsFromTags = true
        maintenanceLoggingEnabled = false
        macTheme = Self.defaultMacTheme
        macRecentNotesLimit = Self.defaultMacRecentNotesLimit
        iOSAppIconName = nil
        #if os(macOS)
        launchAtLogin = Self.defaultLaunchAtLogin
        pinNewNotesByDefault = Self.defaultPinNewNotes
        lockEncryptedNotesOnSleep = Self.defaultLockEncryptedNotesOnSleep
        lockUnpinnedEncryptedNotesOnBackground = Self.defaultLockUnpinnedEncryptedNotesOnBackground
        clearVaultKeyFileReference()
        hideMacIntroOnLaunch = false
        #endif
    }

    #if os(macOS)
    /// 恢复用户可配置偏好与首次使用提示；不改动笔记、密钥或密钥文件关联。
    func restoreAllDefaults() throws {
        if launchAtLogin {
            try setLaunchAtLogin(Self.defaultLaunchAtLogin)
        }

        preferredNoteMode = .plain
        hideContentOnBackground = true
        autoUnloadKeyOnForeground = false
        hasSeenFirstKeyPrompt = false
        macEditorFontSize = Self.defaultMacEditorFontSize
        macEditorLineHeightMultiple = Self.defaultMacEditorLineHeightMultiple
        copyAddsParagraphSpacing = false
        autoDeleteEmptyNotes = true
        autoRenameNotesOnSave = false
        excludeHexColorsFromTags = true
        maintenanceLoggingEnabled = false
        macTheme = Self.defaultMacTheme
        macRecentNotesLimit = Self.defaultMacRecentNotesLimit
        pinNewNotesByDefault = Self.defaultPinNewNotes
        lockEncryptedNotesOnSleep = Self.defaultLockEncryptedNotesOnSleep
        lockUnpinnedEncryptedNotesOnBackground = Self.defaultLockUnpinnedEncryptedNotesOnBackground
        hideMacIntroOnLaunch = false
    }
    #endif

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

    func saveVaultKeyFileReference(for url: URL, keyId: String? = nil, keyFingerprint: String? = nil) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        vaultKeyFileReference = VaultKeyFileReference(
            bookmarkData: bookmarkData,
            displayPath: url.path,
            keyId: keyId,
            keyFingerprint: keyFingerprint
        )
    }

    func resolveVaultKeyFileURL() throws -> (url: URL, isStale: Bool) {
        guard let reference = vaultKeyFileReference else {
            throw CryptoError.keyNotFound
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: reference.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    func clearVaultKeyFileReference() {
        vaultKeyFileReference = nil
    }

    #endif

    static func clampedFontSize(_ value: Double) -> Double {
        min(max(value.rounded(), macEditorFontSizeRange.lowerBound), macEditorFontSizeRange.upperBound)
    }

    static func clampedLineHeightMultiple(_ value: Double) -> Double {
        min(max(value, macEditorLineHeightRange.lowerBound), macEditorLineHeightRange.upperBound)
    }

    static func clampedRecentNotesLimit(_ value: Int) -> Int {
        macRecentNotesLimitOptions.min { abs($0 - value) < abs($1 - value) }
            ?? defaultMacRecentNotesLimit
    }

    private enum Keys {
        static let preferredNoteMode = "SNPreferredNoteMode"
        static let hideContentOnBackground = "SNHideContentOnBackground"
        static let autoUnloadKeyOnForeground = "SNAutoUnloadKeyOnForeground"
        static let hasSeenFirstKeyPrompt = "SNHasSeenFirstKeyPrompt"
        static let hasSeededDefaultNotes = "SNHasSeededDefaultNotes"
        static let macEditorFontSize = "SNMacEditorFontSize"
        static let macEditorLineHeightMultiple = "SNMacEditorLineHeightMultiple"
        static let copyAddsParagraphSpacing = "SNCopyAddsParagraphSpacing"
        static let autoDeleteEmptyNotes = "SNAutoDeleteEmptyNotes"
        static let autoRenameNotesOnSave = "SNAutoRenameNotesOnSave"
        static let excludeHexColorsFromTags = "SNExcludeHexColorsFromTags"
        static let maintenanceLoggingEnabled = "SNMaintenanceLoggingEnabled"
        static let macRecentNotesLimit = "SNMacRecentNotesLimit"
        static let iOSAppIconName = "SNIOSAppIconName"
        #if os(macOS)
        static let launchAtLogin = "SNLaunchAtLogin"
        static let pinNewNotesByDefault = "SNPinNewNotesByDefault"
        static let lockEncryptedNotesOnSleep = "SNLockEncryptedNotesOnSleep"
        static let lockUnpinnedEncryptedNotesOnBackground = "SNLockUnpinnedEncryptedNotesOnBackground"
        static let vaultKeyFileReference = "SNVaultKeyFileReference"
        static let hideMacIntroOnLaunch = "SNHideMacIntroOnLaunch"
        #endif
    }
}
