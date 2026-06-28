import XCTest
import CryptoKit
@testable import EncryptNotes

final class SchemaTests: XCTestCase {

    func testNoteIndexCoding() throws {
        let entry = NoteIndexEntry(
            noteId: "test-note-id",
            fileName: "test-note-id.md",
            mode: .encrypted,
            location: .notes
        )
        var index = NoteIndex()
        index.upsert(entry)

        let data = try JSONEncoder.default.encode(index)
        let decoded = try JSONDecoder.default.decode(NoteIndex.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.app, "BieKanWo")
        XCTAssertEqual(decoded.type, "note_index")
        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries.first?.noteId, "test-note-id")
        XCTAssertEqual(decoded.entries.first?.mode, .encrypted)
        XCTAssertEqual(decoded.entries.first?.location, .notes)
    }

    func testNoteIndexJSONExcludesSensitiveFields() throws {
        let entry = NoteIndexEntry(
            noteId: "secret-id",
            fileName: "secret-id.md",
            mode: .encrypted,
            location: .notes
        )
        var index = NoteIndex()
        index.upsert(entry)

        let data = try JSONEncoder.default.encode(index)
        let jsonString = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(jsonString.contains("created_at"), "notes.json 不得包含 created_at")
        XCTAssertFalse(jsonString.contains("updated_at"), "notes.json 不得包含 updated_at")
        XCTAssertFalse(jsonString.contains("body"), "notes.json 不得包含正文")
        XCTAssertFalse(jsonString.contains("#"), "notes.json 不得包含 # 标签")
    }

    func testVaultKeyV2Coding() throws {
        let key = VaultKey(
            version: 2,
            app: "BieKanWo",
            type: "vault_key",
            keyId: "test-key-id",
            algorithm: "AES-GCM-256",
            createdAt: Date(timeIntervalSince1970: 1000000),
            keyMaterial: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )

        let data = try JSONEncoder.default.encode(key)
        let decoded = try JSONDecoder.default.decode(VaultKey.self, from: data)

        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.keyId, "test-key-id")
        XCTAssertEqual(decoded.algorithm, "AES-GCM-256")
        XCTAssertEqual(decoded.keyMaterial, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
        XCTAssertNil(decoded.value(forKey: "vaultId") as? String)
    }

    func testMarkdownNoteFileParseAndRender() throws {
        let now = Date(timeIntervalSince1970: 1000000)
        let original = MarkdownNoteFile(
            noteId: "test-md-id",
            createdAt: now,
            updatedAt: now,
            body: "这是一段测试正文\n\n#标签1 #标签2"
        )

        let data = try original.render()
        let parsed = try MarkdownNoteFile.parse(from: data)

        XCTAssertEqual(parsed.noteId, "test-md-id")
        XCTAssertEqual(parsed.createdAt, now)
        XCTAssertEqual(parsed.updatedAt, now)
        XCTAssertEqual(parsed.body, "这是一段测试正文\n\n#标签1 #标签2")
        XCTAssertFalse(parsed.isEncrypted)
    }

    func testMarkdownNoteFileEncryptedDetection() {
        let encryptedBody = "bkwenc:v1:ABCDEFGHIJKLMNOP"
        let file = MarkdownNoteFile(
            noteId: "enc-id",
            createdAt: Date(),
            updatedAt: Date(),
            body: encryptedBody
        )
        XCTAssertTrue(file.isEncrypted)

        let plainFile = MarkdownNoteFile(
            noteId: "plain-id",
            createdAt: Date(),
            updatedAt: Date(),
            body: "普通正文 bkwenc:v1: 开头才是加密"
        )
        XCTAssertFalse(plainFile.isEncrypted)
    }

    func testMarkdownNoteFileMalformedFrontmatter() {
        let cases = [
            "no frontmatter here",
            "---\nmissing end\nbody",
            "---\nnote_id: \"\"\ncreated_at: \"bad\"\nupdated_at: \"bad\"\n---\n\nbody",
            "---\ncreated_at: \"2026-01-01T00:00:00Z\"\nupdated_at: \"2026-01-01T00:00:00Z\"\n---\n\nbody",
        ]

        for malformed in cases {
            XCTAssertThrowsError(try MarkdownNoteFile.parse(from: malformed), "malformed input should throw: \(malformed.prefix(30))")
        }
    }

    func testMarkdownFileExtensionFiltering() {
        let urls = [
            URL(fileURLWithPath: "/tmp/note1.md"),
            URL(fileURLWithPath: "/tmp/note2.md"),
            URL(fileURLWithPath: "/tmp/notes.json"),
            URL(fileURLWithPath: "/tmp/.DS_Store"),
            URL(fileURLWithPath: "/tmp/old.bkwenc.json"),
            URL(fileURLWithPath: "/tmp/old.bkwplain.json")
        ]

        let filtered = urls.filter { $0.lastPathComponent.hasSuffix(".md") }

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.lastPathComponent == "note1.md" })
        XCTAssertTrue(filtered.contains { $0.lastPathComponent == "note2.md" })
    }

    func testEncryptedMarkdownBodyDoesNotContainPlaintext() throws {
        let key = SymmetricKey(size: .bits256)
        let crypto = CryptoService.shared
        let secretBody = "这是私密内容 #隐私 敏感信息"

        let encrypted = try crypto.encryptMarkdownBody(secretBody, using: key)

        XCTAssertTrue(encrypted.hasPrefix("bkwenc:v1:"))
        XCTAssertFalse(encrypted.contains("隐私"))
        XCTAssertFalse(encrypted.contains("敏感"))
        XCTAssertFalse(encrypted.contains("#"))
    }

    func testNoteObfuscatorProducesGarbledOutput() {
        let body = "这是一段明文笔记内容"
        let garbled = NoteObfuscator.garbledPreview(of: body)

        XCTAssertNotEqual(garbled, body)
        XCTAssertFalse(garbled.isEmpty)
        XCTAssertTrue(garbled.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" })
    }

    func testNoteObfuscatorTruncatesTo50() {
        let longBody = String(repeating: "a", count: 100)
        let garbled = NoteObfuscator.garbledPreview(of: longBody)

        XCTAssertLessThanOrEqual(garbled.count, 50)
    }
}

private extension VaultKey {
    func value(forKey key: String) -> Any? {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if child.label == key {
                return child.value
            }
        }
        return nil
    }
}
