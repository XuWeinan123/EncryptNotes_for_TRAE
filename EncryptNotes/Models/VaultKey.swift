import Foundation

struct VaultKey: Codable {
    let version: Int
    let app: String
    let type: String
    let vaultId: String
    let keyVersion: Int
    let algorithm: String
    let createdAt: Date
    let keyMaterial: String

    enum CodingKeys: String, CodingKey {
        case version, app, type, algorithm
        case vaultId = "vault_id"
        case keyVersion = "key_version"
        case createdAt = "created_at"
        case keyMaterial = "key_material"
    }

    static let algorithmAES256 = "AES-GCM-256"
}
