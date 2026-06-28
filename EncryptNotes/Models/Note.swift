import Foundation

struct Note: Identifiable, Equatable, Sendable {
    let id: String
    var body: String
    let createdAt: Date
    var updatedAt: Date
    let isEncrypted: Bool

    init(
        id: String = UUID().uuidString,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isEncrypted: Bool = false
    ) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isEncrypted = isEncrypted
    }
}
