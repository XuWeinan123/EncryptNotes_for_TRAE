import XCTest
import CryptoKit
@testable import EncryptNotes

final class CryptoServiceTests: XCTestCase {

    func testEncryptDecryptRoundTrip() throws {
        let cryptoService = CryptoService.shared
        let key = SymmetricKey(size: .bits256)
        let vaultId = UUID().uuidString
        let noteId = UUID().uuidString
        let now = Date()

        let payload = PlainNotePayload(
            title: "测试标题",
            body: "这是一段测试正文内容",
            tags: ["测试", "加密"],
            createdAt: now,
            updatedAt: now
        )

        let encryptedFile = try cryptoService.encryptToNoteFile(
            noteId: noteId,
            vaultId: vaultId,
            payload: payload,
            key: key
        )

        XCTAssertEqual(encryptedFile.noteId, noteId)
        XCTAssertEqual(encryptedFile.vaultId, vaultId)
        XCTAssertNotEqual(encryptedFile.payload.ciphertext, "")

        let decryptedNote = try cryptoService.decryptNote(file: encryptedFile, using: key)

        XCTAssertEqual(decryptedNote.title, "测试标题")
        XCTAssertEqual(decryptedNote.body, "这是一段测试正文内容")
        XCTAssertEqual(decryptedNote.tags, ["测试", "加密"])
    }

    func testWrongKeyFailsDecryption() throws {
        let cryptoService = CryptoService.shared
        let correctKey = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)
        let vaultId = UUID().uuidString
        let noteId = UUID().uuidString
        let now = Date()

        let payload = PlainNotePayload(
            title: "机密内容",
            body: "只有正确密钥才能解密",
            tags: [],
            createdAt: now,
            updatedAt: now
        )

        let encryptedFile = try cryptoService.encryptToNoteFile(
            noteId: noteId,
            vaultId: vaultId,
            payload: payload,
            key: correctKey
        )

        XCTAssertThrowsError(try cryptoService.decryptNote(file: encryptedFile, using: wrongKey))
    }
}
