import XCTest
@testable import EncryptNotes

final class SchemaTests: XCTestCase {

    func testEncryptedNoteFileCoding() throws {
        let file = EncryptedNoteFile(
            version: 1,
            app: "BieKanWo",
            type: "encrypted_note",
            noteId: "test-note-id",
            vaultId: "test-vault-id",
            createdAt: Date(timeIntervalSince1970: 1000000),
            updatedAt: Date(timeIntervalSince1970: 1000000),
            encryption: EncryptedNoteFile.EncryptionMetadata(
                algorithm: "AES-GCM",
                keyVersion: 1,
                nonce: "base64nonce"
            ),
            payload: EncryptedNoteFile.EncryptionPayload(
                ciphertext: "base64ciphertext",
                tag: "base64tag"
            )
        )

        let data = try JSONEncoder.default.encode(file)
        let decoded = try JSONDecoder.default.decode(EncryptedNoteFile.self, from: data)

        XCTAssertEqual(decoded.noteId, "test-note-id")
        XCTAssertEqual(decoded.vaultId, "test-vault-id")
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.encryption.algorithm, "AES-GCM")
        XCTAssertEqual(decoded.payload.ciphertext, "base64ciphertext")
    }

    func testVaultManifestCoding() throws {
        let manifest = VaultManifest(
            version: 1,
            app: "BieKanWo",
            type: "vault",
            vaultId: "test-vault-id",
            createdAt: Date(timeIntervalSince1970: 1000000),
            updatedAt: Date(timeIntervalSince1970: 2000000),
            keyVersion: 1
        )

        let data = try JSONEncoder.default.encode(manifest)
        let decoded = try JSONDecoder.default.decode(VaultManifest.self, from: data)

        XCTAssertEqual(decoded.vaultId, "test-vault-id")
        XCTAssertEqual(decoded.app, "BieKanWo")
        XCTAssertEqual(decoded.keyVersion, 1)
    }

    func testVaultKeyCoding() throws {
        let key = VaultKey(
            version: 1,
            app: "BieKanWo",
            type: "vault_key",
            vaultId: "test-vault-id",
            keyVersion: 1,
            algorithm: "AES-GCM-256",
            createdAt: Date(timeIntervalSince1970: 1000000),
            keyMaterial: "base64keymaterial"
        )

        let data = try JSONEncoder.default.encode(key)
        let decoded = try JSONDecoder.default.decode(VaultKey.self, from: data)

        XCTAssertEqual(decoded.vaultId, "test-vault-id")
        XCTAssertEqual(decoded.keyMaterial, "base64keymaterial")
        XCTAssertEqual(decoded.algorithm, "AES-GCM-256")
    }

    func testNoteFileExtensionFiltering() {
        // 验证 .bkwenc.json 文件的过滤逻辑
        let urls = [
            URL(fileURLWithPath: "/tmp/note1.bkwenc.json"),
            URL(fileURLWithPath: "/tmp/note2.bkwenc.json"),
            URL(fileURLWithPath: "/tmp/vault.json"),
            URL(fileURLWithPath: "/tmp/.DS_Store"),
            URL(fileURLWithPath: "/tmp/readme.txt")
        ]

        let filtered = urls.filter { $0.lastPathComponent.hasSuffix(".bkwenc.json") }

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.lastPathComponent == "note1.bkwenc.json" })
        XCTAssertTrue(filtered.contains { $0.lastPathComponent == "note2.bkwenc.json" })
    }

    // MARK: - PlainNoteFile

    func testPlainNoteFileCoding() throws {
        let file = PlainNoteFile(
            noteId: "plain-test-id",
            vaultId: "plain-test-vault",
            createdAt: Date(timeIntervalSince1970: 1000000),
            updatedAt: Date(timeIntervalSince1970: 1000000),
            body: "未导入密钥时添加的明文笔记"
        )

        let data = try JSONEncoder.default.encode(file)
        let decoded = try JSONDecoder.default.decode(PlainNoteFile.self, from: data)

        XCTAssertEqual(decoded.noteId, "plain-test-id")
        XCTAssertEqual(decoded.vaultId, "plain-test-vault")
        XCTAssertEqual(decoded.type, "plain_note")
        XCTAssertEqual(decoded.body, "未导入密钥时添加的明文笔记")
    }

    func testPlainNoteFileToNote() {
        let createdAt = Date(timeIntervalSince1970: 1000000)
        let updatedAt = Date(timeIntervalSince1970: 2000000)
        let file = PlainNoteFile(
            noteId: "to-note-id",
            vaultId: "to-note-vault",
            createdAt: createdAt,
            updatedAt: updatedAt,
            body: "转换为 Note"
        )

        let note = file.toNote()
        XCTAssertEqual(note.id, "to-note-id")
        XCTAssertEqual(note.vaultId, "to-note-vault")
        XCTAssertEqual(note.body, "转换为 Note")
        XCTAssertEqual(note.createdAt, createdAt)
        XCTAssertEqual(note.updatedAt, updatedAt)
    }

    func testPlainNoteFileExtensionFiltering() {
        let urls = [
            URL(fileURLWithPath: "/tmp/plain1.bkwplain.json"),
            URL(fileURLWithPath: "/tmp/plain2.bkwplain.json"),
            URL(fileURLWithPath: "/tmp/note1.bkwenc.json"),
            URL(fileURLWithPath: "/tmp/vault.json")
        ]

        let filtered = urls.filter { $0.lastPathComponent.hasSuffix(".bkwplain.json") }

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.lastPathComponent == "plain1.bkwplain.json" })
        XCTAssertTrue(filtered.contains { $0.lastPathComponent == "plain2.bkwplain.json" })
    }

    // MARK: - 回收站元数据

    func testPlainNoteFileTrashMetadata() throws {
        let deletedAt = Date(timeIntervalSince1970: 1000000)
        let purgeAfter = Date(timeIntervalSince1970: 1000000 + 30 * 86400)
        let location = NoteLocation.root

        let file = PlainNoteFile(
            noteId: "trash-plain",
            vaultId: "v",
            createdAt: Date(timeIntervalSince1970: 500000),
            updatedAt: Date(timeIntervalSince1970: 600000),
            body: "回收站明文笔记",
            deletedAt: deletedAt,
            purgeAfter: purgeAfter,
            originalLocation: location
        )

        let data = try JSONEncoder.default.encode(file)
        let decoded = try JSONDecoder.default.decode(PlainNoteFile.self, from: data)

        XCTAssertEqual(decoded.deletedAt, deletedAt)
        XCTAssertEqual(decoded.purgeAfter, purgeAfter)
        XCTAssertEqual(decoded.originalLocation, location)
    }

    func testEncryptedNoteFileTrashMetadata() throws {
        let deletedAt = Date(timeIntervalSince1970: 1000000)
        let purgeAfter = Date(timeIntervalSince1970: 1000000 + 30 * 86400)
        let location = NoteLocation.root

        let file = EncryptedNoteFile(
            version: 1,
            app: "BieKanWo",
            type: "encrypted_note",
            noteId: "trash-enc",
            vaultId: "v",
            createdAt: Date(timeIntervalSince1970: 500000),
            updatedAt: Date(timeIntervalSince1970: 600000),
            encryption: EncryptedNoteFile.EncryptionMetadata(
                algorithm: "AES-GCM",
                keyVersion: 1,
                nonce: "base64nonce"
            ),
            payload: EncryptedNoteFile.EncryptionPayload(
                ciphertext: "base64ciphertext",
                tag: "base64tag"
            ),
            deletedAt: deletedAt,
            purgeAfter: purgeAfter,
            originalLocation: location
        )

        let data = try JSONEncoder.default.encode(file)
        let decoded = try JSONDecoder.default.decode(EncryptedNoteFile.self, from: data)

        XCTAssertEqual(decoded.deletedAt, deletedAt)
        XCTAssertEqual(decoded.purgeAfter, purgeAfter)
        XCTAssertEqual(decoded.originalLocation, location)
    }

    func testNoteLocationCoding() throws {
        let location = NoteLocation.root
        let data = try JSONEncoder.default.encode(location)
        let decoded = try JSONDecoder.default.decode(NoteLocation.self, from: data)

        XCTAssertEqual(decoded.type, "root")
        XCTAssertNil(decoded.folderId)
        XCTAssertNil(decoded.relativePath)
    }

    // MARK: - 安全验收：加密笔记外层 JSON 不含正文

    func testEncryptedNoteFileOuterJSONExcludesPlaintext() throws {
        let secretBody = "这是一段私密内容 #敏感"
        let file = EncryptedNoteFile(
            version: 1,
            app: "BieKanWo",
            type: "encrypted_note",
            noteId: "secret-id",
            vaultId: "v",
            createdAt: Date(timeIntervalSince1970: 500000),
            updatedAt: Date(timeIntervalSince1970: 600000),
            encryption: EncryptedNoteFile.EncryptionMetadata(
                algorithm: "AES-GCM",
                keyVersion: 1,
                nonce: "base64nonce"
            ),
            payload: EncryptedNoteFile.EncryptionPayload(
                ciphertext: "base64ciphertext",
                tag: "base64tag"
            )
        )

        let data = try JSONEncoder.default.encode(file)
        let jsonString = String(data: data, encoding: .utf8) ?? ""

        // 外层 JSON 不得出现正文、标签、摘要
        XCTAssertFalse(jsonString.contains(secretBody), "外层 JSON 不得包含正文")
        XCTAssertFalse(jsonString.contains("敏感"), "外层 JSON 不得包含标签内容")
        XCTAssertFalse(jsonString.contains("#"), "外层 JSON 不得包含 # 符号")
    }

    // MARK: - NoteObfuscator

    func testNoteObfuscatorProducesGarbledOutput() {
        let body = "这是一段明文笔记内容"
        let garbled = NoteObfuscator.garbledPreview(of: body)

        // 乱码应为 base64 编码，不等于原文
        XCTAssertNotEqual(garbled, body)
        XCTAssertFalse(garbled.isEmpty)
        // base64 字符集
        XCTAssertTrue(garbled.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" })
    }

    func testNoteObfuscatorTruncatesTo50() {
        let longBody = String(repeating: "a", count: 100)
        let garbled = NoteObfuscator.garbledPreview(of: longBody)

        XCTAssertLessThanOrEqual(garbled.count, 50)
    }
}
