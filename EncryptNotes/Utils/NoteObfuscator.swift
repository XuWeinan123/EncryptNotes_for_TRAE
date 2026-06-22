import Foundation

/// 将明文笔记内容转换为乱码形式，用于未导入密钥时显示。
///
/// 将正文进行 base64 编码后截取前 50 个字符，视觉上与加密笔记的密文预览一致。
enum NoteObfuscator {
    /// 返回乱码形式的笔记预览。
    static func garbledPreview(of body: String) -> String {
        let data = Data(body.utf8)
        let base64 = data.base64EncodedString()
        return String(base64.prefix(50))
    }
}
