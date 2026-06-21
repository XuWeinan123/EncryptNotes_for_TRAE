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
            body: "这是一段测试正文内容",
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

        XCTAssertEqual(decryptedNote.body, "这是一段测试正文内容")
    }

    func testWrongKeyFailsDecryption() throws {
        let cryptoService = CryptoService.shared
        let correctKey = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)
        let vaultId = UUID().uuidString
        let noteId = UUID().uuidString
        let now = Date()

        let payload = PlainNotePayload(
            body: "只有正确密钥才能解密",
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
