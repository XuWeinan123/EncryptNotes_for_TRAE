import Foundation

/// 未导入密钥时创建的明文笔记文件。
///
/// 当 Vault 处于 `.locked` 状态（本机没有密钥）时，用户仍可以添加笔记。
/// 这些笔记以明文形式存储在 `.bkwplain.json` 文件中，并带有小锁标志：
/// - 未导入密钥文件时：小锁为锁定状态，笔记内容显示为乱码。
/// - 导入密钥文件后：小锁为解锁状态，笔记内容正常显示。
struct PlainNoteFile: Codable {
    let version: Int
    let app: String
    let type: String  // "plain_note"
    let noteId: String
    let vaultId: String
    let createdAt: Date
    let updatedAt: Date
    let body: String

    enum CodingKeys: String, CodingKey {
        case version, app, type, body
        case noteId = "note_id"
        case vaultId = "vault_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        version: Int = 1,
        app: String = "BieKanWo",
        type: String = "plain_note",
        noteId: String,
        vaultId: String,
        createdAt: Date,
        updatedAt: Date,
        body: String
    ) {
        self.version = version
        self.app = app
        self.type = type
        self.noteId = noteId
        self.vaultId = vaultId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.body = body
    }

    func toNote() -> Note {
        Note(
            id: noteId,
            vaultId: vaultId,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
