import Foundation
import SwiftUI
import Combine
#if os(macOS)
import ServiceManagement
#endif

enum AppTheme: String, CaseIterable, Identifiable, Codable {
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

    static let editorFontSizeRange: ClosedRange<Double> = 12...18
    static let editorFontSizeStep: Double = 1
    static let defaultEditorFontSize: Double = 14
    static let defaultEditorLineHeightMultiple: Double = 1.5
    static let editorLineHeightRange: ClosedRange<Double> = 1.2...2.0
    static let defaultAppTheme: AppTheme = .pink
    static let macThemeDefaultsKey = "SNMacTheme"
    static let macRecentNotesLimitOptions = [5, 10, 15]
    static let defaultMacRecentNotesLimit = 5
    #if os(macOS)
    static let defaultLaunchAtLogin = false
    static let defaultPinNewNotes = true
    static let defaultLockEncryptedNotesOnSleep = true
    static let defaultLockUnpinnedEncryptedNotesOnBackground = true
    static let defaultCLIAccessEnabled = false
    static let defaultCLIEncryptedAccessEnabled = false
    #endif

    private let defaults: UserDefaults
    private let keychainStore: KeychainStore

    @Published var preferredNoteMode: NoteMode {
        didSet { defaults.set(preferredNoteMode.rawValue, forKey: Keys.preferredNoteMode) }
    }

    @Published var hideContentOnBackground: Bool {
        didSet { defaults.set(hideContentOnBackground, forKey: Keys.hideContentOnBackground) }
    }

    // ponytail: dead setting — retained only because tests reference it; the destructive
    // foreground auto-unload it drove was removed in favor of lockSession (P0-4).
    @Published var autoUnloadKeyOnForeground: Bool {
        didSet { defaults.set(autoUnloadKeyOnForeground, forKey: Keys.autoUnloadKeyOnForeground) }
    }

    /// When set, encrypted notes are locked (the in-memory key is forgotten, Keychain
    /// untouched) each time the app leaves the foreground, requiring re-authentication on
    /// return (P0-4). Default off.
    @Published var lockSessionOnBackground: Bool {
        didSet { defaults.set(lockSessionOnBackground, forKey: Keys.lockSessionOnBackground) }
    }

    @Published var hasSeenFirstKeyPrompt: Bool {
        didSet { defaults.set(hasSeenFirstKeyPrompt, forKey: Keys.hasSeenFirstKeyPrompt) }
    }

    @Published var hasSeededDefaultNotes: Bool {
        didSet { defaults.set(hasSeededDefaultNotes, forKey: Keys.hasSeededDefaultNotes) }
    }

    /// Persisted mirror of `VaultStore.needsKeyExport` so the "save your key" prompt
    /// survives relaunch until the user actually exports (P0-1).
    @Published var needsKeyExportPending: Bool {
        didSet { defaults.set(needsKeyExportPending, forKey: Keys.needsKeyExportPending) }
    }

    /// Which storage root the vault is pinned to: "icloud", "local", or nil (not yet
    /// decided). Pinning stops the vault from silently forking to local when iCloud
    /// briefly disappears, and back again (P0-3).
    @Published var pinnedStorageRoot: String? {
        didSet {
            if let pinnedStorageRoot {
                defaults.set(pinnedStorageRoot, forKey: Keys.pinnedStorageRoot)
            } else {
                defaults.removeObject(forKey: Keys.pinnedStorageRoot)
            }
        }
    }

    @Published var editorFontSize: Double {
        didSet {
            let clamped = Self.clampedFontSize(editorFontSize)
            if editorFontSize != clamped {
                editorFontSize = clamped
                return
            }
            defaults.set(editorFontSize, forKey: Keys.editorFontSize)
        }
    }

    @Published var editorLineHeightMultiple: Double {
        didSet {
            let clamped = Self.clampedLineHeightMultiple(editorLineHeightMultiple)
            if editorLineHeightMultiple != clamped {
                editorLineHeightMultiple = clamped
                return
            }
            defaults.set(editorLineHeightMultiple, forKey: Keys.editorLineHeightMultiple)
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

    @Published var appTheme: AppTheme {
        didSet {
            defaults.set(appTheme.rawValue, forKey: Self.macThemeDefaultsKey)
            #if os(macOS)
            MacAppIconController.shared.apply(theme: appTheme)
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

    @Published private(set) var cliAccessEnabled: Bool {
        didSet { defaults.set(cliAccessEnabled, forKey: Keys.cliAccessEnabled) }
    }

    @Published private(set) var cliEncryptedAccessEnabled: Bool {
        didSet { defaults.set(cliEncryptedAccessEnabled, forKey: Keys.cliEncryptedAccessEnabled) }
    }
    #endif

    init(defaults: UserDefaults = .standard, keychainStore: KeychainStore? = nil) {
        self.defaults = defaults
        self.keychainStore = keychainStore ?? .shared
        self.preferredNoteMode = NoteMode(rawValue: defaults.string(forKey: Keys.preferredNoteMode) ?? "") ?? .plain
        self.hideContentOnBackground = defaults.object(forKey: Keys.hideContentOnBackground) as? Bool ?? true
        self.autoUnloadKeyOnForeground = defaults.object(forKey: Keys.autoUnloadKeyOnForeground) as? Bool ?? false
        self.lockSessionOnBackground = defaults.object(forKey: Keys.lockSessionOnBackground) as? Bool ?? false
        self.hasSeenFirstKeyPrompt = defaults.bool(forKey: Keys.hasSeenFirstKeyPrompt)
        self.hasSeededDefaultNotes = defaults.bool(forKey: Keys.hasSeededDefaultNotes)
        self.needsKeyExportPending = defaults.bool(forKey: Keys.needsKeyExportPending)
        self.pinnedStorageRoot = defaults.string(forKey: Keys.pinnedStorageRoot)

        let storedFontSize = defaults.double(forKey: Keys.editorFontSize)
        if storedFontSize > 0 {
            self.editorFontSize = Self.clampedFontSize(storedFontSize)
        } else {
            self.editorFontSize = Self.defaultEditorFontSize
        }

        let storedLineHeight = defaults.double(forKey: Keys.editorLineHeightMultiple)
        if storedLineHeight > 0 {
            self.editorLineHeightMultiple = Self.clampedLineHeightMultiple(storedLineHeight)
        } else {
            self.editorLineHeightMultiple = Self.defaultEditorLineHeightMultiple
        }

        self.copyAddsParagraphSpacing = defaults.object(forKey: Keys.copyAddsParagraphSpacing) as? Bool ?? false
        self.autoDeleteEmptyNotes = defaults.object(forKey: Keys.autoDeleteEmptyNotes) as? Bool ?? true
        self.autoRenameNotesOnSave = defaults.object(forKey: Keys.autoRenameNotesOnSave) as? Bool ?? false
        self.excludeHexColorsFromTags = defaults.object(forKey: Keys.excludeHexColorsFromTags) as? Bool ?? true
        self.maintenanceLoggingEnabled = defaults.object(forKey: Keys.maintenanceLoggingEnabled) as? Bool ?? false
        self.appTheme = AppTheme(rawValue: defaults.string(forKey: Self.macThemeDefaultsKey) ?? "") ?? Self.defaultAppTheme
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
        let storedCLIAccess = defaults.object(forKey: Keys.cliAccessEnabled) as? Bool
            ?? Self.defaultCLIAccessEnabled
        self.cliAccessEnabled = storedCLIAccess
        // Encrypted-note CLI access is temporarily unavailable for
        // product-positioning reasons. Always revoke any authorization left by
        // an earlier build while retaining the underlying implementation.
        self.cliEncryptedAccessEnabled = false
        defaults.set(false, forKey: Keys.cliEncryptedAccessEnabled)

        // Retained for a possible future reintroduction:
//        let storedEncryptedCLIAccess = defaults.object(forKey: Keys.cliEncryptedAccessEnabled) as? Bool
//            ?? Self.defaultCLIEncryptedAccessEnabled
//        self.cliEncryptedAccessEnabled = storedCLIAccess && storedEncryptedCLIAccess
//        if !storedCLIAccess && storedEncryptedCLIAccess {
//            defaults.set(false, forKey: Keys.cliEncryptedAccessEnabled)
//        }
        #endif
    }

    /// The backing store, exposed so vault-identity caching (SNVaultId) shares the
    /// same (test-injectable) UserDefaults instance as the rest of settings.
    var userDefaults: UserDefaults { defaults }

    /// 用于测试：重置为默认值。
    func resetForTesting() {
        preferredNoteMode = .plain
        hideContentOnBackground = true
        autoUnloadKeyOnForeground = false
        lockSessionOnBackground = false
        hasSeenFirstKeyPrompt = false
        hasSeededDefaultNotes = false
        needsKeyExportPending = false
        pinnedStorageRoot = nil
        editorFontSize = Self.defaultEditorFontSize
        editorLineHeightMultiple = Self.defaultEditorLineHeightMultiple
        copyAddsParagraphSpacing = false
        autoDeleteEmptyNotes = true
        autoRenameNotesOnSave = false
        excludeHexColorsFromTags = true
        maintenanceLoggingEnabled = false
        appTheme = Self.defaultAppTheme
        macRecentNotesLimit = Self.defaultMacRecentNotesLimit
        iOSAppIconName = nil
        #if os(macOS)
        launchAtLogin = Self.defaultLaunchAtLogin
        pinNewNotesByDefault = Self.defaultPinNewNotes
        lockEncryptedNotesOnSleep = Self.defaultLockEncryptedNotesOnSleep
        lockUnpinnedEncryptedNotesOnBackground = Self.defaultLockUnpinnedEncryptedNotesOnBackground
        clearVaultKeyFileReference()
        hideMacIntroOnLaunch = false
        setCLIAccessEnabled(false)
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
        lockSessionOnBackground = false
        hasSeenFirstKeyPrompt = false
        editorFontSize = Self.defaultEditorFontSize
        editorLineHeightMultiple = Self.defaultEditorLineHeightMultiple
        copyAddsParagraphSpacing = false
        autoDeleteEmptyNotes = true
        autoRenameNotesOnSave = false
        excludeHexColorsFromTags = true
        maintenanceLoggingEnabled = false
        appTheme = Self.defaultAppTheme
        macRecentNotesLimit = Self.defaultMacRecentNotesLimit
        pinNewNotesByDefault = Self.defaultPinNewNotes
        lockEncryptedNotesOnSleep = Self.defaultLockEncryptedNotesOnSleep
        lockUnpinnedEncryptedNotesOnBackground = Self.defaultLockUnpinnedEncryptedNotesOnBackground
        hideMacIntroOnLaunch = false
        setCLIAccessEnabled(false)
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

    func setCLIAccessEnabled(_ isEnabled: Bool) {
        if !isEnabled {
            cliEncryptedAccessEnabled = false
        }
        cliAccessEnabled = isEnabled
    }

    func setCLIEncryptedAccessEnabled(_ isEnabled: Bool) {
        cliEncryptedAccessEnabled = cliAccessEnabled && isEnabled
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
        min(max(value.rounded(), editorFontSizeRange.lowerBound), editorFontSizeRange.upperBound)
    }

    static func clampedLineHeightMultiple(_ value: Double) -> Double {
        min(max(value, editorLineHeightRange.lowerBound), editorLineHeightRange.upperBound)
    }

    static func clampedRecentNotesLimit(_ value: Int) -> Int {
        macRecentNotesLimitOptions.min { abs($0 - value) < abs($1 - value) }
            ?? defaultMacRecentNotesLimit
    }

    private enum Keys {
        static let preferredNoteMode = "SNPreferredNoteMode"
        static let hideContentOnBackground = "SNHideContentOnBackground"
        static let autoUnloadKeyOnForeground = "SNAutoUnloadKeyOnForeground"
        static let lockSessionOnBackground = "SNLockSessionOnBackground"
        static let hasSeenFirstKeyPrompt = "SNHasSeenFirstKeyPrompt"
        static let hasSeededDefaultNotes = "SNHasSeededDefaultNotes"
        static let needsKeyExportPending = "SNNeedsKeyExportPending"
        static let pinnedStorageRoot = "SNPinnedStorageRoot"
        static let editorFontSize = "SNMacEditorFontSize"
        static let editorLineHeightMultiple = "SNMacEditorLineHeightMultiple"
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
        static let cliAccessEnabled = "SNCLIAccessEnabled"
        static let cliEncryptedAccessEnabled = "SNCLIEncryptedAccessEnabled"
        #endif
    }
}
