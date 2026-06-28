import Foundation

enum NoteFileMode: String, Codable, Sendable {
    case plain
    case encrypted
}

enum NoteFileLocation: String, Codable, Sendable {
    case notes
    case trash
}

struct NoteIndexEntry: Codable, Equatable, Sendable {
    let noteId: String
    let fileName: String
    let mode: NoteFileMode
    var location: NoteFileLocation
    var deletedAt: Date?
    var purgeAfter: Date?
    var originalLocation: NoteFileLocation?

    enum CodingKeys: String, CodingKey {
        case mode, location
        case noteId = "note_id"
        case fileName = "file_name"
        case deletedAt = "deleted_at"
        case purgeAfter = "purge_after"
        case originalLocation = "original_location"
    }

    init(
        noteId: String,
        fileName: String,
        mode: NoteFileMode,
        location: NoteFileLocation,
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil,
        originalLocation: NoteFileLocation? = nil
    ) {
        self.noteId = noteId
        self.fileName = fileName
        self.mode = mode
        self.location = location
        self.deletedAt = deletedAt
        self.purgeAfter = purgeAfter
        self.originalLocation = originalLocation
    }
}

struct NoteIndex: Codable, Sendable {
    let version: Int
    let app: String
    let type: String
    var entries: [NoteIndexEntry]

    init(entries: [NoteIndexEntry] = []) {
        self.version = 1
        self.app = "BieKanWo"
        self.type = "note_index"
        self.entries = entries
    }

    func entry(for noteId: String) -> NoteIndexEntry? {
        entries.first { $0.noteId == noteId }
    }

    mutating func upsert(_ entry: NoteIndexEntry) {
        if let idx = entries.firstIndex(where: { $0.noteId == entry.noteId }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
    }

    mutating func removeEntry(for noteId: String) {
        entries.removeAll { $0.noteId == noteId }
    }
}
