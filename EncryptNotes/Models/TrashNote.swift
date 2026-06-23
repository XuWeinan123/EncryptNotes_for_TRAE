import Foundation

/// 回收站中的笔记，统一表示明文笔记、已解密加密笔记与未解密加密笔记。
///
/// - `body` 非空：明文笔记或已解密加密笔记，可在回收站内直接展示内容。
/// - `body` 为空：未解密加密笔记，仅展示乱码与上锁 icon。
struct TrashNote: Identifiable, Equatable {
    let id: String
    let vaultId: String
    let isEncrypted: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date
    let purgeAfter: Date
    let url: URL

    /// 可读正文；未解密加密笔记为 nil。
    let body: String?
    /// 未解密加密笔记的密文预览；可读笔记为 nil。
    let ciphertextPreview: String?
    let fileSize: Int

    var isReadable: Bool { body != nil }

    /// 距离自动永久删除的剩余天数（最小为 0）。
    var remainingDays: Int {
        let seconds = purgeAfter.timeIntervalSinceNow
        return max(0, Int(ceil(seconds / 86400)))
    }
}
