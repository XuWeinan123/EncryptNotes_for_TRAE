import Foundation

struct MarkdownNoteFile: Sendable {
    let noteId: String
    let createdAt: Date
    var updatedAt: Date
    var body: String

    var isEncrypted: Bool {
        body.hasPrefix(MarkdownNoteFile.encryptedPrefix)
    }

    static let encryptedPrefix = "bkwenc:v1:"

    init(noteId: String, createdAt: Date, updatedAt: Date, body: String) {
        self.noteId = noteId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.body = body
    }

    static func parse(from data: Data) throws -> MarkdownNoteFile {
        guard let content = String(data: data, encoding: .utf8) else {
            throw StorageError.invalidData
        }
        return try parse(from: content)
    }

    static func parse(from content: String) throws -> MarkdownNoteFile {
        let fullStart = "---\n"
        guard content.hasPrefix(fullStart) else {
            throw StorageError.invalidData
        }

        let afterStart = content.dropFirst(fullStart.count)

        var frontmatterEndIdx: String.Index? = nil
        var bodyStartIdx: String.Index? = nil

        let searchStr = "\n---"
        var searchPos = afterStart.startIndex
        while true {
            guard let range = afterStart[searchPos...].range(of: searchStr) else {
                break
            }
            let candidateStart = range.lowerBound
            let afterDelimiter = range.upperBound

            if afterDelimiter == afterStart.endIndex {
                frontmatterEndIdx = candidateStart
                bodyStartIdx = afterDelimiter
                break
            }

            let nextChar = afterStart[afterDelimiter]
            if nextChar == "\n" {
                frontmatterEndIdx = candidateStart
                bodyStartIdx = afterStart.index(after: afterDelimiter)
                break
            }

            searchPos = afterDelimiter
        }

        guard let fmEnd = frontmatterEndIdx, let bStart = bodyStartIdx else {
            throw StorageError.invalidData
        }

        let frontmatterStr = String(afterStart[..<fmEnd])
        let body = String(afterStart[bStart...])

        var noteId: String?
        var createdAt: Date?
        var updatedAt: Date?

        let lines = frontmatterStr.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }

            switch key {
            case "note_id":
                noteId = value
            case "created_at":
                createdAt = iso8601Date(from: value)
            case "updated_at":
                updatedAt = iso8601Date(from: value)
            default:
                break
            }
        }

        guard let nid = noteId, !nid.isEmpty else {
            throw StorageError.invalidData
        }
        guard let ca = createdAt else {
            throw StorageError.invalidData
        }
        guard let ua = updatedAt else {
            throw StorageError.invalidData
        }

        return MarkdownNoteFile(
            noteId: nid,
            createdAt: ca,
            updatedAt: ua,
            body: body
        )
    }

    func render() throws -> Data {
        let createdStr = iso8601String(from: createdAt)
        let updatedStr = iso8601String(from: updatedAt)

        let frontmatter = "---\nnote_id: \"\(noteId)\"\ncreated_at: \"\(createdStr)\"\nupdated_at: \"\(updatedStr)\"\n---"

        let md: String
        if body.isEmpty {
            md = frontmatter + "\n"
        } else {
            md = frontmatter + "\n\n" + body
        }

        guard let data = md.data(using: .utf8) else {
            throw StorageError.invalidData
        }
        return data
    }

    func toNote() -> Note {
        Note(
            id: noteId,
            body: isEncrypted ? "" : body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isEncrypted: isEncrypted
        )
    }
}

private let _iso8601FormatterWithFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let _iso8601FormatterNoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private func iso8601Date(from string: String) -> Date? {
    if let d = _iso8601FormatterWithFractional.date(from: string) {
        return d
    }
    return _iso8601FormatterNoFractional.date(from: string)
}

private func iso8601String(from date: Date) -> String {
    _iso8601FormatterWithFractional.string(from: date)
}
