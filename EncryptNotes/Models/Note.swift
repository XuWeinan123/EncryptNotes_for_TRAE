import Foundation

struct Note: Identifiable, Equatable {
    let id: String
    let vaultId: String
    var body: String
    let createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, vaultId: String, body: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.vaultId = vaultId
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from payload: PlainNotePayload, noteId: String, vaultId: String) {
        self.id = noteId
        self.vaultId = vaultId
        self.body = payload.body
        self.createdAt = payload.createdAt
        self.updatedAt = payload.updatedAt
    }

    func toPayload() -> PlainNotePayload {
        PlainNotePayload(body: body, createdAt: createdAt, updatedAt: updatedAt)
    }
}
