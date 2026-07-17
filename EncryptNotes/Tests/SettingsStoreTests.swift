import XCTest
@testable import EncryptNotes

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName = defaults.string(forKey: "suiteNameMarker") {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        super.tearDown()
    }

    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: defaults)
    }

    func testDefaultFontSizeIs14() {
        let store = makeStore()
        XCTAssertEqual(store.macEditorFontSize, 14)
    }

    func testAllowedFontSizesCanBeSet() {
        let store = makeStore()
        for size in [12.0, 13.0, 14.0, 16.0, 18.0] {
            store.macEditorFontSize = size
            XCTAssertEqual(store.macEditorFontSize, size)
        }
    }

    func testIllegalFontSizeIsClamped() {
        let store = makeStore()
        store.macEditorFontSize = 100
        XCTAssertEqual(store.macEditorFontSize, 18)
        store.macEditorFontSize = 0
        XCTAssertEqual(store.macEditorFontSize, 12)
    }

    func testResetForTestingRestoresFontSize() {
        let store = makeStore()
        store.macEditorFontSize = 18
        XCTAssertEqual(store.macEditorFontSize, 18)
        store.macEditorLineHeightMultiple = 1.6
        store.resetForTesting()
        XCTAssertEqual(store.macEditorFontSize, 14)
        XCTAssertEqual(store.macEditorLineHeightMultiple, 1.5, accuracy: 0.0001)
    }

    func testPersistedFontSizeIsLoaded() {
        defaults.set(15.0, forKey: "SNMacEditorFontSize")
        let store = makeStore()
        XCTAssertEqual(store.macEditorFontSize, 15)
    }

    func testDefaultLineHeightMultipleIs150() {
        let store = makeStore()
        XCTAssertEqual(store.macEditorLineHeightMultiple, 1.5, accuracy: 0.0001)
    }

    func testLineHeightMultipleCanBeSetInRange() {
        let store = makeStore()
        for multiple in [1.2, 1.25, 2.0] {
            store.macEditorLineHeightMultiple = multiple
            XCTAssertEqual(store.macEditorLineHeightMultiple, multiple, accuracy: 0.0001)
        }
    }

    func testLineHeightMultipleIsClamped() {
        let store = makeStore()
        store.macEditorLineHeightMultiple = 1.0
        XCTAssertEqual(store.macEditorLineHeightMultiple, 1.2, accuracy: 0.0001)
        store.macEditorLineHeightMultiple = 2.5
        XCTAssertEqual(store.macEditorLineHeightMultiple, 2.0, accuracy: 0.0001)
    }

    func testPersistedLineHeightMultipleIsLoaded() {
        defaults.set(1.5, forKey: "SNMacEditorLineHeightMultiple")
        let store = makeStore()
        XCTAssertEqual(store.macEditorLineHeightMultiple, 1.5, accuracy: 0.0001)
    }

    func testNewMacSettingsDefaults() {
        let store = makeStore()
        XCTAssertFalse(store.copyAddsParagraphSpacing)
        XCTAssertTrue(store.autoDeleteEmptyNotes)
        XCTAssertFalse(store.autoRenameNotesOnSave)
        XCTAssertTrue(store.excludeHexColorsFromTags)
        XCTAssertEqual(store.macTheme, .pink)
        XCTAssertEqual(store.macRecentNotesLimit, 5)
    }

    func testMacThemePersists() {
        let store = makeStore()
        store.macTheme = .cyan
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.macTheme, .cyan)
    }

    func testAppLanguageDefaultsToFollowingSystemAndPersists() {
        let store = makeStore()
        XCTAssertEqual(store.appLanguage, .system)

        store.appLanguage = .japanese
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.appLanguage, .japanese)
    }

    func testSupportedSystemLanguageResolutionFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.supportedIdentifier(for: "zh-Hant-HK"), "zh-Hant")
        XCTAssertEqual(AppLanguage.supportedIdentifier(for: "zh-CN"), "zh-Hans")
        XCTAssertEqual(AppLanguage.supportedIdentifier(for: "pt-BR"), "pt")
        XCTAssertNil(AppLanguage.supportedIdentifier(for: "it-IT"))
    }

    func testEditingPrivacyAndDataPreferencesPersist() {
        let store = makeStore()
        store.preferredNoteMode = .encrypted
        store.hideContentOnBackground = false
        store.copyAddsParagraphSpacing = true
        store.autoDeleteEmptyNotes = false
        store.autoRenameNotesOnSave = true
        store.excludeHexColorsFromTags = false
        store.maintenanceLoggingEnabled = true

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.preferredNoteMode, .encrypted)
        XCTAssertFalse(reloaded.hideContentOnBackground)
        XCTAssertTrue(reloaded.copyAddsParagraphSpacing)
        XCTAssertFalse(reloaded.autoDeleteEmptyNotes)
        XCTAssertTrue(reloaded.autoRenameNotesOnSave)
        XCTAssertFalse(reloaded.excludeHexColorsFromTags)
        XCTAssertTrue(reloaded.maintenanceLoggingEnabled)
    }

    #if os(iOS)
    func testIOSAppIconPreferencePersists() {
        let store = makeStore()
        store.iOSAppIconName = IOSAppIconChoice.cyan.iconName

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.iOSAppIconName, IOSAppIconChoice.cyan.iconName)
        XCTAssertEqual(IOSAppIconChoice.choice(for: reloaded.iOSAppIconName), .cyan)
    }
    #endif

    func testRecentNotesLimitIsClamped() {
        let store = makeStore()
        store.macRecentNotesLimit = 1
        XCTAssertEqual(store.macRecentNotesLimit, 3)
        store.macRecentNotesLimit = 99
        XCTAssertEqual(store.macRecentNotesLimit, 12)
    }

    func testRecentNotesLimitPersists() {
        let store = makeStore()
        store.macRecentNotesLimit = 7
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.macRecentNotesLimit, 7)
    }

    #if os(macOS)
    func testMacIntroPreferencePersists() {
        let store = makeStore()
        store.hideMacIntroOnLaunch = true

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.hideMacIntroOnLaunch)
    }

    func testResetForTestingRestoresMacIntroPreference() {
        let store = makeStore()
        store.hideMacIntroOnLaunch = true
        store.resetForTesting()
        XCTAssertFalse(store.hideMacIntroOnLaunch)
    }
    #endif

}
