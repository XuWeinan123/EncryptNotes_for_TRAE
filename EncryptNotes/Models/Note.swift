import Foundation

/// 内存中的可读笔记模型（明文笔记或已解密的加密笔记）。
struct Note: Identifiable, Equatable, Sendable {
    let id: String
    let vaultId: String
    var body: String
    let createdAt: Date
    var updatedAt: Date
    /// 是否为加密笔记。明文笔记为 false；已解密加密笔记为 true。
    let isEncrypted: Bool

    init(
        id: String = UUID().uuidString,
        vaultId: String,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isEncrypted: Bool = false
    ) {
        self.id = id
        self.vaultId = vaultId
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isEncrypted = isEncrypted
    }

    /// 从解密后的 payload 构造加密笔记。
    init(from payload: PlainNotePayload, noteId: String, vaultId: String) {
        self.id = noteId
        self.vaultId = vaultId
        self.body = payload.body
        self.createdAt = payload.createdAt
        self.updatedAt = payload.updatedAt
        self.isEncrypted = true
    }
}
