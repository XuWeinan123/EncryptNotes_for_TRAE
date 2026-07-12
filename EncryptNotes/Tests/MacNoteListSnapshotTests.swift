#if os(macOS)
import XCTest
@testable import EncryptNotes

final class MacNoteListSnapshotTests: XCTestCase {
    func testSnapshotBuildsSearchTagsCountsAndRecentItemsInOnePass() {
        let olderPlain = Note(
            id: "plain-old",
            body: "Alpha #work\nbody",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 120),
            isEncrypted: false
        )
        let newestEncrypted = Note(
            id: "encrypted-new",
            body: "Secret title #work #secure",
            createdAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 320),
            isEncrypted: true
        )
        let emptyNote = Note(
            id: "empty",
            body: "  \n",
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 210),
            isEncrypted: false
        )
        let locked = EncryptedNoteInfo(
            id: "locked",
            url: URL(fileURLWithPath: "/tmp/locked.md"),
            title: "Locked secret",
            ciphertextPreview: "snenc:v1:preview",
            fileSize: 32,
            createdAt: Date(timeIntervalSince1970: 250),
            updatedAt: Date(timeIntervalSince1970: 260)
        )

        let all = MacNoteListSnapshotBuilder.make(
            readableNotes: [olderPlain, newestEncrypted, emptyNote],
            lockedEncryptedNotes: [locked],
            titleProvider: { NoteTitleFormatter.displayTitle(from: $0.body, emptyTitle: "") }
        )

        XCTAssertEqual(all.items.map(\.id), ["encrypted-new", "locked", "empty", "plain-old"])
        XCTAssertEqual(all.emptyReadableCount, 1)
        XCTAssertEqual(all.encryptedCount, 2)
        XCTAssertEqual(all.totalCount, 4)
        XCTAssertEqual(all.recentItems(limit: 2).map(\.id), ["encrypted-new", "locked"])
        XCTAssertEqual(all.tagCounts, [TagCount(tag: "work", count: 1)])

        let filtered = MacNoteListSnapshotBuilder.make(
            readableNotes: [olderPlain, newestEncrypted, emptyNote],
            lockedEncryptedNotes: [locked],
            query: "alpha",
            selectedTag: "work",
            titleProvider: { NoteTitleFormatter.displayTitle(from: $0.body, emptyTitle: "") }
        )

        XCTAssertEqual(filtered.items.map(\.id), ["plain-old"])
        XCTAssertEqual(filtered.encryptedCount, 0)
    }
}
#endif
