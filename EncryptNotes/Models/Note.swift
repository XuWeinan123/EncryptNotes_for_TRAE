import Foundation

nonisolated struct Note: Identifiable, Equatable, Sendable {
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

nonisolated enum NoteTitleFormatter {
    static let maxTitleLength = 72

    static func displayTitle(from body: String, emptyTitle: String = "空笔记") -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return emptyTitle }

        let firstLine = trimmed.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? emptyTitle
        let normalized = stripLeadingHeadingMarker(from: firstLine.trimmingCharacters(in: .whitespacesAndNewlines))
        return normalized.isEmpty ? emptyTitle : normalized
    }

    static func fileName(for noteId: String, body: String) -> String {
        let title = displayTitle(from: body)
        return fileName(for: noteId, title: title)
    }

    static func fileName(for noteId: String, title: String) -> String {
        let cleaned = sanitizedTitle(title, emptyTitle: "空笔记")
        return "\(cleaned)-\(noteId).md"
    }

    static func displayTitle(fromFileName fileName: String, noteId: String, emptyTitle: String = "空笔记") -> String {
        let suffix = "-\(noteId).md"
        guard fileName.hasSuffix(suffix) else { return emptyTitle }

        let rawTitle = String(fileName.dropLast(suffix.count))
        let cleaned = sanitizedTitle(rawTitle, emptyTitle: emptyTitle)
        return cleaned.isEmpty ? emptyTitle : cleaned
    }

    static func sanitizedGeneratedTitle(_ title: String) -> String? {
        let cleaned = sanitizedTitle(title, emptyTitle: "")
        return cleaned.isEmpty ? nil : cleaned
    }

    static func firstNonEmptyLineIsMarkdownHeading(in body: String) -> Bool {
        guard let firstLine = body.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return false
        }

        guard let firstNonHash = firstLine.firstIndex(where: { $0 != "#" }) else {
            return false
        }

        let marker = firstLine[..<firstNonHash]
        return (1...6).contains(marker.count)
            && firstNonHash < firstLine.endIndex
            && firstLine[firstNonHash].isWhitespace
            && !firstLine[firstNonHash...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func sanitizedTitle(_ title: String, emptyTitle: String) -> String {
        let firstLine = title.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        var normalized = stripLeadingHeadingMarker(from: firstLine.trimmingCharacters(in: .whitespacesAndNewlines))
        normalized = stripWrappingPunctuation(from: normalized)
        normalized = stripLeadingHeadingMarker(from: normalized)

        let invalidScalars = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleanedScalars = normalized.unicodeScalars.map { scalar in
            invalidScalars.contains(scalar) ? UnicodeScalar(45)! : scalar
        }
        var cleaned = String(String.UnicodeScalarView(cleanedScalars))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-"))

        if cleaned.isEmpty {
            cleaned = emptyTitle
        }

        if cleaned.count > maxTitleLength {
            cleaned = String(cleaned.prefix(maxTitleLength)).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        }

        return cleaned
    }

    private static func stripLeadingHeadingMarker(from line: String) -> String {
        guard let firstNonHash = line.firstIndex(where: { $0 != "#" }) else {
            return line
        }

        let marker = line[..<firstNonHash]
        guard (1...6).contains(marker.count),
              firstNonHash < line.endIndex,
              line[firstNonHash].isWhitespace else {
            return line
        }

        return line[firstNonHash...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripWrappingPunctuation(from title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("`", "`"),
            ("“", "”"),
            ("‘", "’"),
            ("《", "》"),
            ("「", "」"),
            ("『", "』")
        ]

        var didStrip = true
        while didStrip, result.count >= 2 {
            didStrip = false
            for (open, close) in pairs {
                if result.first == open, result.last == close {
                    result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                    didStrip = true
                    break
                }
            }
        }

        return result
    }
}
