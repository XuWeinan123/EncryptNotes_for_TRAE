import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notFound
    case dataConversionFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status): return "Failed to save to Keychain: \(status)"
        case .loadFailed(let status): return "Failed to load from Keychain: \(status)"
        case .deleteFailed(let status): return "Failed to delete from Keychain: \(status)"
        case .notFound: return "Key not found in Keychain"
        case .dataConversionFailed: return "Data conversion failed"
        }
    }
}

/// Test seam over the Keychain-backed key store so VaultStore can be driven with
/// an in-memory fake in unit tests. Conformed by `KeychainStore`.
protocol KeyStore: AnyObject {
    func saveKey(_ keyMaterial: String, forVaultId vaultId: String, keyId: String?, keyFingerprint: String?) throws
    func loadKey(forVaultId vaultId: String) throws -> String
    func loadKeyId(forVaultId vaultId: String) -> String?
    func loadKeyFingerprint(forVaultId vaultId: String) -> String?
    func saveKeyMetadata(keyId: String?, keyFingerprint: String, forVaultId vaultId: String) throws
    func deleteKey(forVaultId vaultId: String) throws
    func hasKey(forVaultId vaultId: String) -> Bool
    /// Every account under the service that holds key material (i.e. excluding the
    /// `.key_id` / `.key_fingerprint` metadata accounts). Used to adopt a legacy vault id.
    func allVaultIdCandidates() -> [String]
}

final class KeychainStore: KeyStore {
    static let shared = KeychainStore()

    private let service = "com.xuweinan.sealnote"

    private init() {}

    func saveKey(
        _ keyMaterial: String,
        forVaultId vaultId: String,
        keyId: String? = nil,
        keyFingerprint: String? = nil
    ) throws {
        try saveString(keyMaterial, account: vaultId)
        if let keyId {
            try saveString(keyId, account: metadataAccount(forVaultId: vaultId, field: "key_id"))
        }
        if let keyFingerprint {
            try saveString(keyFingerprint, account: metadataAccount(forVaultId: vaultId, field: "key_fingerprint"))
        }
    }

    func saveString(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadKey(forVaultId vaultId: String) throws -> String {
        try loadString(account: vaultId)
    }

    func loadKeyId(forVaultId vaultId: String) -> String? {
        try? loadString(account: metadataAccount(forVaultId: vaultId, field: "key_id"))
    }

    func loadKeyFingerprint(forVaultId vaultId: String) -> String? {
        try? loadString(account: metadataAccount(forVaultId: vaultId, field: "key_fingerprint"))
    }

    func saveKeyMetadata(keyId: String?, keyFingerprint: String, forVaultId vaultId: String) throws {
        if let keyId {
            try saveString(keyId, account: metadataAccount(forVaultId: vaultId, field: "key_id"))
        }
        try saveString(keyFingerprint, account: metadataAccount(forVaultId: vaultId, field: "key_fingerprint"))
    }

    func loadString(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data,
              let keyMaterial = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        return keyMaterial
    }

    func deleteKey(forVaultId vaultId: String) throws {
        try deleteString(account: vaultId)
        try deleteString(account: metadataAccount(forVaultId: vaultId, field: "key_id"))
        try deleteString(account: metadataAccount(forVaultId: vaultId, field: "key_fingerprint"))
    }

    func deleteString(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func hasKey(forVaultId vaultId: String) -> Bool {
        hasString(account: vaultId)
    }

    func hasString(account: String) -> Bool {
        do {
            _ = try loadString(account: account)
            return true
        } catch {
            return false
        }
    }

    func allVaultIdCandidates() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }

        var ids: [String] = []
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            if account.hasSuffix(".key_id") || account.hasSuffix(".key_fingerprint") { continue }
            ids.append(account)
        }
        return ids
    }

    func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    private func metadataAccount(forVaultId vaultId: String, field: String) -> String {
        "\(vaultId).\(field)"
    }
}
