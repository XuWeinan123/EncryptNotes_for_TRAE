import Foundation
import CryptoKit

enum CryptoError: Error, LocalizedError {
    case keyGenerationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidKeyLength
    case invalidKeyMaterial
    case keyValidationFailed
    case keyNotFound

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed: return "Failed to generate encryption key"
        case .encryptionFailed: return "Encryption failed"
        case .decryptionFailed: return "Decryption failed"
        case .invalidKeyLength: return "Invalid key length"
        case .invalidKeyMaterial: return "Invalid key material"
        case .keyValidationFailed: return "Key validation failed"
        case .keyNotFound: return "Key not found"
        }
    }
}

final class VaultKeyManager {
    static let shared = VaultKeyManager()

    private init() {}

    func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    func keyToBase64(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { bytes in
            Data(bytes).base64EncodedString()
        }
    }

    func keyFromBase64(_ base64: String) throws -> SymmetricKey {
        guard let data = Data(base64Encoded: base64) else {
            throw CryptoError.invalidKeyMaterial
        }
        guard data.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        return SymmetricKey(data: data)
    }

    func generateVaultKey(key: SymmetricKey) -> VaultKey {
        VaultKey(
            version: 2,
            app: VaultKey.appName,
            type: "vault_key",
            keyId: UUID().uuidString,
            algorithm: VaultKey.algorithmAES256,
            createdAt: Date(),
            keyMaterial: keyToBase64(key)
        )
    }

    func validateVaultKey(_ key: VaultKey) -> Bool {
        guard key.version == 2 else { return false }
        guard key.app == VaultKey.appName else { return false }
        guard key.type == "vault_key" else { return false }
        guard !key.keyId.isEmpty else { return false }
        guard key.algorithm == VaultKey.algorithmAES256 else { return false }
        guard key.keyMaterial.count == 44 else { return false }
        return true
    }

    func extractKey(_ vaultKey: VaultKey) throws -> SymmetricKey {
        try keyFromBase64(vaultKey.keyMaterial)
    }
}
