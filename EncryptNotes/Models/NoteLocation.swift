import Foundation

/// 笔记在文件中的原始位置，用于回收站恢复。
///
/// v0.2 中 `type` 固定为 `"root"`；预留 `"folder"` 以支持未来文件夹架构。
struct NoteLocation: Codable, Equatable, Sendable {
    let type: String
    let folderId: String?
    let relativePath: String?

    enum CodingKeys: String, CodingKey {
        case type
        case folderId = "folder_id"
        case relativePath = "relative_path"
    }

    static let root = NoteLocation(type: "root", folderId: nil, relativePath: nil)
}
