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
        store.macEditorLineHeightMultiple = 1.6
        store.resetForTesting()
        XCTAssertEqual(store.macEditorFontSize, 14)
        XCTAssertEqual(store.macEditorLineHeightMultiple, 1.25, accuracy: 0.0001)
    }

    func testPersistedFontSizeIsLoaded() {
        defaults.set(16.0, forKey: "BKMacEditorFontSize")
        let store = makeStore()
        XCTAssertEqual(store.macEditorFontSize, 16)
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
}
