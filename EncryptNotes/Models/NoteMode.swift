import Foundation

/// 新建笔记的持久化模式。
///
/// - seealso: PRD v0.2 5.6「默认新建模式的持久记忆」
enum NoteMode: String, Codable, CaseIterable {
    case plain
    case encrypted
}
