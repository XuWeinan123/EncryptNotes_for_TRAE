import Foundation

nonisolated struct MarkdownNoteFile: Sendable {
    let noteId: String
    let createdAt: Date
    var updatedAt: Date
    var title: String?
    var body: String

    var isEncrypted: Bool {
        body.hasPrefix(MarkdownNoteFile.encryptedPrefix)
    }

    static let encryptedPrefix = "snenc:v1:"

    init(noteId: String, createdAt: Date, updatedAt: Date, title: String? = nil, body: String) {
        self.noteId = noteId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
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
        var bodyStart = bStart
        if bodyStart < afterStart.endIndex, afterStart[bodyStart] == "\n" {
            bodyStart = afterStart.index(after: bodyStart)
        }
        let body = String(afterStart[bodyStart...])

        var noteId: String?
        var createdAt: Date?
        var updatedAt: Date?
        var title: String?

        let lines = frontmatterStr.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            value = unquoteYAMLString(value)

            switch key {
            case "note_id":
                noteId = value
            case "created_at":
                createdAt = iso8601Date(from: value)
            case "updated_at":
                updatedAt = iso8601Date(from: value)
            case "title":
                title = value
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
            title: title,
            body: body
        )
    }

    func render() throws -> Data {
        let createdStr = iso8601String(from: createdAt)
        let updatedStr = iso8601String(from: updatedAt)

        var frontmatterLines = [
            "---",
            "note_id: \"\(escapeYAMLString(noteId))\"",
            "created_at: \"\(createdStr)\"",
            "updated_at: \"\(updatedStr)\""
        ]
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            frontmatterLines.append("title: \"\(escapeYAMLString(title))\"")
        }
        frontmatterLines.append("---")
        let frontmatter = frontmatterLines.joined(separator: "\n")

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

nonisolated private func unquoteYAMLString(_ string: String) -> String {
    guard string.hasPrefix("\""), string.hasSuffix("\""), string.count >= 2 else {
        return string
    }
    let unquoted = String(string.dropFirst().dropLast())
    var result = ""
    var isEscaping = false
    for character in unquoted {
        if isEscaping {
            result.append(character)
            isEscaping = false
        } else if character == "\\" {
            isEscaping = true
        } else {
            result.append(character)
        }
    }
    if isEscaping {
        result.append("\\")
    }
    return result
}

nonisolated private func escapeYAMLString(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

nonisolated private func iso8601Date(from string: String) -> Date? {
    let formatterWithFractional = ISO8601DateFormatter()
    formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = formatterWithFractional.date(from: string) {
        return d
    }

    let formatterNoFractional = ISO8601DateFormatter()
    formatterNoFractional.formatOptions = [.withInternetDateTime]
    return formatterNoFractional.date(from: string)
}

nonisolated private func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
