import Foundation

/// 解析正文中的 `#标签`。
///
/// 规则（PRD v0.2 9.1 / 9.2）：
/// - 以 `#` 开头。
/// - 内容不能为空、不包含空格。
/// - 结束符为空格、换行或正文结尾。
/// - 不做次级标签，`#产品/隐私` 视为单个标签 `产品/隐私`。
enum TagParser {
    /// 匹配 `#` 后跟若干非空白、非 `#` 字符。
    static let pattern = #"#[^\s#]+"#

    /// 返回正文中出现的所有标签（含 `#` 前缀），按出现顺序排列。
    static func tags(in body: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        return matches.map { ns.substring(with: $0.range) }
    }
}

/// 标签及其在可读笔记中的出现次数。
struct TagCount: Identifiable, Equatable {
    let tag: String
    let count: Int
    var id: String { tag }
}
