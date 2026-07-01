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

final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.biekanwo.encryptnotes"

    private init() {}

    func saveKey(_ keyMaterial: String, forVaultId vaultId: String) throws {
        try saveString(keyMaterial, account: vaultId)
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
}
