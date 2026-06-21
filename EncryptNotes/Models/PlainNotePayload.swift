import Foundation

struct PlainNotePayload: Codable {
    var title: String
    var body: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case title, body, tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(title: String = "", body: String, tags: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.title = title
        self.body = body
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
