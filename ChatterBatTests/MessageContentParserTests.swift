import XCTest
@testable import ChatterBat

final class MessageContentParserTests: XCTestCase {
    func testEmptyContentProducesNoBlocks() {
        XCTAssertEqual(MessageContentParser.parse(""), [])
    }

    func testPlainTextWithNoFenceIsOneTextBlock() {
        let blocks = MessageContentParser.parse("Hello, how are you?")
        XCTAssertEqual(blocks, [.text("Hello, how are you?")])
    }

    func testSingleFencedCodeBlockWithLanguage() {
        let content = "```swift\nlet x = 1\n```"
        let blocks = MessageContentParser.parse(content)
        XCTAssertEqual(blocks, [.code(language: "swift", content: "let x = 1")])
    }

    func testFencedCodeBlockWithoutLanguageTag() {
        let content = "```\nplain code\n```"
        let blocks = MessageContentParser.parse(content)
        XCTAssertEqual(blocks, [.code(language: nil, content: "plain code")])
    }

    func testTextBeforeAndAfterCodeBlock() {
        let content = "Here is code:\n```python\nprint(1)\n```\nDone."
        let blocks = MessageContentParser.parse(content)
        XCTAssertEqual(blocks, [
            .text("Here is code:"),
            .code(language: "python", content: "print(1)"),
            .text("Done.")
        ])
    }

    func testMultipleCodeBlocksAreEachSeparateBlocks() {
        let content = "```a\n1\n```\ntext\n```b\n2\n```"
        let blocks = MessageContentParser.parse(content)
        XCTAssertEqual(blocks, [
            .code(language: "a", content: "1"),
            .text("text"),
            .code(language: "b", content: "2")
        ])
    }

    func testUnterminatedFenceDuringStreamingIsTreatedAsCodeNotLost() {
        // Simulates a still-streaming message whose content ends mid
        // code-block — must not crash and must not silently drop the
        // partial code content.
        let content = "Here:\n```swift\nlet partial = "
        let blocks = MessageContentParser.parse(content)
        XCTAssertEqual(blocks, [
            .text("Here:"),
            .code(language: "swift", content: "let partial = ")
        ])
    }

    func testEmptyCodeBlockProducesCodeBlockWithEmptyContent() {
        let content = "```swift\n```"
        let blocks = MessageContentParser.parse(content)
        XCTAssertEqual(blocks, [.code(language: "swift", content: "")])
    }

    func testWhitespaceOnlyTextBetweenFencesIsDropped() {
        let content = "```a\n1\n```\n   \n```b\n2\n```"
        let blocks = MessageContentParser.parse(content)
        XCTAssertEqual(blocks, [
            .code(language: "a", content: "1"),
            .code(language: "b", content: "2")
        ])
    }

    func testLeadingWhitespaceFenceIsStillRecognized() {
        // A fence indented with spaces (e.g. inside a numbered list) is
        // still recognized after trimming.
        let content = "  ```swift\n  code\n  ```"
        let blocks = MessageContentParser.parse(content)
        XCTAssertEqual(blocks, [.code(language: "swift", content: "  code")])
    }

    func testTripleBacktickInsideRunningTextWithoutNewlineIsNotSpecialCased() {
        // A degenerate case: three backticks appear but the parser only
        // recognizes them as fence markers when they start a line after
        // trimming — this is a deliberate, documented limitation of the
        // "deliberate subset," not a full inline-code-span parser.
        let content = "Use ``` carefully"
        let blocks = MessageContentParser.parse(content)
        // The line still starts with the fence after trimming leading
        // "Use " is not trimmed away, so this is NOT treated as a fence
        // (the line doesn't start with backticks even after trimming
        // whitespace) — it remains plain text.
        XCTAssertEqual(blocks, [.text("Use ``` carefully")])
    }
}
