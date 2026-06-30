import Foundation

nonisolated struct VaultKey: Codable {
    let version: Int
    let app: String
    let type: String
    let keyId: String
    let algorithm: String
    let createdAt: Date
    let keyMaterial: String

    enum CodingKeys: String, CodingKey {
        case version, app, type, algorithm
        case keyId = "key_id"
        case createdAt = "created_at"
        case keyMaterial = "key_material"
    }

    static let algorithmAES256 = "AES-GCM-256"
}
