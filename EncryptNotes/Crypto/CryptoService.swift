import Foundation
import CryptoKit

enum CryptoServiceError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidCiphertext
    case invalidNonce
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Encryption failed"
        case .decryptionFailed: return "Decryption failed"
        case .invalidCiphertext: return "Invalid ciphertext"
        case .invalidNonce: return "Invalid nonce"
        case .authenticationFailed: return "Authentication failed - wrong key or tampered data"
        }
    }
}

final class CryptoService {
    static let shared = CryptoService()

    private init() {}

    func encrypt(payload: PlainNotePayload, using key: SymmetricKey) throws -> EncryptedNoteFile.EncryptionPayload {
        let payloadData = try JSONEncoder.default.encode(payload)

        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(payloadData, using: key, nonce: nonce)

        guard let ciphertext = sealedBox.ciphertext as Data?,
              let tag = sealedBox.tag as Data? else {
            throw CryptoServiceError.encryptionFailed
        }

        return EncryptedNoteFile.EncryptionPayload(
            ciphertext: ciphertext.base64EncodedString(),
            tag: tag.base64EncodedString()
        )
    }

    func encryptToNoteFile(
        noteId: String,
        vaultId: String,
        payload: PlainNotePayload,
        key: SymmetricKey
    ) throws -> EncryptedNoteFile {
        let nonce = AES.GCM.Nonce()
        let payloadData = try JSONEncoder.default.encode(payload)
        let sealedBox = try AES.GCM.seal(payloadData, using: key, nonce: nonce)

        guard let ciphertext = sealedBox.ciphertext as Data?,
              let tag = sealedBox.tag as Data? else {
            throw CryptoServiceError.encryptionFailed
        }

        let now = Date()

        return EncryptedNoteFile(
            version: 1,
            app: "BieKanWo",
            type: "encrypted_note",
            noteId: noteId,
            vaultId: vaultId,
            createdAt: payload.createdAt,
            updatedAt: now,
            encryption: EncryptedNoteFile.EncryptionMetadata(
                algorithm: "AES-GCM",
                keyVersion: 1,
                nonce: Data(nonce).base64EncodedString()
            ),
            payload: EncryptedNoteFile.EncryptionPayload(
                ciphertext: ciphertext.base64EncodedString(),
                tag: tag.base64EncodedString()
            )
        )
    }

    func decrypt(file: EncryptedNoteFile, using key: SymmetricKey) throws -> PlainNotePayload {
        guard let nonceData = Data(base64Encoded: file.encryption.nonce) else {
            throw CryptoServiceError.invalidNonce
        }

        guard let ciphertext = Data(base64Encoded: file.payload.ciphertext),
              let tag = Data(base64Encoded: file.payload.tag) else {
            throw CryptoServiceError.invalidCiphertext
        }

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)

        do {
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder.default.decode(PlainNotePayload.self, from: decryptedData)
        } catch {
            throw CryptoServiceError.authenticationFailed
        }
    }

    func decryptNote(file: EncryptedNoteFile, using key: SymmetricKey) throws -> Note {
        let payload = try decrypt(file: file, using: key)
        return Note(from: payload, noteId: file.noteId, vaultId: file.vaultId)
    }
}
