import Foundation

enum MacMarkdownFormatCommand {
    case bold
    case italic
    case underline
    case inlineCode
    case inlineMath
    case strike
    case htmlComment
    case link
}

struct MacMarkdownFormatResult: Equatable {
    let text: String
    let selection: NSRange
}

struct MacMarkdownListContinuationResult: Equatable {
    let text: String
    let selection: NSRange
}

final class MacMarkdownFormatter {

    static func apply(command: MacMarkdownFormatCommand, to text: String, selection: NSRange) -> MacMarkdownFormatResult {
        let nsText = text as NSString
        let safeRange = NSRange(
            location: max(0, min(selection.location, nsText.length)),
            length: max(0, min(selection.length, nsText.length - max(0, min(selection.location, nsText.length))))
        )

        switch command {
        case .bold:
            return applyWrapper(text: text, selection: safeRange, open: "**", close: "**", placeholder: "strong", supportsToggle: true)
        case .italic:
            return applyWrapper(text: text, selection: safeRange, open: "*", close: "*", placeholder: "emphasis", supportsToggle: true)
        case .underline:
            return applyWrapper(text: text, selection: safeRange, open: "<u>", close: "</u>", placeholder: "underline", supportsToggle: true)
        case .inlineCode:
            return applyWrapper(text: text, selection: safeRange, open: "`", close: "`", placeholder: "code", supportsToggle: true)
        case .inlineMath:
            return applyWrapper(text: text, selection: safeRange, open: "$", close: "$", placeholder: "math", supportsToggle: true)
        case .strike:
            return applyWrapper(text: text, selection: safeRange, open: "~~", close: "~~", placeholder: "strike", supportsToggle: true)
        case .htmlComment:
            return applyWrapper(text: text, selection: safeRange, open: "<!-- ", close: " -->", placeholder: "comment", supportsToggle: true)
        case .link:
            return applyLink(text: text, selection: safeRange)
        }
    }

    private static func applyWrapper(text: String, selection: NSRange, open: String, close: String, placeholder: String, supportsToggle: Bool) -> MacMarkdownFormatResult {
        let nsText = text as NSString
        let selectedText = safeSubstring(nsText: nsText, range: selection)
        let openLen = open.utf16.count
        let closeLen = close.utf16.count

        if supportsToggle && selection.length > 0 {
            let beforeLoc = max(0, selection.location - openLen)
            let beforeRange = NSRange(location: beforeLoc, length: min(openLen, nsText.length - beforeLoc))
            let afterLoc = selection.location + selection.length
            let afterRange = NSRange(location: afterLoc, length: min(closeLen, nsText.length - afterLoc))
            if beforeRange.length == openLen && afterRange.length == closeLen {
                let before = nsText.substring(with: beforeRange)
                let after = nsText.substring(with: afterRange)
                if before == open && after == close {
                    var newText = text
                    newText = (nsText.substring(with: NSRange(location: 0, length: beforeLoc)) as NSString)
                        .appending(selectedText)
                    let remaining = nsText.substring(from: afterLoc + closeLen)
                    newText = newText.appending(remaining)
                    let newSelection = NSRange(location: beforeLoc, length: selection.length)
                    return MacMarkdownFormatResult(text: newText, selection: newSelection)
                }
            }
        }

        let insertText: String
        let newCursorStart: Int
        let newCursorLength: Int

        if selection.length == 0 {
            insertText = open + placeholder + close
            newCursorStart = selection.location + openLen
            newCursorLength = placeholder.utf16.count
        } else {
            insertText = open + selectedText + close
            newCursorStart = selection.location + openLen
            newCursorLength = selection.length
        }

        var newText = text
        newText = (nsText.substring(with: NSRange(location: 0, length: selection.location)) as NSString).appending(insertText)
        newText = newText.appending(nsText.substring(from: selection.location + selection.length))

        return MacMarkdownFormatResult(text: newText, selection: NSRange(location: newCursorStart, length: newCursorLength))
    }

    private static func applyLink(text: String, selection: NSRange) -> MacMarkdownFormatResult {
        let nsText = text as NSString
        let selectedText = safeSubstring(nsText: nsText, range: selection)

        let insertText: String
        let newCursorStart: Int
        let newCursorLength: Int

        if selection.length == 0 {
            insertText = "[]()"
            newCursorStart = selection.location + 1
            newCursorLength = 0
        } else {
            insertText = "[" + selectedText + "]()"
            newCursorStart = selection.location + selection.length + 3
            newCursorLength = 0
        }

        var newText = text
        newText = (nsText.substring(with: NSRange(location: 0, length: selection.location)) as NSString).appending(insertText)
        newText = newText.appending(nsText.substring(from: selection.location + selection.length))

        return MacMarkdownFormatResult(text: newText, selection: NSRange(location: newCursorStart, length: newCursorLength))
    }

    private static func safeSubstring(nsText: NSString, range: NSRange) -> String {
        if range.location >= nsText.length { return "" }
        let safeLength = min(range.length, nsText.length - range.location)
        return nsText.substring(with: NSRange(location: range.location, length: safeLength))
    }

    static func continueListIfNeeded(in text: String, selection: NSRange) -> MacMarkdownListContinuationResult? {
        guard selection.length == 0 else { return nil }
        let nsText = text as NSString
        let cursor = max(0, min(selection.location, nsText.length))
        guard !isInsideFencedCodeBlock(text: text, cursor: cursor) else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let lineStart = lineRange.location
        let lineLengthToCursor = max(0, cursor - lineStart)
        let currentLine = nsText.substring(with: NSRange(location: lineStart, length: lineLengthToCursor))
        guard let marker = ListMarker(line: currentLine) else { return nil }

        if marker.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let newText = nsText.substring(to: lineStart) + nsText.substring(from: cursor)
            return MacMarkdownListContinuationResult(
                text: newText,
                selection: NSRange(location: lineStart, length: 0)
            )
        }

        let nextMarker = marker.nextMarker
        let insertion = "\n\(marker.indent)\(nextMarker)"
        let newText = nsText.substring(to: cursor) + insertion + nsText.substring(from: cursor)
        return MacMarkdownListContinuationResult(
            text: newText,
            selection: NSRange(location: cursor + (insertion as NSString).length, length: 0)
        )
    }

    static func stringByAddingMarkdownParagraphSpacing(to text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }

        var output: [String] = []
        var inFence = false

        for index in lines.indices {
            let line = lines[index]
            output.append(line)

            if isFenceLine(line) {
                inFence.toggle()
                continue
            }

            guard !inFence, index < lines.index(before: lines.endIndex) else { continue }
            let nextLine = lines[lines.index(after: index)]
            if isNormalParagraphLine(line), isNormalParagraphLine(nextLine) {
                output.append("")
            }
        }

        return output.joined(separator: "\n")
    }

    private static func isInsideFencedCodeBlock(text: String, cursor: Int) -> Bool {
        let nsText = text as NSString
        let prefix = nsText.substring(to: max(0, min(cursor, nsText.length)))
        var inFence = false
        for line in prefix.components(separatedBy: "\n") {
            if isFenceLine(line) {
                inFence.toggle()
            }
        }
        return inFence
    }

    private static func isFenceLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func isNormalParagraphLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if isFenceLine(line) { return false }
        if trimmed.hasPrefix("#") || trimmed.hasPrefix(">") { return false }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") { return false }
        if trimmed.hasPrefix("|") { return false }
        if trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil { return false }
        return true
    }

    private struct ListMarker {
        let indent: String
        let nextMarker: String
        let content: String

        init?(line: String) {
            let pattern = #"^(\s*)(?:(\d+)([\.\)])|([-+*]))\s+(.*)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let nsLine = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else { return nil }

            indent = nsLine.substring(with: match.range(at: 1))
            content = nsLine.substring(with: match.range(at: 5))

            if match.range(at: 2).location != NSNotFound {
                let number = Int(nsLine.substring(with: match.range(at: 2))) ?? 0
                let delimiter = nsLine.substring(with: match.range(at: 3))
                nextMarker = "\(number + 1)\(delimiter) "
            } else if match.range(at: 4).location != NSNotFound {
                nextMarker = nsLine.substring(with: match.range(at: 4)) + " "
            } else {
                return nil
            }
        }
    }
}
