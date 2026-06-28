import Foundation

struct TrashNote: Identifiable, Equatable, Sendable {
    let id: String
    let isEncrypted: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date
    let purgeAfter: Date
    let url: URL

    let body: String?
    let ciphertextPreview: String?
    let fileSize: Int

    var isReadable: Bool { body != nil }

    var remainingDays: Int {
        let seconds = purgeAfter.timeIntervalSinceNow
        return max(0, Int(ceil(seconds / 86400)))
    }
}
