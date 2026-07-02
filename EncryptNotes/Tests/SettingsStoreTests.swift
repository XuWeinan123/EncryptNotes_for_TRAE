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
        XCTAssertEqual(store.macEditorLineHeightMultiple, 1.25, accuracy: 0.0001)
    }

    func testPersistedFontSizeIsLoaded() {
        defaults.set(15.0, forKey: "BKMacEditorFontSize")
        let store = makeStore()
        XCTAssertEqual(store.macEditorFontSize, 15)
    }

    func testDefaultLineHeightMultipleIs125() {
        let store = makeStore()
        XCTAssertEqual(store.macEditorLineHeightMultiple, 1.25, accuracy: 0.0001)
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
        defaults.set(1.5, forKey: "BKMacEditorLineHeightMultiple")
        let store = makeStore()
        XCTAssertEqual(store.macEditorLineHeightMultiple, 1.5, accuracy: 0.0001)
    }

    func testNewMacSettingsDefaults() {
        let store = makeStore()
        XCTAssertFalse(store.copyAddsParagraphSpacing)
        XCTAssertTrue(store.autoDeleteEmptyNotes)
        XCTAssertEqual(store.macTheme, .pink)
        XCTAssertEqual(store.macRecentNotesLimit, 5)
    }

    func testMacThemePersists() {
        let store = makeStore()
        store.macTheme = .cyan
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.macTheme, .cyan)
    }

    func testEditingPrivacyAndDataPreferencesPersist() {
        let store = makeStore()
        store.preferredNoteMode = .encrypted
        store.hideContentOnBackground = false
        store.autoDeleteEmptyNotes = false
        store.maintenanceLoggingEnabled = true

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.preferredNoteMode, .encrypted)
        XCTAssertFalse(reloaded.hideContentOnBackground)
        XCTAssertFalse(reloaded.autoDeleteEmptyNotes)
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
    func testMacAITitleDefaults() {
        let store = makeStore()
        XCTAssertFalse(store.macAITitleEnabled)
        XCTAssertEqual(store.macAITitleProvider, .deepSeek)
        XCTAssertEqual(store.macAITitlePrompt, SettingsStore.defaultMacAITitlePrompt)
        XCTAssertFalse(store.macAITitleSkipsMarkdownHeading)
        XCTAssertFalse(store.hideMacIntroOnLaunch)
    }

    func testMacAITitlePreferencesPersist() {
        let store = makeStore()
        store.macAITitleEnabled = true
        store.macAITitleProvider = .gemini
        store.macAITitlePrompt = "Return a short title."
        store.macAITitleSkipsMarkdownHeading = true

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.macAITitleEnabled)
        XCTAssertEqual(reloaded.macAITitleProvider, .gemini)
        XCTAssertEqual(reloaded.macAITitlePrompt, "Return a short title.")
        XCTAssertTrue(reloaded.macAITitleSkipsMarkdownHeading)
    }

    func testMacIntroPreferencePersists() {
        let store = makeStore()
        store.hideMacIntroOnLaunch = true

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.hideMacIntroOnLaunch)
    }

    func testResetMacAITitlePromptRestoresDefault() {
        let store = makeStore()
        store.macAITitlePrompt = "Custom prompt"
        store.resetMacAITitlePrompt()
        XCTAssertEqual(store.macAITitlePrompt, SettingsStore.defaultMacAITitlePrompt)
    }

    func testResetForTestingRestoresMacIntroPreference() {
        let store = makeStore()
        store.hideMacIntroOnLaunch = true
        store.resetForTesting()
        XCTAssertFalse(store.hideMacIntroOnLaunch)
    }
    #endif

}
