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

nonisolated enum NoteListOrdering {
    static func newestCreatedFirst(_ lhs: NoteListItem, _ rhs: NoteListItem) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id < rhs.id
    }
}

nonisolated enum NoteTitleFormatter {
    static let emptyTitle = "Untitled Note"
    static let generatedTitleMaxLength = 20

    static func displayTitle(from body: String, emptyTitle: String = Self.emptyTitle) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return emptyTitle }

        let firstLine = trimmed.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? emptyTitle
        let normalized = stripLeadingHeadingMarker(from: firstLine.trimmingCharacters(in: .whitespacesAndNewlines))
        return normalized.isEmpty ? emptyTitle : normalized
    }

    static func fileName(for noteId: String, body: String) -> String {
        fileName(for: body)
    }

    static func fileName(for body: String) -> String {
        let title = displayTitle(from: body)
        let shouldLimit = !firstNonEmptyLineIsMarkdownHeading(in: body)
        return fileName(forTitle: title, limitsLength: shouldLimit)
    }

    static func fileName(for noteId: String, title: String) -> String {
        fileName(forTitle: title)
    }

    static func fileName(forTitle title: String, limitsLength: Bool = true) -> String {
        "\(fileBaseName(forTitle: title, limitsLength: limitsLength)).md"
    }

    static func fileBaseName(forTitle title: String, limitsLength: Bool = true) -> String {
        sanitizedTitle(title, emptyTitle: Self.emptyTitle, limitsLength: limitsLength)
    }

    static func displayTitle(fromFileName fileName: String, emptyTitle: String = Self.emptyTitle) -> String {
        let stem = fileName.hasSuffix(".md") ? String(fileName.dropLast(3)) : fileName
        let cleaned = sanitizedTitle(removingNumericSuffix(from: stem), emptyTitle: emptyTitle)
        return cleaned.isEmpty ? emptyTitle : cleaned
    }

    static func displayTitle(fromFileName fileName: String, noteId: String, emptyTitle: String = Self.emptyTitle) -> String {
        let cleaned = displayTitle(fromFileName: fileName, emptyTitle: emptyTitle)
        return cleaned.isEmpty ? emptyTitle : cleaned
    }

    static func sanitizedGeneratedTitle(_ title: String, limitsLength: Bool = true) -> String? {
        let cleaned = sanitizedTitle(title, emptyTitle: "", limitsLength: limitsLength)
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

    private static func sanitizedTitle(_ title: String, emptyTitle: String, limitsLength: Bool = false) -> String {
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

        if limitsLength && cleaned.count > generatedTitleMaxLength {
            cleaned = String(cleaned.prefix(generatedTitleMaxLength)).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        }

        return cleaned
    }

    private static func removingNumericSuffix(from title: String) -> String {
        title.replacingOccurrences(
            of: #"（\d+）$"#,
            with: "",
            options: .regularExpression
        )
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
