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
        for size in [12.0, 14.0, 16.0, 18.0] {
            store.macEditorFontSize = size
            XCTAssertEqual(store.macEditorFontSize, size)
        }
    }

    func testIllegalFontSizeFallsBackTo14() {
        let store = makeStore()
        store.macEditorFontSize = 13
        XCTAssertEqual(store.macEditorFontSize, 14)
        store.macEditorFontSize = 100
        XCTAssertEqual(store.macEditorFontSize, 14)
        store.macEditorFontSize = 0
        XCTAssertEqual(store.macEditorFontSize, 14)
    }

    func testResetForTestingRestoresFontSize() {
        let store = makeStore()
        store.macEditorFontSize = 18
        XCTAssertEqual(store.macEditorFontSize, 18)
        store.resetForTesting()
        XCTAssertEqual(store.macEditorFontSize, 14)
    }

    func testPersistedFontSizeIsLoaded() {
        defaults.set(16.0, forKey: "BKMacEditorFontSize")
        let store = makeStore()
        XCTAssertEqual(store.macEditorFontSize, 16)
    }
}
