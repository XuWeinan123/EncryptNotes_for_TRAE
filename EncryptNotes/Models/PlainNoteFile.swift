import Foundation

/// 明文笔记文件 `.bkwplain.json`。
///
/// 内容真实明文落盘，适合普通内容；敏感内容应使用加密笔记。
/// `deleted_at` / `purge_after` / `original_location` 用于回收站与未来文件夹恢复，
/// 主列表中的笔记这三个字段为 nil。
struct PlainNoteFile: Codable {
    let version: Int
    let app: String
    let type: String  // "plain_note"
    let noteId: String
    let vaultId: String
    let createdAt: Date
    let updatedAt: Date
    let body: String
    let deletedAt: Date?
    let purgeAfter: Date?
    let originalLocation: NoteLocation?

    enum CodingKeys: String, CodingKey {
        case version, app, type, body
        case noteId = "note_id"
        case vaultId = "vault_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case purgeAfter = "purge_after"
        case originalLocation = "original_location"
    }

    init(
        version: Int = 1,
        app: String = "BieKanWo",
        type: String = "plain_note",
        noteId: String,
        vaultId: String,
        createdAt: Date,
        updatedAt: Date,
        body: String,
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
        self.body = body
        self.deletedAt = deletedAt
        self.purgeAfter = purgeAfter
        self.originalLocation = originalLocation
    }

    func toNote() -> Note {
        Note(
            id: noteId,
            vaultId: vaultId,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isEncrypted: false
        )
    }
}
