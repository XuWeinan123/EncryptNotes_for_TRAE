import Foundation

struct EncryptedNoteFile: Codable {
    let version: Int
    let app: String
    let type: String
    let noteId: String
    let vaultId: String
    let createdAt: Date
    let updatedAt: Date
    let encryption: EncryptionMetadata
    let payload: EncryptionPayload

    enum CodingKeys: String, CodingKey {
        case version, app, type, encryption, payload
        case noteId = "note_id"
        case vaultId = "vault_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    struct EncryptionMetadata: Codable {
        let algorithm: String
        let keyVersion: Int
        let nonce: String

        enum CodingKeys: String, CodingKey {
            case algorithm
            case keyVersion = "key_version"
            case nonce
        }
    }

    struct EncryptionPayload: Codable {
        let ciphertext: String
        let tag: String
    }
}
