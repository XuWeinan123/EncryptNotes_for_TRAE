import XCTest
import CryptoKit
@testable import SealNote

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
        XCTAssertEqual(decoded.app, "Seal Note")
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
            app: VaultKey.appName,
            type: "vault_key",
            keyId: "test-key-id",
            algorithm: "AES-GCM-256",
            createdAt: Date(timeIntervalSince1970: 1000000),
            keyMaterial: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )

        let data = try JSONEncoder.default.encode(key)
        let decoded = try JSONDecoder.default.decode(VaultKey.self, from: data)

        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.app, "Seal Note")
        XCTAssertEqual(decoded.keyId, "test-key-id")
        XCTAssertEqual(decoded.algorithm, "AES-GCM-256")
        XCTAssertEqual(decoded.keyMaterial, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
        XCTAssertNil(decoded.value(forKey: "vaultId") as? String)
    }

    func testGeneratedVaultKeyUsesSealNoteAppName() {
        let key = VaultKeyManager.shared.generateVaultKey(key: SymmetricKey(size: .bits256))

        XCTAssertEqual(key.app, "Seal Note")
        XCTAssertTrue(VaultKeyManager.shared.validateVaultKey(key))
    }

    func testVaultKeyValidationRejectsLegacyAppName() {
        let legacyKey = VaultKey(
            version: 2,
            app: "LegacyApp",
            type: "vault_key",
            keyId: "test-key-id",
            algorithm: "AES-GCM-256",
            createdAt: Date(timeIntervalSince1970: 1000000),
            keyMaterial: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )

        XCTAssertFalse(VaultKeyManager.shared.validateVaultKey(legacyKey))
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

    func testMarkdownNoteFilePreservesPlaintextTitle() throws {
        let now = Date(timeIntervalSince1970: 1000000)
        let original = MarkdownNoteFile(
            noteId: "title-md-id",
            createdAt: now,
            updatedAt: now,
            title: "明文标题 \"A\"",
            body: "snenc:v1:ABCDEFGHIJKLMNOP"
        )

        let data = try original.render()
        let rendered = String(data: data, encoding: .utf8)
        let parsed = try MarkdownNoteFile.parse(from: data)

        XCTAssertTrue(rendered?.contains("title: \"明文标题 \\\"A\\\"\"") == true)
        XCTAssertEqual(parsed.title, "明文标题 \"A\"")
        XCTAssertEqual(parsed.body, "snenc:v1:ABCDEFGHIJKLMNOP")
        XCTAssertTrue(parsed.isEncrypted)
    }

    func testMarkdownNoteFileParseSkipsSeparatorBlankLine() throws {
        let content = """
        ---
        note_id: "separator-id"
        created_at: "1970-01-12T13:46:40.000Z"
        updated_at: "1970-01-12T13:46:40.000Z"
        ---

        第一行
        """

        let parsed = try MarkdownNoteFile.parse(from: content)

        XCTAssertEqual(parsed.body, "第一行")
    }

    func testMarkdownNoteFileEncryptedDetection() {
        let encryptedBody = "snenc:v1:ABCDEFGHIJKLMNOP"
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
            body: "普通正文 snenc:v1: 开头才是加密"
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
            URL(fileURLWithPath: "/tmp/old.snenc.json"),
            URL(fileURLWithPath: "/tmp/old.snplain.json")
        ]

        let filtered = urls.filter { $0.lastPathComponent.hasSuffix(".md") }

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.lastPathComponent == "note1.md" })
        XCTAssertTrue(filtered.contains { $0.lastPathComponent == "note2.md" })
    }

    func testNoteTitleFormatterRemovesLeadingHeadingMarker() {
        XCTAssertEqual(NoteTitleFormatter.displayTitle(from: "# Hello"), "Hello")
        XCTAssertEqual(NoteTitleFormatter.displayTitle(from: "## Hello"), "Hello")
        XCTAssertEqual(NoteTitleFormatter.displayTitle(from: "#Hello"), "#Hello")
        XCTAssertEqual(NoteTitleFormatter.displayTitle(from: "Hello"), "Hello")
    }

    func testNoteTitleFormatterFileNameUsesNormalizedHeadingTitle() {
        XCTAssertEqual(
            NoteTitleFormatter.fileName(for: "note-id", body: "# Hello"),
            "Hello.md"
        )
        XCTAssertEqual(
            NoteTitleFormatter.fileName(for: "note-id", body: "Hello"),
            "Hello.md"
        )
    }

    func testNoteTitleFormatterLimitsGeneratedTitleToTwentyCharacters() {
        XCTAssertEqual(
            NoteTitleFormatter.fileName(for: "note-id", body: "1234567890123456789012345"),
            "12345678901234567890.md"
        )
    }

    func testNoteTitleFormatterDoesNotLimitMarkdownHeadingTitle() {
        XCTAssertEqual(
            NoteTitleFormatter.fileName(for: "note-id", body: "# 1234567890123456789012345"),
            "1234567890123456789012345.md"
        )
    }

    func testNoteTitleFormatterSanitizesGeneratedTitle() {
        XCTAssertEqual(
            NoteTitleFormatter.sanitizedGeneratedTitle("\"# Project / Launch?\""),
            "Project - Launch"
        )
        XCTAssertEqual(
            NoteTitleFormatter.fileName(for: "note-id", title: "`# 私密/标题?`"),
            "私密-标题.md"
        )
    }

    func testNoteTitleFormatterDetectsMarkdownHeadingException() {
        XCTAssertTrue(NoteTitleFormatter.firstNonEmptyLineIsMarkdownHeading(in: "\n## 标题\n正文"))
        XCTAssertFalse(NoteTitleFormatter.firstNonEmptyLineIsMarkdownHeading(in: "#标签 不是标题"))
        XCTAssertFalse(NoteTitleFormatter.firstNonEmptyLineIsMarkdownHeading(in: "普通第一行\n# 标题"))
    }

    func testNoteTitleFormatterReadsTitleFromFileName() {
        XCTAssertEqual(
            NoteTitleFormatter.displayTitle(fromFileName: "AI 标题（2）.md"),
            "AI 标题"
        )
        XCTAssertEqual(
            NoteTitleFormatter.displayTitle(fromFileName: "（空笔记）.md"),
            "（空笔记）"
        )
        XCTAssertEqual(
            NoteTitleFormatter.displayTitle(from: ""),
            "临时笔记"
        )
    }

    func testEncryptedMarkdownBodyDoesNotContainPlaintext() throws {
        let key = SymmetricKey(size: .bits256)
        let crypto = CryptoService.shared
        let secretBody = "这是私密内容 #隐私 敏感信息"

        let encrypted = try crypto.encryptMarkdownBody(secretBody, using: key)

        XCTAssertTrue(encrypted.hasPrefix("snenc:v1:"))
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
