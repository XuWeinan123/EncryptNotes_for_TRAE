import XCTest
@testable import EncryptNotes

final class MacMarkdownFormatterTests: XCTestCase {

    // MARK: - Empty selection: insert placeholder

    func testBoldEmptySelectionInsertsPlaceholder() {
        let result = MacMarkdownFormatter.apply(
            command: .bold,
            to: "",
            selection: NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(result.text, "**strong**")
        XCTAssertEqual(result.selection, NSRange(location: 2, length: 6))
    }

    func testItalicEmptySelectionInsertsPlaceholder() {
        let result = MacMarkdownFormatter.apply(
            command: .italic,
            to: "hello",
            selection: NSRange(location: 5, length: 0)
        )
        XCTAssertEqual(result.text, "hello*emphasis*")
        XCTAssertEqual(result.selection, NSRange(location: 6, length: 8))
    }

    func testUnderlineEmptySelectionInsertsPlaceholder() {
        let result = MacMarkdownFormatter.apply(command: .underline, to: "", selection: .init(location: 0, length: 0))
        XCTAssertEqual(result.text, "<u>underline</u>")
        XCTAssertEqual(result.selection, NSRange(location: 3, length: 9))
    }

    func testInlineCodeEmptySelectionInsertsPlaceholder() {
        let result = MacMarkdownFormatter.apply(command: .inlineCode, to: "", selection: .init(location: 0, length: 0))
        XCTAssertEqual(result.text, "`code`")
        XCTAssertEqual(result.selection, NSRange(location: 1, length: 4))
    }

    func testInlineMathEmptySelectionInsertsPlaceholder() {
        let result = MacMarkdownFormatter.apply(command: .inlineMath, to: "", selection: .init(location: 0, length: 0))
        XCTAssertEqual(result.text, "$math$")
        XCTAssertEqual(result.selection, NSRange(location: 1, length: 4))
    }

    func testStrikeEmptySelectionInsertsPlaceholder() {
        let result = MacMarkdownFormatter.apply(command: .strike, to: "", selection: .init(location: 0, length: 0))
        XCTAssertEqual(result.text, "~~strike~~")
        XCTAssertEqual(result.selection, NSRange(location: 2, length: 6))
    }

    func testHTMLCommentEmptySelectionInsertsPlaceholder() {
        let result = MacMarkdownFormatter.apply(command: .htmlComment, to: "", selection: .init(location: 0, length: 0))
        XCTAssertEqual(result.text, "<!-- comment -->")
        XCTAssertEqual(result.selection, NSRange(location: 5, length: 7))
    }

    func testLinkEmptySelectionPlacesCursorInBrackets() {
        let result = MacMarkdownFormatter.apply(command: .link, to: "", selection: .init(location: 0, length: 0))
        XCTAssertEqual(result.text, "[]()")
        XCTAssertEqual(result.selection, NSRange(location: 1, length: 0))
    }

    // MARK: - With selection: wrap text

    func testBoldWrapsSelection() {
        let text = "hello world"
        let result = MacMarkdownFormatter.apply(
            command: .bold,
            to: text,
            selection: NSRange(location: 6, length: 5)
        )
        XCTAssertEqual(result.text, "hello **world**")
        XCTAssertEqual(result.selection, NSRange(location: 8, length: 5))
    }

    func testLinkWrapsSelection() {
        let result = MacMarkdownFormatter.apply(
            command: .link,
            to: "click here",
            selection: NSRange(location: 6, length: 4)
        )
        XCTAssertEqual(result.text, "click [here]()")
        XCTAssertEqual(result.selection, NSRange(location: 13, length: 0))
    }

    // MARK: - Toggle removal

    func testBoldToggleRemovesMarkerWhenAlreadyWrapped() {
        let text = "**hello**"
        let result = MacMarkdownFormatter.apply(
            command: .bold,
            to: text,
            selection: NSRange(location: 2, length: 5)
        )
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 5))
    }

    func testItalicToggleRemovesMarker() {
        let text = "*hi*"
        let result = MacMarkdownFormatter.apply(
            command: .italic,
            to: text,
            selection: NSRange(location: 1, length: 2)
        )
        XCTAssertEqual(result.text, "hi")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 2))
    }

    func testInlineCodeToggleRemovesBackticks() {
        let text = "`code`"
        let result = MacMarkdownFormatter.apply(
            command: .inlineCode,
            to: text,
            selection: NSRange(location: 1, length: 4)
        )
        XCTAssertEqual(result.text, "code")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 4))
    }

    func testStrikeToggleRemovesMarker() {
        let text = "~~strike~~"
        let result = MacMarkdownFormatter.apply(
            command: .strike,
            to: text,
            selection: NSRange(location: 2, length: 6)
        )
        XCTAssertEqual(result.text, "strike")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 6))
    }

    func testCommentToggleRemovesMarker() {
        let text = "<!-- hello -->"
        let result = MacMarkdownFormatter.apply(
            command: .htmlComment,
            to: text,
            selection: NSRange(location: 5, length: 5)
        )
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 5))
    }
}
