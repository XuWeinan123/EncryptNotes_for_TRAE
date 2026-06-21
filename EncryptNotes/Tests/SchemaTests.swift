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
}
