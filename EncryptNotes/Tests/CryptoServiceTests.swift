import XCTest
import CryptoKit
@testable import EncryptNotes

final class CryptoServiceTests: XCTestCase {

    func testEncryptDecryptMarkdownRoundTrip() throws {
        let cryptoService = CryptoService.shared
        let key = SymmetricKey(size: .bits256)
        let body = "这是一段测试正文内容 #标签"

        let encrypted = try cryptoService.encryptMarkdownBody(body, using: key)

        XCTAssertTrue(encrypted.hasPrefix("snenc:v1:"))
        XCTAssertNotEqual(encrypted, body)

        let decrypted = try cryptoService.decryptMarkdownBody(encrypted, using: key)
        XCTAssertEqual(decrypted, body)
    }

    func testWrongKeyFailsDecryption() throws {
        let cryptoService = CryptoService.shared
        let correctKey = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)

        let encrypted = try cryptoService.encryptMarkdownBody("只有正确密钥才能解密", using: correctKey)

        XCTAssertThrowsError(try cryptoService.decryptMarkdownBody(encrypted, using: wrongKey))
    }

    func testTamperedCiphertextFails() throws {
        let cryptoService = CryptoService.shared
        let key = SymmetricKey(size: .bits256)

        let encrypted = try cryptoService.encryptMarkdownBody("原始内容", using: key)

        let base64Start = encrypted.index(encrypted.startIndex, offsetBy: "snenc:v1:".count)
        let prefix = encrypted[..<base64Start]
        var base64 = String(encrypted[base64Start...])
        if let firstChar = base64.first, firstChar != "A" {
            base64 = "A" + String(base64.dropFirst())
        } else {
            base64 = "B" + String(base64.dropFirst())
        }
        let tampered = String(prefix) + base64

        XCTAssertThrowsError(try cryptoService.decryptMarkdownBody(tampered, using: key))
    }

    func testInvalidFormatFails() throws {
        let cryptoService = CryptoService.shared
        let key = SymmetricKey(size: .bits256)

        XCTAssertThrowsError(try cryptoService.decryptMarkdownBody("not-encrypted", using: key))
        XCTAssertThrowsError(try cryptoService.decryptMarkdownBody("snenc:v1:", using: key))
        XCTAssertThrowsError(try cryptoService.decryptMarkdownBody("snenc:v1:!!!", using: key))
    }

    func testLegacyEncryptedPrefixIsRejected() throws {
        let cryptoService = CryptoService.shared
        let key = SymmetricKey(size: .bits256)
        let legacyPrefix = "bk" + "wenc:v1:"

        XCTAssertThrowsError(try cryptoService.decryptMarkdownBody(legacyPrefix + "ABCDEFGHIJKLMNOP", using: key)) { error in
            guard case CryptoServiceError.invalidEncryptedFormat = error else {
                XCTFail("旧加密前缀应被识别为无效格式，实际：\(error)")
                return
            }
        }
    }

    func testEncryptedBodyDoesNotContainPlaintext() throws {
        let cryptoService = CryptoService.shared
        let key = SymmetricKey(size: .bits256)
        let secretBody = "这是超级私密的内容 #秘密标签"

        let encrypted = try cryptoService.encryptMarkdownBody(secretBody, using: key)

        XCTAssertFalse(encrypted.contains("私密"))
        XCTAssertFalse(encrypted.contains("秘密标签"))
        XCTAssertFalse(encrypted.contains("#"))
    }

    func testEmptyBodyRoundTrip() throws {
        let cryptoService = CryptoService.shared
        let key = SymmetricKey(size: .bits256)

        let encrypted = try cryptoService.encryptMarkdownBody("", using: key)
        let decrypted = try cryptoService.decryptMarkdownBody(encrypted, using: key)
        XCTAssertEqual(decrypted, "")
    }

    func testLongBodyRoundTrip() throws {
        let cryptoService = CryptoService.shared
        let key = SymmetricKey(size: .bits256)
        let longBody = String(repeating: "长文本内容测试。", count: 1000)

        let encrypted = try cryptoService.encryptMarkdownBody(longBody, using: key)
        let decrypted = try cryptoService.decryptMarkdownBody(encrypted, using: key)
        XCTAssertEqual(decrypted, longBody)
    }

    func testBase64URLFormat() throws {
        let cryptoService = CryptoService.shared
        let key = SymmetricKey(size: .bits256)

        let encrypted = try cryptoService.encryptMarkdownBody("test", using: key)
        let afterPrefix = String(encrypted.dropFirst("snenc:v1:".count))

        XCTAssertFalse(afterPrefix.contains("+"), "base64url should not contain +")
        XCTAssertFalse(afterPrefix.contains("/"), "base64url should not contain /")
        XCTAssertFalse(afterPrefix.contains("="), "base64url should not contain padding =")
    }
}
