import Foundation
import CryptoKit

nonisolated enum CryptoServiceError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidCiphertext
    case invalidNonce
    case authenticationFailed
    case invalidEncryptedFormat

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Encryption failed"
        case .decryptionFailed: return "Decryption failed"
        case .invalidCiphertext: return "Invalid ciphertext"
        case .invalidNonce: return "Invalid nonce"
        case .authenticationFailed: return "Authentication failed - wrong key or tampered data"
        case .invalidEncryptedFormat: return "Invalid encrypted body format"
        }
    }
}

nonisolated final class CryptoService {
    static let shared = CryptoService()

    static let encryptedPrefix = "bkwenc:v1:"

    private init() {}

    func encryptMarkdownBody(_ body: String, using key: SymmetricKey) throws -> String {
        let bodyData = Data(body.utf8)

        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(bodyData, using: key, nonce: nonce)

        guard let ciphertext = sealedBox.ciphertext as Data?,
              let tag = sealedBox.tag as Data? else {
            throw CryptoServiceError.encryptionFailed
        }

        let nonceData = Data(nonce)
        let combined = nonceData + ciphertext + tag
        let base64url = combined.base64URLEncodedString()

        return CryptoService.encryptedPrefix + base64url
    }

    func decryptMarkdownBody(_ encrypted: String, using key: SymmetricKey) throws -> String {
        guard encrypted.hasPrefix(CryptoService.encryptedPrefix) else {
            throw CryptoServiceError.invalidEncryptedFormat
        }

        let base64url = String(encrypted.dropFirst(CryptoService.encryptedPrefix.count))
        guard let combined = Data(base64URLEncoded: base64url) else {
            throw CryptoServiceError.invalidCiphertext
        }

        guard combined.count >= 12 + 16 else {
            throw CryptoServiceError.invalidCiphertext
        }

        let nonceData = combined.prefix(12)
        let ciphertextAndTag = combined.dropFirst(12)
        let tag = ciphertextAndTag.suffix(16)
        let ciphertext = ciphertextAndTag.dropLast(16)

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: Data(ciphertext),
            tag: Data(tag)
        )

        do {
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            guard let body = String(data: decryptedData, encoding: .utf8) else {
                throw CryptoServiceError.decryptionFailed
            }
            return body
        } catch {
            throw CryptoServiceError.authenticationFailed
        }
    }
}

private extension Data {
    nonisolated func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    nonisolated init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padLength = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padLength))
        self.init(base64Encoded: base64)
    }
}
