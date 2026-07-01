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

    func testInlineMathWrapsSelection() {
        let result = MacMarkdownFormatter.apply(
            command: .inlineMath,
            to: "use x",
            selection: NSRange(location: 4, length: 1)
        )
        XCTAssertEqual(result.text, "use $x$")
        XCTAssertEqual(result.selection, NSRange(location: 5, length: 1))
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

    func testInlineMathToggleRemovesDollarMarkers() {
        let text = "$math$"
        let result = MacMarkdownFormatter.apply(
            command: .inlineMath,
            to: text,
            selection: NSRange(location: 1, length: 4)
        )
        XCTAssertEqual(result.text, "math")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 4))
    }

    func testUnderlineToggleRemovesTags() {
        let text = "<u>under</u>"
        let result = MacMarkdownFormatter.apply(
            command: .underline,
            to: text,
            selection: NSRange(location: 3, length: 5)
        )
        XCTAssertEqual(result.text, "under")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 5))
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

    // MARK: - List continuation

    func testNumberedListReturnContinuesWithNextNumber() {
        let text = "1. hello"
        let result = MacMarkdownFormatter.continueListIfNeeded(
            in: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        XCTAssertEqual(result?.text, "1. hello\n2. ")
        XCTAssertEqual(result?.selection, NSRange(location: 12, length: 0))
    }

    func testBulletListReturnContinuesSameMarker() {
        let text = "- hello"
        let result = MacMarkdownFormatter.continueListIfNeeded(
            in: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        XCTAssertEqual(result?.text, "- hello\n- ")
    }

    func testEmptyGeneratedListMarkerExitsList() {
        let text = "1. hello\n2. "
        let result = MacMarkdownFormatter.continueListIfNeeded(
            in: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        XCTAssertEqual(result?.text, "1. hello\n")
        XCTAssertEqual(result?.selection, NSRange(location: 9, length: 0))
    }

    func testListContinuationSkipsFencedCodeBlocks() {
        let text = "```\n1. code"
        let result = MacMarkdownFormatter.continueListIfNeeded(
            in: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        XCTAssertNil(result)
    }

    // MARK: - Code fence completion

    func testCodeFenceCompletionInsertsClosingFenceAndPlacesCursorInside() {
        let text = "```swift"
        let result = MacMarkdownFormatter.completeCodeFenceIfNeeded(
            in: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        XCTAssertEqual(result?.text, "```swift\n\n```")
        XCTAssertEqual(result?.selection, NSRange(location: 9, length: 0))
    }

    func testCodeFenceCompletionHandlesPlainFence() {
        let text = "```"
        let result = MacMarkdownFormatter.completeCodeFenceIfNeeded(
            in: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        XCTAssertEqual(result?.text, "```\n\n```")
        XCTAssertEqual(result?.selection, NSRange(location: 4, length: 0))
    }

    func testCodeFenceCompletionIgnoresFenceWithInlineContent() {
        let text = "```内容"
        let result = MacMarkdownFormatter.completeCodeFenceIfNeeded(
            in: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        XCTAssertNil(result)
    }

    // MARK: - Copy spacing

    func testCopySpacingAddsBlankLinesBetweenParagraphLines() {
        let text = "第一段\n第二段\n\n- item\n- item2\n\n```swift\nlet x = 1\nlet y = 2\n```"
        let result = MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: text)
        XCTAssertEqual(result, "第一段\n\n第二段\n\n- item\n- item2\n\n```swift\nlet x = 1\nlet y = 2\n```\n")
    }

    func testCopySpacingMatchesPRDSample() {
        let text = """
        # Seal Note 更新需求 0701
        1. 取消代码块的背景。高亮语法仅针对“```markdown”和"```"结束部分
        2. 增加三个快捷键，command+control+1、command+control+2、command+control+3 打开最近 x 项的笔记，并在 menu 中增加快捷键提示
        ## 需求补充
        1. 新一行起始输入 ```{代码类型} 这样的代码块起始标志后，点击回车，应该自动在后一行补上代码块结束标识```
        ---
        4. 编辑的时候似乎窗口还是会跳动，即使不是编辑新起了一行。
        5. 新建笔记时，笔记窗口会记住上次的大小——记住上次新建笔记时调整的窗口大小，如果是编辑旧笔记，则不需要记录。
        ## 昨天遗留的需求
        **需求 7**：设置页增加 AI 标题模块支持开启 AI 标题
        用户输入 DeepSeek / Gemini API Key，选择服务，自定义 Prompt；关闭 Editor 后调用 AI 总结标题，只影响 menu 和 iCloud 文件名显示，不改正文；可开启“标题例外”，若第一行是 # 标题 则跳过 AI。
        """
        let result = MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: text)
        XCTAssertEqual(result, """
        # Seal Note 更新需求 0701

        1. 取消代码块的背景。高亮语法仅针对“```markdown”和"```"结束部分
        2. 增加三个快捷键，command+control+1、command+control+2、command+control+3 打开最近 x 项的笔记，并在 menu 中增加快捷键提示

        ## 需求补充

        1. 新一行起始输入 ```{代码类型} 这样的代码块起始标志后，点击回车，应该自动在后一行补上代码块结束标识```

        ---

        4. 编辑的时候似乎窗口还是会跳动，即使不是编辑新起了一行。
        5. 新建笔记时，笔记窗口会记住上次的大小——记住上次新建笔记时调整的窗口大小，如果是编辑旧笔记，则不需要记录。

        ## 昨天遗留的需求

        **需求 7**：设置页增加 AI 标题模块支持开启 AI 标题

        用户输入 DeepSeek / Gemini API Key，选择服务，自定义 Prompt；关闭 Editor 后调用 AI 总结标题，只影响 menu 和 iCloud 文件名显示，不改正文；可开启“标题例外”，若第一行是 # 标题 则跳过 AI。

        """)
    }

    func testCopySpacingHandlesMarkdownBlocksWithoutInternalBlankLines() {
        let text = """
        正文
        # 标题
        正文
        > quote 1
        > quote 2
        | 功能 | 状态 |
        | --- | --- |
        | A | Done |
        正文
        ```swift
        let a = 1

        let b = 2
        ```
        正文
        """
        let result = MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: text)
        XCTAssertEqual(result, """
        正文

        # 标题

        正文

        > quote 1
        > quote 2

        | 功能 | 状态 |
        | --- | --- |
        | A | Done |

        正文

        ```swift
        let a = 1

        let b = 2
        ```

        正文

        """)
    }

    func testCopySpacingPreservesNestedListsAndListNumberingAcrossRule() {
        let text = """
        正文
        1. 第一项
            1. 子项
            - 子弹
        2. 第二项
        ---
        4. 第四项
        """
        let result = MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: text)
        XCTAssertEqual(result, """
        正文

        1. 第一项
            1. 子项
            - 子弹
        2. 第二项

        ---

        4. 第四项

        """)
    }

    func testCopySpacingDoesNotTreatInlineTripleBackticksAsFence() {
        let text = "注意到 ```内容``` 这种格式会被错误识别。\n下一句"
        let result = MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: text)
        XCTAssertEqual(result, "注意到 ```内容``` 这种格式会被错误识别。\n\n下一句\n")
    }

    func testCopySpacingCompressesBlankLinesAndTrimsLeadingBlanks() {
        let text = "\n\n第一段\n\n\n第二段\n\n"
        let result = MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: text)
        XCTAssertEqual(result, "第一段\n\n第二段\n")
    }

    func testCopySpacingReturnsEmptyStringForBlankInput() {
        XCTAssertEqual(MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: ""), "")
        XCTAssertEqual(MacMarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: "\n \n\t\n"), "")
    }
}
