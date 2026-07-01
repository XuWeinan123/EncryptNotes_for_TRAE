import XCTest
@testable import EncryptNotes
#if os(macOS)
import AppKit
#endif

final class MacMarkdownHighlighterTests: XCTestCase {

    // Helpers

    private func spans(_ text: String) -> [MarkdownHighlightSpan] {
        MacMarkdownHighlighter.highlight(text)
    }

    private func hasRole(_ role: MarkdownHighlightRole, in spans: [MarkdownHighlightSpan], text: String, substring: String) -> Bool {
        let nsText = text as NSString
        let range = nsText.range(of: substring)
        guard range.location != NSNotFound else {
            return false
        }
        return spans.contains { span in
            span.role == role && NSIntersectionRange(span.range, range).length > 0
        }
    }

    private func firstSpan(with role: MarkdownHighlightRole, in spans: [MarkdownHighlightSpan], forText text: String, matching substring: String) -> MarkdownHighlightSpan? {
        let nsText = text as NSString
        let targetRange = nsText.range(of: substring)
        guard targetRange.location != NSNotFound else { return nil }
        return spans.first { span in
            span.role == role && span.range.location <= targetRange.location && span.range.location + span.range.length >= targetRange.location + targetRange.length
        }
    }

    // MARK: - Headings

    func testHeadingRoles() {
        let text = "# H1\n## H2\n### H3\n"
        let s = spans(text)
        XCTAssertTrue(hasRole(.headingMarker, in: s, text: text, substring: "# "))
        XCTAssertTrue(hasRole(.headingMarker, in: s, text: text, substring: "## "))
        XCTAssertTrue(hasRole(.headingMarker, in: s, text: text, substring: "### "))
        XCTAssertTrue(hasRole(.headingText(level: 1), in: s, text: text, substring: "H1"))
        XCTAssertTrue(hasRole(.headingText(level: 2), in: s, text: text, substring: "H2"))
        XCTAssertTrue(hasRole(.headingText(level: 3), in: s, text: text, substring: "H3"))
    }

    // MARK: - Code fence

    func testCodeFenceMarkersAndContent() {
        let text = "```markdown\nlet x = 1\n```\n"
        let s = spans(text)
        let nsText = text as NSString
        let openFenceRange = nsText.range(of: "```markdown")
        let closeFenceLoc = nsText.range(of: "```", options: .backwards).location

        XCTAssertTrue(s.contains { $0.role == .codeFenceMarker && $0.range.location == openFenceRange.location })
        XCTAssertTrue(s.contains { $0.role == .codeFenceMarker && $0.range.location == closeFenceLoc })
        XCTAssertFalse(s.contains { $0.role == .codeBlockText })
    }

    func testPlainCodeFenceOpeningMarkerIsNotHighlighted() {
        let text = "```\nlet x = 1\n```\n"
        let s = spans(text)
        let nsText = text as NSString
        let openFenceLoc = nsText.range(of: "```").location
        let closeFenceLoc = nsText.range(of: "```", options: .backwards).location

        XCTAssertFalse(s.contains { $0.role == .codeFenceMarker && $0.range.location == openFenceLoc })
        XCTAssertTrue(s.contains { $0.role == .codeFenceMarker && $0.range.location == closeFenceLoc })
    }

    func testMultipleMarkdownFenceOpeningsAreHighlighted() {
        let text = "```markdown\nfirst\n```\n\n```markdown\nsecond\n```\n"
        let s = spans(text)
        let nsText = text as NSString
        let firstOpening = nsText.range(of: "```markdown").location
        let secondOpening = nsText.range(of: "```markdown", options: [], range: NSRange(location: firstOpening + 1, length: nsText.length - firstOpening - 1)).location

        XCTAssertTrue(s.contains { $0.role == .codeFenceMarker && $0.range.location == firstOpening })
        XCTAssertTrue(s.contains { $0.role == .codeFenceMarker && $0.range.location == secondOpening })
    }

    func testInlineCodeRecognized() {
        let text = "use `foo` here"
        let s = spans(text)
        XCTAssertTrue(hasRole(.inlineCode, in: s, text: text, substring: "`foo`"))
    }

    func testTripleBackticksOnSingleLineArePlainText() {
        let text = "before ```内容``` after"
        let s = spans(text)
        XCTAssertFalse(s.contains { $0.role == .inlineCode })
        XCTAssertFalse(s.contains { $0.role == .codeFenceMarker })
        XCTAssertFalse(s.contains { $0.role == .codeBlockText })
    }

    // MARK: - Emphasis

    func testBoldAndItalicDistinct() {
        let text = "**bold** and *italic*"
        let s = spans(text)
        XCTAssertTrue(hasRole(.strongText, in: s, text: text, substring: "bold"))
        XCTAssertTrue(hasRole(.italicText, in: s, text: text, substring: "italic"))
        let emMarkers = s.filter {
            if case .emphasisMarker = $0.role { return true }
            return false
        }
        XCTAssertFalse(emMarkers.isEmpty)
    }

    func testBoldMarkerNotSwallowedInItalic() {
        let text = "a **b** c"
        let s = spans(text)
        let nsText = text as NSString
        let boldTextRange = nsText.range(of: "b")
        let boldSpan = s.first {
            if case .strongText = $0.role { return $0.range == boldTextRange }
            return false
        }
        XCTAssertNotNil(boldSpan)
    }

    // MARK: - Strikethrough

    func testStrikethrough() {
        let text = "~~gone~~"
        let s = spans(text)
        XCTAssertTrue(hasRole(.strikeText, in: s, text: text, substring: "gone"))
    }

    // MARK: - Underline

    func testUnderlineHTMLTag() {
        let text = "<u>underlined</u>"
        let s = spans(text)
        XCTAssertTrue(hasRole(.underlineText, in: s, text: text, substring: "underlined"))
    }

    // MARK: - Links and images

    func testLinkTextAndURL() {
        let text = "[click](https://example.com)"
        let s = spans(text)
        XCTAssertTrue(hasRole(.linkText, in: s, text: text, substring: "click"))
        XCTAssertTrue(hasRole(.linkURL, in: s, text: text, substring: "https://example.com"))
    }

    func testImageMarked() {
        let text = "![alt](url.png)"
        let s = spans(text)
        XCTAssertTrue(s.contains {
            if case .imageMarker = $0.role { return true }
            return false
        })
        XCTAssertTrue(hasRole(.linkText, in: s, text: text, substring: "alt"))
    }

    #if os(macOS)
    func testHeadingHighlightDoesNotChangePointSize() {
        let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: "### 标题", fontSize: 14)
        let font = attributed.attribute(.font, at: 4, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }

    func testInlineCodeHighlightDoesNotChangePointSize() {
        let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: "`code`", fontSize: 14)
        let font = attributed.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }

    func testCodeBlockContentHasNoBackground() {
        let text = "```markdown\nlet x = 1\n```\n"
        let attributed = MacMarkdownHighlighter.makeHighlightedAttributedString(text: text, fontSize: 14)
        let contentIndex = (text as NSString).range(of: "let x = 1").location
        XCTAssertNil(attributed.attribute(.backgroundColor, at: contentIndex, effectiveRange: nil))
    }

    func testParagraphLineHeightUsesMultiplier() {
        let style = MacMarkdownHighlighter.paragraphStyle(size: 14, multiple: 1.5)
        XCTAssertEqual(style.minimumLineHeight, ceil(14 * 1.5))
        XCTAssertEqual(style.maximumLineHeight, ceil(14 * 1.5))
    }
    #endif

    // MARK: - Lists

    func testUnorderedListMarker() {
        let text = "- item\n* item2\n+ item3\n"
        let s = spans(text)
        let markers = s.compactMap { span -> String? in
            if case .listMarker = span.role {
                return (text as NSString).substring(with: span.range)
            }
            return nil
        }
        XCTAssertEqual(markers.count, 3)
    }

    func testOrderedListMarker() {
        let text = "1. first\n2. second\n"
        let s = spans(text)
        XCTAssertTrue(s.contains {
            if case .listMarker = $0.role { return true }
            return false
        })
    }

    func testTaskMarker() {
        let text = "- [ ] todo\n- [x] done\n"
        let s = spans(text)
        XCTAssertTrue(s.contains {
            if case .taskMarker = $0.role { return true }
            return false
        })
    }

    // MARK: - Quote

    func testQuoteMarker() {
        let text = "> quoted"
        let s = spans(text)
        XCTAssertTrue(s.contains {
            if case .quoteMarker = $0.role { return true }
            return false
        })
    }

    // MARK: - Horizontal rule

    func testHorizontalRule() {
        let text = "---"
        let s = spans(text)
        XCTAssertTrue(s.contains {
            if case .horizontalRule = $0.role { return true }
            return false
        })
    }

    // MARK: - HTML comment

    func testHTMLComment() {
        let text = "<!-- hello -->"
        let s = spans(text)
        XCTAssertTrue(s.contains {
            if case .htmlComment = $0.role { return true }
            return false
        })
    }

    // MARK: - Table

    func testTableDelimiters() {
        let text = "| a | b |\n| --- | --- |\n| 1 | 2 |\n"
        let s = spans(text)
        let pipeCount = s.filter {
            if case .tableDelimiter = $0.role { return true }
            return false
        }.count
        XCTAssertGreaterThanOrEqual(pipeCount, 6)
    }

    // MARK: - Double equals is plain text

    func testDoubleEqualsNotHighlighted() {
        let text = "==x=="
        let s = spans(text)
        let specialRoles = s.filter { span in
            switch span.role {
            case .strongText, .italicText, .strikeText, .underlineText, .inlineCode,
                 .headingText, .linkText, .codeBlockText, .htmlComment:
                return true
            default:
                return false
            }
        }
        XCTAssertTrue(specialRoles.isEmpty, "==x== should not produce special roles, got \(specialRoles)")
    }
}
