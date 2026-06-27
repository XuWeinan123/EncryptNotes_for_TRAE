import Foundation

/// 加密笔记文件 `.bkwenc.json`。
///
/// 外层 JSON 只保存元数据；正文、标签只能存在于加密 `payload` 内，
/// 不得写入外层 JSON。`deleted_at` / `purge_after` / `original_location`
/// 用于回收站与未来文件夹恢复，主列表中的笔记这三个字段为 nil。
struct EncryptedNoteFile: Codable, Sendable {
    let version: Int
    let app: String
    let type: String
    let noteId: String
    let vaultId: String
    let createdAt: Date
    let updatedAt: Date
    let encryption: EncryptionMetadata
    let payload: EncryptionPayload
    let deletedAt: Date?
    let purgeAfter: Date?
    let originalLocation: NoteLocation?

    enum CodingKeys: String, CodingKey {
        case version, app, type, encryption, payload
        case noteId = "note_id"
        case vaultId = "vault_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case purgeAfter = "purge_after"
        case originalLocation = "original_location"
    }

    struct EncryptionMetadata: Codable, Sendable {
        let algorithm: String
        let keyVersion: Int
        let nonce: String

        enum CodingKeys: String, CodingKey {
            case algorithm
            case keyVersion = "key_version"
            case nonce
        }
    }

    struct EncryptionPayload: Codable, Sendable {
        let ciphertext: String
        let tag: String
    }

    init(
        version: Int = 1,
        app: String = "BieKanWo",
        type: String = "encrypted_note",
        noteId: String,
        vaultId: String,
        createdAt: Date,
        updatedAt: Date,
        encryption: EncryptionMetadata,
        payload: EncryptionPayload,
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil,
        originalLocation: NoteLocation? = nil
    ) {
        self.version = version
        self.app = app
        self.type = type
        self.noteId = noteId
        self.vaultId = vaultId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.encryption = encryption
        self.payload = payload
        self.deletedAt = deletedAt
        self.purgeAfter = purgeAfter
        self.originalLocation = originalLocation
    }
}
