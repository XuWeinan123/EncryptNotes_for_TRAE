import Foundation

struct VaultManifest: Codable {
    let version: Int
    let app: String
    let type: String
    let vaultId: String
    let createdAt: Date
    let updatedAt: Date
    let keyVersion: Int

    enum CodingKeys: String, CodingKey {
        case version, app, type
        case vaultId = "vault_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case keyVersion = "key_version"
    }
}
