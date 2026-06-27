import Foundation

struct PlainNotePayload: Codable, Sendable {
    var body: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(body: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
