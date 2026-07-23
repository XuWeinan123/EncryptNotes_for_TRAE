import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#endif
#if os(iOS)
import UIKit
import SwiftUI
#endif

enum MarkdownHighlightRole: Equatable {
    case headingMarker
    case headingText(level: Int)
    case emphasisMarker
    case strongText
    case italicText
    case strikeText
    case underlineText
    case inlineCode
    case codeFenceMarker
    case codeBlockText
    case listMarker
    case taskMarker
    case quoteMarker
    case linkText
    case linkURL
    case imageMarker
    case tableDelimiter
    case horizontalRule
    case htmlComment
}

struct MarkdownHighlightSpan {
    let range: NSRange
    let role: MarkdownHighlightRole
}

final class MarkdownHighlighter {
    private enum RegexCache {
        static let codeFence = try! NSRegularExpression(pattern: "^([ \\t]{0,3})(```|~~~)([^`~\\n]*)$", options: [.anchorsMatchLines])
        static let heading = try! NSRegularExpression(pattern: "^(\\s{0,3})(#{1,6})(\\s+)(.*)$", options: [.anchorsMatchLines])
        static let taskList = try! NSRegularExpression(pattern: "^(\\s*)([-*+])\\s+\\[([ xX])\\]\\s+", options: [.anchorsMatchLines])
        static let unorderedList = try! NSRegularExpression(pattern: "^(\\s*)([-*+])\\s+", options: [.anchorsMatchLines])
        static let orderedList = try! NSRegularExpression(pattern: "^(\\s*)(\\d+)([.)])\\s+", options: [.anchorsMatchLines])
        static let quote = try! NSRegularExpression(pattern: "^(\\s*)(>+)\\s?", options: [.anchorsMatchLines])
        static let htmlComment = try! NSRegularExpression(pattern: "^\\s*(<!--.*?-->)\\s*$")
        static let image = try! NSRegularExpression(pattern: "(!)(\\[)([^\\]]*)(\\])(\\()([^)]*)(\\))")
        static let link = try! NSRegularExpression(pattern: "(?<!!)(\\[)([^\\]]+)(\\])(\\()([^)]+)(\\))")
        static let inlineCode = try! NSRegularExpression(pattern: "`([^`\\n]+?)`")
        static let underline = try! NSRegularExpression(pattern: "(<u>)([^<]+)(</u>)", options: [.caseInsensitive])
        static let boldRange = try! NSRegularExpression(pattern: "(\\*\\*[^*]+\\*\\*|__[^_]+__)")
    }

    static func highlight(_ text: String) -> [MarkdownHighlightSpan] {
        guard !text.isEmpty else { return [] }
        let nsString = text as NSString
        var spans: [MarkdownHighlightSpan] = []

        let codeBlockRanges = findCodeFenceRanges(in: text, nsString: nsString)
        spans.append(contentsOf: codeBlockRanges.spans)

        let tableRanges = findTableRanges(in: text, nsString: nsString, excludedRanges: codeBlockRanges.totalRanges)
        spans.append(contentsOf: tableRanges.spans)

        let lines = text.components(separatedBy: .newlines)
        var currentLocation = 0

        for (_, line) in lines.enumerated() {
            let lineRange = NSRange(location: currentLocation, length: (line as NSString).length)
            let isInCodeBlock = codeBlockRanges.totalRanges.contains { NSIntersectionRange(lineRange, $0).length > 0 }
            let isInTable = tableRanges.totalRanges.contains { NSIntersectionRange(lineRange, $0).length > 0 }

            if !isInCodeBlock {
                if let hrSpan = matchHorizontalRule(line: line, lineRange: lineRange) {
                    spans.append(hrSpan)
                    currentLocation += line.utf16.count + 1
                    continue
                }

                if let headingSpans = matchHeading(line: line, lineRange: lineRange) {
                    spans.append(contentsOf: headingSpans)
                } else if let listSpans = matchList(line: line, lineRange: lineRange, inTable: isInTable) {
                    spans.append(contentsOf: listSpans)
                } else if let quoteSpans = matchQuote(line: line, lineRange: lineRange) {
                    spans.append(contentsOf: quoteSpans)
                }
            }

            if !isInCodeBlock {
                let inlineSpans = matchInlineElements(
                    in: line,
                    lineRange: lineRange,
                    excludedRanges: codeBlockRanges.totalRanges
                )
                spans.append(contentsOf: inlineSpans)
            }

            currentLocation += line.utf16.count + 1
        }

        return mergedSortedSpans(spans)
    }

    private struct BlockRanges {
        let spans: [MarkdownHighlightSpan]
        let totalRanges: [NSRange]
    }

    private struct FencePosition {
        let lineRange: NSRange
        let markerRange: NSRange
        let line: String
    }

    private static func findCodeFenceRanges(in text: String, nsString: NSString) -> BlockRanges {
        var spans: [MarkdownHighlightSpan] = []
        var totalRanges: [NSRange] = []
        let matches = RegexCache.codeFence.matches(in: text, options: [], range: fullRange(nsString))
        var fencePositions: [FencePosition] = []

        for match in matches {
            let markerRange = match.range(at: 2)
            let lineRange = match.range
            fencePositions.append(FencePosition(
                lineRange: lineRange,
                markerRange: markerRange,
                line: nsString.substring(with: lineRange)
            ))
        }

        var i = 0
        while i < fencePositions.count - 1 {
            let opening = fencePositions[i]
            let closing = fencePositions[i + 1]
            let blockStart = opening.markerRange.location
            let blockEnd = closing.markerRange.location + closing.markerRange.length
            let totalRange = NSRange(location: blockStart, length: blockEnd - blockStart)
            totalRanges.append(totalRange)

            if isOpeningFenceWithInfo(opening.line, marker: nsString.substring(with: opening.markerRange)) {
                let markerLineRange = NSRange(
                    location: opening.markerRange.location,
                    length: opening.lineRange.location + opening.lineRange.length - opening.markerRange.location
                )
                spans.append(MarkdownHighlightSpan(range: markerLineRange, role: .codeFenceMarker))
            }
            if isClosingFenceLine(closing.line, marker: nsString.substring(with: closing.markerRange)) {
                spans.append(MarkdownHighlightSpan(range: closing.markerRange, role: .codeFenceMarker))
            }
            i += 2
        }

        return BlockRanges(spans: spans, totalRanges: totalRanges)
    }

    private static func isOpeningFenceWithInfo(_ line: String, marker: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(marker), trimmed != marker else { return false }
        return !trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isClosingFenceLine(_ line: String, marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == marker
    }

    private static func findTableRanges(in text: String, nsString: NSString, excludedRanges: [NSRange]) -> BlockRanges {
        var spans: [MarkdownHighlightSpan] = []
        var totalRanges: [NSRange] = []
        let lines = text.components(separatedBy: .newlines)
        var currentLocation = 0
        var tableStart: Int? = nil
        var tableEnd: Int? = nil

        for (idx, line) in lines.enumerated() {
            let lineRange = NSRange(location: currentLocation, length: (line as NSString).length)
            let isExcluded = excludedRanges.contains { NSIntersectionRange(lineRange, $0).length > 0 }

            let isSeparatorLine = isTableSeparatorLine(line)
            let hasPipe = line.contains("|")

            if isExcluded {
                if let start = tableStart {
                    totalRanges.append(NSRange(location: start, length: currentLocation - start))
                    tableStart = nil
                }
            } else if isSeparatorLine && idx > 0 {
                if tableStart == nil {
                    let prevLineStart = currentLocation - (lines[idx - 1] as NSString).length - 1
                    tableStart = prevLineStart
                }
                tableEnd = currentLocation + line.utf16.count
            } else if hasPipe && tableStart != nil {
                tableEnd = currentLocation + line.utf16.count
            } else if tableStart != nil {
                if let start = tableStart, let end = tableEnd {
                    let range = NSRange(location: start, length: end - start + 1)
                    totalRanges.append(range)
                    addTableDelimiterSpans(in: text, nsString: nsString, tableRange: range, spans: &spans)
                }
                tableStart = nil
                tableEnd = nil
            }

            currentLocation += line.utf16.count + 1
        }

        if let start = tableStart, let end = tableEnd {
            let range = NSRange(location: start, length: end - start)
            totalRanges.append(range)
            addTableDelimiterSpans(in: text, nsString: nsString, tableRange: range, spans: &spans)
        }

        return BlockRanges(spans: spans, totalRanges: totalRanges)
    }

    private static func isTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") || trimmed.contains("|") else { return false }
        let stripped = trimmed.replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty && trimmed.contains("-")
    }

    private static func addTableDelimiterSpans(in text: String, nsString: NSString, tableRange: NSRange, spans: inout [MarkdownHighlightSpan]) {
        let tableText = nsString.substring(with: tableRange)
        let lines = tableText.components(separatedBy: .newlines)
        var pos = tableRange.location
        for line in lines {
            let nsLine = line as NSString
            for i in 0..<nsLine.length {
                if nsLine.character(at: i) == unichar(0x7C) {
                    spans.append(MarkdownHighlightSpan(
                        range: NSRange(location: pos, length: 1),
                        role: .tableDelimiter
                    ))
                }
                pos += 1
            }
            pos += 1
        }
    }

    private static func matchHorizontalRule(line: String, lineRange: NSRange) -> MarkdownHighlightSpan? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            return MarkdownHighlightSpan(range: lineRange, role: .horizontalRule)
        }
        if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" || $0.isWhitespace }) && trimmed.count >= 3 {
            let dashes = trimmed.filter { $0 == "-" || $0 == "*" || $0 == "_" }
            if dashes.count >= 3 {
                return MarkdownHighlightSpan(range: lineRange, role: .horizontalRule)
            }
        }
        return nil
    }

    private static func matchHeading(line: String, lineRange: NSRange) -> [MarkdownHighlightSpan]? {
        let nsLine = line as NSString
        guard let match = RegexCache.heading.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }

        var spans: [MarkdownHighlightSpan] = []
        let hashRange = match.range(at: 2)
        let spaceRange = match.range(at: 3)
        let textRange = match.range(at: 4)
        let level = hashRange.length

        let markerRange = NSRange(
            location: lineRange.location + hashRange.location,
            length: hashRange.length + spaceRange.length
        )
        spans.append(MarkdownHighlightSpan(range: markerRange, role: .headingMarker))

        if textRange.length > 0 {
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + textRange.location, length: textRange.length),
                role: .headingText(level: level)
            ))
        }

        return spans
    }

    private static func matchList(line: String, lineRange: NSRange, inTable: Bool) -> [MarkdownHighlightSpan]? {
        if inTable { return nil }
        let nsLine = line as NSString

        if let match = RegexCache.taskList.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) {
            var spans: [MarkdownHighlightSpan] = []
            let bulletRange = match.range(at: 2)
            let checkboxRange = NSRange(location: match.range(at: 3).location - 1, length: match.range(at: 3).length + 2)

            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + bulletRange.location, length: bulletRange.length),
                role: .listMarker
            ))
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + checkboxRange.location, length: checkboxRange.length),
                role: .taskMarker
            ))
            return spans
        }

        if let match = RegexCache.unorderedList.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) {
            let bulletRange = match.range(at: 2)
            return [MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + bulletRange.location, length: bulletRange.length),
                role: .listMarker
            )]
        }

        if let match = RegexCache.orderedList.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) {
            let numRange = match.range(at: 2)
            let dotRange = match.range(at: 3)
            let markerRange = NSRange(
                location: lineRange.location + numRange.location,
                length: numRange.length + dotRange.length
            )
            return [MarkdownHighlightSpan(range: markerRange, role: .listMarker)]
        }

        return nil
    }

    private static func matchQuote(line: String, lineRange: NSRange) -> [MarkdownHighlightSpan]? {
        let nsLine = line as NSString
        guard let match = RegexCache.quote.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        let markerRange = match.range(at: 2)
        return [MarkdownHighlightSpan(
            range: NSRange(location: lineRange.location + markerRange.location, length: markerRange.length),
            role: .quoteMarker
        )]
    }

    private static func matchInlineElements(in line: String, lineRange: NSRange, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan] {
        var spans: [MarkdownHighlightSpan] = []
        var inlineExcluded = excludedRanges

        if let commentSpans = matchHTMLComments(in: line, lineRange: lineRange, excludedRanges: inlineExcluded) {
            spans.append(contentsOf: commentSpans)
            inlineExcluded.append(contentsOf: commentSpans.map(\.range))
        }

        if let imageSpans = matchImages(in: line, lineRange: lineRange, excludedRanges: inlineExcluded) {
            spans.append(contentsOf: imageSpans)
            inlineExcluded.append(contentsOf: imageSpans.map(\.range))
        }

        if let linkSpans = matchLinks(in: line, lineRange: lineRange, excludedRanges: inlineExcluded) {
            spans.append(contentsOf: linkSpans)
            inlineExcluded.append(contentsOf: linkSpans.map(\.range))
        }

        if let codeSpans = matchInlineCode(in: line, lineRange: lineRange, excludedRanges: inlineExcluded) {
            spans.append(contentsOf: codeSpans)
            inlineExcluded.append(contentsOf: codeSpans.map(\.range))
        }

        if let strikeSpans = matchDelimiter(in: line, lineRange: lineRange, delimiter: "~~", role: .strikeText, markerRole: .emphasisMarker, excludedRanges: inlineExcluded) {
            spans.append(contentsOf: strikeSpans)
            inlineExcluded.append(contentsOf: strikeSpans.map(\.range))
        }

        if let underlineSpans = matchUnderline(in: line, lineRange: lineRange, excludedRanges: inlineExcluded) {
            spans.append(contentsOf: underlineSpans)
            inlineExcluded.append(contentsOf: underlineSpans.map(\.range))
        }

        if let boldSpans = matchBold(in: line, lineRange: lineRange, excludedRanges: inlineExcluded) {
            spans.append(contentsOf: boldSpans)
            inlineExcluded.append(contentsOf: boldSpans.map(\.range))
        }

        if let italicSpans = matchItalic(in: line, lineRange: lineRange, excludedRanges: inlineExcluded) {
            spans.append(contentsOf: italicSpans)
        }

        return spans
    }

    private static func matchHTMLComments(in line: String, lineRange: NSRange, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        let nsLine = line as NSString
        guard let match = RegexCache.htmlComment.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        let commentRange = match.range(at: 1)
        let absoluteRange = NSRange(location: lineRange.location + commentRange.location, length: commentRange.length)
        guard !isExcluded(absoluteRange, by: excludedRanges) else { return nil }
        return [MarkdownHighlightSpan(range: absoluteRange, role: .htmlComment)]
    }

    private static func matchImages(in line: String, lineRange: NSRange, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        let nsLine = line as NSString
        let matches = RegexCache.image.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
        var spans: [MarkdownHighlightSpan] = []

        for match in matches {
            let fullRange = match.range
            let bangRange = match.range(at: 1)
            guard bangRange.length > 0 else { continue }
            let openBracketRange = match.range(at: 2)
            let textRange = match.range(at: 3)
            let closeBracketRange = match.range(at: 4)
            let openParenRange = match.range(at: 5)
            let urlRange = match.range(at: 6)
            let closeParenRange = match.range(at: 7)

            let absoluteFull = NSRange(location: lineRange.location + fullRange.location, length: fullRange.length)
            if isExcluded(absoluteFull, by: excludedRanges) { continue }

            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + bangRange.location, length: bangRange.length),
                role: .imageMarker
            ))
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + openBracketRange.location, length: openBracketRange.length),
                role: .imageMarker
            ))
            if textRange.length > 0 {
                spans.append(MarkdownHighlightSpan(
                    range: NSRange(location: lineRange.location + textRange.location, length: textRange.length),
                    role: .linkText
                ))
            }
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + closeBracketRange.location, length: closeBracketRange.length),
                role: .imageMarker
            ))
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + openParenRange.location, length: openParenRange.length),
                role: .imageMarker
            ))
            if urlRange.length > 0 {
                spans.append(MarkdownHighlightSpan(
                    range: NSRange(location: lineRange.location + urlRange.location, length: urlRange.length),
                    role: .linkURL
                ))
            }
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + closeParenRange.location, length: closeParenRange.length),
                role: .imageMarker
            ))
        }
        return spans.isEmpty ? nil : spans
    }

    private static func matchLinks(in line: String, lineRange: NSRange, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        let nsLine = line as NSString
        let matches = RegexCache.link.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
        var spans: [MarkdownHighlightSpan] = []

        for match in matches {
            let fullRange = match.range
            let openBracketRange = match.range(at: 1)
            let textRange = match.range(at: 2)
            let closeBracketRange = match.range(at: 3)
            let openParenRange = match.range(at: 4)
            let urlRange = match.range(at: 5)
            let closeParenRange = match.range(at: 6)

            let absoluteFull = NSRange(location: lineRange.location + fullRange.location, length: fullRange.length)
            if isExcluded(absoluteFull, by: excludedRanges) { continue }

            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + openBracketRange.location, length: openBracketRange.length),
                role: .emphasisMarker
            ))
            if textRange.length > 0 {
                spans.append(MarkdownHighlightSpan(
                    range: NSRange(location: lineRange.location + textRange.location, length: textRange.length),
                    role: .linkText
                ))
            }
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + closeBracketRange.location, length: closeBracketRange.length),
                role: .emphasisMarker
            ))
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + openParenRange.location, length: openParenRange.length),
                role: .emphasisMarker
            ))
            if urlRange.length > 0 {
                spans.append(MarkdownHighlightSpan(
                    range: NSRange(location: lineRange.location + urlRange.location, length: urlRange.length),
                    role: .linkURL
                ))
            }
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + closeParenRange.location, length: closeParenRange.length),
                role: .emphasisMarker
            ))
        }
        return spans.isEmpty ? nil : spans
    }

    private static func matchInlineCode(in line: String, lineRange: NSRange, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        let matches = RegexCache.inlineCode.matches(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length))
        var spans: [MarkdownHighlightSpan] = []

        for match in matches {
            let fullRange = match.range
            guard !isBacktickAdjacentMatch(fullRange, in: line) else { continue }
            let absoluteFull = NSRange(location: lineRange.location + fullRange.location, length: fullRange.length)
            if isExcluded(absoluteFull, by: excludedRanges) { continue }
            spans.append(MarkdownHighlightSpan(range: absoluteFull, role: .inlineCode))
        }
        return spans.isEmpty ? nil : spans
    }

    private static func isBacktickAdjacentMatch(_ range: NSRange, in line: String) -> Bool {
        let nsLine = line as NSString
        if range.location > 0, nsLine.character(at: range.location - 1) == unichar(0x60) {
            return true
        }
        let end = range.location + range.length
        if end < nsLine.length, nsLine.character(at: end) == unichar(0x60) {
            return true
        }
        return false
    }

    private static func matchUnderline(in line: String, lineRange: NSRange, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        let nsLine = line as NSString
        let matches = RegexCache.underline.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
        var spans: [MarkdownHighlightSpan] = []

        for match in matches {
            let fullRange = match.range
            let openTagRange = match.range(at: 1)
            let textRange = match.range(at: 2)
            let closeTagRange = match.range(at: 3)

            let absoluteFull = NSRange(location: lineRange.location + fullRange.location, length: fullRange.length)
            if isExcluded(absoluteFull, by: excludedRanges) { continue }

            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + openTagRange.location, length: openTagRange.length),
                role: .emphasisMarker
            ))
            if textRange.length > 0 {
                spans.append(MarkdownHighlightSpan(
                    range: NSRange(location: lineRange.location + textRange.location, length: textRange.length),
                    role: .underlineText
                ))
            }
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + closeTagRange.location, length: closeTagRange.length),
                role: .emphasisMarker
            ))
        }
        return spans.isEmpty ? nil : spans
    }

    private static func matchDelimiter(in line: String, lineRange: NSRange, delimiter: String, role: MarkdownHighlightRole, markerRole: MarkdownHighlightRole, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        let count = delimiter.utf16.count
        var spans: [MarkdownHighlightSpan] = []
        var positions: [Int] = []
        var searchStart = 0
        let nsLine = line as NSString

        while searchStart < nsLine.length {
            let range = nsLine.range(of: delimiter, options: [], range: NSRange(location: searchStart, length: nsLine.length - searchStart))
            if range.location == NSNotFound { break }
            positions.append(range.location)
            searchStart = range.location + count
        }

        var i = 0
        while i < positions.count - 1 {
            let start = positions[i]
            let end = positions[i + 1]
            let contentStart = start + count
            let contentLength = end - contentStart
            let fullRange = NSRange(location: lineRange.location + start, length: end + count - start)
            if isExcluded(fullRange, by: excludedRanges) {
                i += 1
                continue
            }

            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + start, length: count),
                role: markerRole
            ))
            if contentLength > 0 {
                spans.append(MarkdownHighlightSpan(
                    range: NSRange(location: lineRange.location + contentStart, length: contentLength),
                    role: role
                ))
            }
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + end, length: count),
                role: markerRole
            ))
            i += 2
        }
        return spans.isEmpty ? nil : spans
    }

    private static func matchBold(in line: String, lineRange: NSRange, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        var allSpans: [MarkdownHighlightSpan] = []
        if let spans = matchPairedDelimiter(in: line, lineRange: lineRange, delimiter: "**", contentRole: .strongText, excludedRanges: excludedRanges) {
            allSpans.append(contentsOf: spans)
        }
        if let spans = matchPairedDelimiter(in: line, lineRange: lineRange, delimiter: "__", contentRole: .strongText, excludedRanges: excludedRanges) {
            allSpans.append(contentsOf: spans)
        }
        return allSpans.isEmpty ? nil : allSpans
    }

    private static func matchItalic(in line: String, lineRange: NSRange, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        var allSpans: [MarkdownHighlightSpan] = []
        let matches = RegexCache.boldRange.matches(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length))
        let boldRanges = matches.map { $0.range }

        let absoluteBoldRanges = boldRanges.map { NSRange(location: lineRange.location + $0.location, length: $0.length) }

        if let spans = matchSingleEmphasis(in: line, lineRange: lineRange, delimiter: "*", contentRole: .italicText, excludedRanges: excludedRanges + absoluteBoldRanges) {
            allSpans.append(contentsOf: spans)
        }
        if let spans = matchSingleEmphasis(in: line, lineRange: lineRange, delimiter: "_", contentRole: .italicText, excludedRanges: excludedRanges + absoluteBoldRanges) {
            allSpans.append(contentsOf: spans)
        }
        return allSpans.isEmpty ? nil : allSpans
    }

    private static func matchPairedDelimiter(in line: String, lineRange: NSRange, delimiter: String, contentRole: MarkdownHighlightRole, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        let count = delimiter.utf16.count
        var spans: [MarkdownHighlightSpan] = []
        var positions: [Int] = []
        var searchStart = 0
        let nsLine = line as NSString

        while searchStart < nsLine.length {
            let range = nsLine.range(of: delimiter, options: [], range: NSRange(location: searchStart, length: nsLine.length - searchStart))
            if range.location == NSNotFound { break }
            positions.append(range.location)
            searchStart = range.location + count
        }

        var i = 0
        while i < positions.count - 1 {
            let start = positions[i]
            let end = positions[i + 1]
            let contentStart = start + count
            let contentLength = end - contentStart
            guard contentLength > 0 else { i += 1; continue }

            let fullRange = NSRange(location: lineRange.location + start, length: end + count - start)
            if isExcluded(fullRange, by: excludedRanges) { i += 1; continue }

            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + start, length: count),
                role: .emphasisMarker
            ))
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + contentStart, length: contentLength),
                role: contentRole
            ))
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + end, length: count),
                role: .emphasisMarker
            ))
            i += 2
        }
        return spans.isEmpty ? nil : spans
    }

    private static func matchSingleEmphasis(in line: String, lineRange: NSRange, delimiter: String, contentRole: MarkdownHighlightRole, excludedRanges: [NSRange]) -> [MarkdownHighlightSpan]? {
        var spans: [MarkdownHighlightSpan] = []
        var positions: [Int] = []
        var searchStart = 0
        let nsLine = line as NSString

        while searchStart < nsLine.length {
            let range = nsLine.range(of: delimiter, options: [], range: NSRange(location: searchStart, length: nsLine.length - searchStart))
            if range.location == NSNotFound { break }

            if range.location + 1 < nsLine.length {
                let nextTwo = nsLine.substring(with: NSRange(location: range.location, length: min(2, nsLine.length - range.location)))
                if nextTwo.hasPrefix("**") || nextTwo.hasPrefix("__") {
                    searchStart = range.location + 2
                    continue
                }
            }

            positions.append(range.location)
            searchStart = range.location + 1
        }

        var i = 0
        while i < positions.count - 1 {
            let start = positions[i]
            let end = positions[i + 1]
            let contentStart = start + 1
            let contentLength = end - contentStart
            guard contentLength > 0 else { i += 1; continue }

            let fullRange = NSRange(location: lineRange.location + start, length: end + 1 - start)
            if isExcluded(fullRange, by: excludedRanges) { i += 1; continue }

            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + start, length: 1),
                role: .emphasisMarker
            ))
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + contentStart, length: contentLength),
                role: contentRole
            ))
            spans.append(MarkdownHighlightSpan(
                range: NSRange(location: lineRange.location + end, length: 1),
                role: .emphasisMarker
            ))
            i += 2
        }
        return spans.isEmpty ? nil : spans
    }

    private static func isExcluded(_ range: NSRange, by excludedRanges: [NSRange]) -> Bool {
        excludedRanges.contains { NSIntersectionRange(range, $0).length > 0 }
    }

    private static func fullRange(_ nsString: NSString) -> NSRange {
        NSRange(location: 0, length: nsString.length)
    }

    private static func mergedSortedSpans(_ spans: [MarkdownHighlightSpan]) -> [MarkdownHighlightSpan] {
        spans.sorted { $0.range.location < $1.range.location }
    }
}

#if os(macOS)
extension MarkdownHighlighter {
    static func attributes(for role: MarkdownHighlightRole, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let bodyFont = bodyFont(size: fontSize)
        let monoFontValue = monoFont(size: fontSize)

        switch role {
        case .headingMarker:
            return [
                .foregroundColor: NSColor(DS.ai),
                .font: bodyFont
            ]
        case .headingText(let level):
            _ = level
            let headingFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            return [
                .foregroundColor: NSColor(DS.textEmphasize),
                .font: headingFont
            ]
        case .emphasisMarker:
            return [
                .foregroundColor: NSColor(DS.textSubtle),
                .font: bodyFont
            ]
        case .strongText:
            let boldFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            return [
                .foregroundColor: NSColor(DS.textStrong),
                .font: boldFont
            ]
        case .italicText:
            let italicFont: NSFont = {
                let desc = bodyFont.fontDescriptor.withSymbolicTraits(.italic)
                return NSFont(descriptor: desc, size: fontSize) ?? bodyFont
            }()
            return [
                .foregroundColor: NSColor(DS.textBody),
                .font: italicFont
            ]
        case .strikeText:
            return [
                .foregroundColor: NSColor(DS.textSecondary),
                .font: bodyFont,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor(DS.textSubtle)
            ]
        case .underlineText:
            return [
                .foregroundColor: NSColor(DS.textBody),
                .font: bodyFont,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        case .inlineCode:
            return [
                .foregroundColor: NSColor(DS.primaryDeep),
                .font: monoFontValue,
                .backgroundColor: NSColor(DS.surfaceSunken)
            ]
        case .codeFenceMarker:
            return [
                .foregroundColor: NSColor(DS.textSubtle),
                .font: monoFontValue
            ]
        case .codeBlockText:
            return [
                .foregroundColor: NSColor(DS.textBody),
                .font: bodyFont
            ]
        case .listMarker:
            return [
                .foregroundColor: NSColor(DS.primaryDeep),
                .font: bodyFont
            ]
        case .taskMarker:
            return [
                .foregroundColor: NSColor(DS.primaryDeep),
                .font: bodyFont
            ]
        case .quoteMarker:
            return [
                .foregroundColor: NSColor(DS.link),
                .font: bodyFont
            ]
        case .linkText:
            return [
                .foregroundColor: NSColor(DS.link),
                .font: bodyFont
            ]
        case .linkURL:
            return [
                .foregroundColor: NSColor(DS.textSubtle),
                .font: monoFontValue
            ]
        case .imageMarker:
            return [
                .foregroundColor: NSColor(DS.textSubtle),
                .font: bodyFont
            ]
        case .tableDelimiter:
            return [
                .foregroundColor: NSColor(DS.textSubtle),
                .font: bodyFont
            ]
        case .horizontalRule:
            return [
                .foregroundColor: NSColor(DS.line),
                .font: bodyFont
            ]
        case .htmlComment:
            return [
                .foregroundColor: NSColor.systemGreen,
                .font: monoFontValue
            ]
        }
    }

    static func bodyFont(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size)
    }

    static func monoFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func lineHeight(size: CGFloat, multiple: CGFloat = 1.25) -> CGFloat {
        ceil(size * multiple)
    }

    static func paragraphStyle(size: CGFloat, multiple: CGFloat = 1.25) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        let lh = lineHeight(size: size, multiple: multiple)
        paragraphStyle.minimumLineHeight = lh
        paragraphStyle.maximumLineHeight = lh
        paragraphStyle.lineHeightMultiple = 1
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping
        return paragraphStyle
    }

    static func baselineOffset(size: CGFloat, font: NSFont, multiple: CGFloat = 1.25) -> CGFloat {
        let lh = lineHeight(size: size, multiple: multiple)
        let actualFontHeight = font.ascender - font.descender
        let remaining = lh - actualFontHeight
        return max(0, floor(remaining / 2))
    }

    static func textContainerInset(size: CGFloat) -> NSSize {
        let verticalInset = ceil(size * 0.3)
        return NSSize(width: 4, height: verticalInset)
    }

    @MainActor
    static func makeHighlightedAttributedString(text: String, fontSize: CGFloat, lineHeightMultiple: CGFloat = 1.25) -> NSAttributedString {
        let bodyFont = bodyFont(size: fontSize)
        let paraStyle = paragraphStyle(size: fontSize, multiple: lineHeightMultiple)
        let baselineOff = baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)

        let mutable = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        mutable.setAttributes([
            .font: bodyFont,
            .foregroundColor: NSColor(DS.textBody),
            .paragraphStyle: paraStyle,
            .baselineOffset: baselineOff
        ], range: fullRange)

        let spans = highlight(text)
        for span in spans {
            let attrs = attributes(for: span.role, fontSize: fontSize)
            var mergedAttrs = attrs
            if mergedAttrs[.paragraphStyle] == nil {
                mergedAttrs[.paragraphStyle] = paraStyle
            }
            if mergedAttrs[.baselineOffset] == nil {
                mergedAttrs[.baselineOffset] = baselineOff
            }
            mutable.addAttributes(mergedAttrs, range: span.range)
        }
        return mutable
    }
}
#endif

#if os(iOS)
extension MarkdownHighlighter {
    static func makeIOSHighlightedAttributedString(text: String, fontSize: CGFloat, lineHeightMultiple: CGFloat = 1.3) -> NSAttributedString {
        let bodyFont = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple

        let mutable = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        mutable.setAttributes([
            .font: bodyFont,
            .foregroundColor: UIColor(DS.textBody),
            .paragraphStyle: paragraphStyle
        ], range: fullRange)

        let spans = highlight(text)
        for span in spans {
            var attrs = iosAttributes(for: span.role, fontSize: fontSize)
            if attrs[.paragraphStyle] == nil {
                attrs[.paragraphStyle] = paragraphStyle
            }
            mutable.addAttributes(attrs, range: span.range)
        }

        return mutable
    }

    /// Re-highlight only `dirtyRange` in place. Spans are still computed over the FULL
    /// text (so fenced code / tables stay globally correct), but attributes are written
    /// only within the dirty range via `setAttributes`/`addAttributes` — no character
    /// mutation and no `setAttributedString`, so typing stays cheap. (P1-1)
    static func applyIOSHighlighting(
        to textStorage: NSTextStorage,
        text: String,
        dirtyRange: NSRange,
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat = 1.3
    ) {
        let fullLength = (textStorage.string as NSString).length
        let applyRange = NSIntersectionRange(dirtyRange, NSRange(location: 0, length: fullLength))
        guard applyRange.length > 0 else { return }

        let bodyFont = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor(DS.textBody),
            .paragraphStyle: paragraphStyle
        ]

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: applyRange)
        for span in highlight(text) {
            let intersection = NSIntersectionRange(span.range, applyRange)
            guard intersection.length > 0 else { continue }
            var attrs = iosAttributes(for: span.role, fontSize: fontSize)
            if attrs[.paragraphStyle] == nil {
                attrs[.paragraphStyle] = paragraphStyle
            }
            textStorage.addAttributes(attrs, range: intersection)
        }
        textStorage.endEditing()
    }

    static func iosTypingAttributes(fontSize: CGFloat, lineHeightMultiple: CGFloat = 1.3) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        return [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor(DS.textBody),
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func iosAttributes(for role: MarkdownHighlightRole, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let bodyFont = UIFont.systemFont(ofSize: fontSize)
        let monoFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        switch role {
        case .headingMarker:
            return [.foregroundColor: UIColor(DS.ai), .font: bodyFont]
        case .headingText:
            return [.foregroundColor: UIColor(DS.textEmphasize), .font: UIFont.systemFont(ofSize: fontSize, weight: .bold)]
        case .emphasisMarker:
            return [.foregroundColor: UIColor(DS.textSubtle), .font: bodyFont]
        case .strongText:
            return [.foregroundColor: UIColor(DS.textStrong), .font: UIFont.systemFont(ofSize: fontSize, weight: .bold)]
        case .italicText:
            let italicFont = UIFont.italicSystemFont(ofSize: fontSize)
            return [.foregroundColor: UIColor(DS.textBody), .font: italicFont]
        case .strikeText:
            return [
                .foregroundColor: UIColor(DS.textSecondary),
                .font: bodyFont,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: UIColor(DS.textSubtle)
            ]
        case .underlineText:
            return [
                .foregroundColor: UIColor(DS.textBody),
                .font: bodyFont,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        case .inlineCode:
            return [
                .foregroundColor: UIColor(DS.primaryDeep),
                .font: monoFont,
                .backgroundColor: UIColor(DS.surfaceSunken)
            ]
        case .codeFenceMarker:
            return [.foregroundColor: UIColor(DS.textSubtle), .font: monoFont]
        case .codeBlockText:
            return [.foregroundColor: UIColor(DS.textBody), .font: bodyFont]
        case .listMarker, .taskMarker:
            return [.foregroundColor: UIColor(DS.primaryDeep), .font: bodyFont]
        case .quoteMarker, .linkText:
            return [.foregroundColor: UIColor(DS.link), .font: bodyFont]
        case .linkURL:
            return [.foregroundColor: UIColor(DS.textSubtle), .font: monoFont]
        case .imageMarker, .tableDelimiter:
            return [.foregroundColor: UIColor(DS.textSubtle), .font: bodyFont]
        case .horizontalRule:
            return [.foregroundColor: UIColor(DS.line), .font: bodyFont]
        case .htmlComment:
            return [.foregroundColor: UIColor.systemGreen, .font: monoFont]
        }
    }
}
#endif
