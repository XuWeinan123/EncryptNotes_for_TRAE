import Foundation

struct Note: Identifiable, Equatable {
    let id: String
    let vaultId: String
    var title: String
    var body: String
    var tags: [String]
    let createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, vaultId: String, title: String, body: String, tags: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.vaultId = vaultId
        self.title = title
        self.body = body
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from payload: PlainNotePayload, noteId: String, vaultId: String) {
        self.id = noteId
        self.vaultId = vaultId
        self.title = payload.title
        self.body = payload.body
        self.tags = payload.tags
        self.createdAt = payload.createdAt
        self.updatedAt = payload.updatedAt
    }

    func toPayload() -> PlainNotePayload {
        PlainNotePayload(title: title, body: body, tags: tags, createdAt: createdAt, updatedAt: updatedAt)
    }
}
