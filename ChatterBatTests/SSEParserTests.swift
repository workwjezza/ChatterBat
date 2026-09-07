import XCTest
@testable import ChatterBat

final class SSEParserTests: XCTestCase {
    func testSingleCompleteEventWithLF() {
        var parser = SSEParser()
        let events = parser.feed(Data("data: hello\n\n".utf8))
        XCTAssertEqual(events, [SSEEvent(data: "hello")])
    }

    func testSingleCompleteEventWithCRLF() {
        var parser = SSEParser()
        let events = parser.feed(Data("data: hello\r\n\r\n".utf8))
        XCTAssertEqual(events, [SSEEvent(data: "hello")])
    }

    func testEventFragmentedAcrossMultipleFeeds() {
        var parser = SSEParser()
        XCTAssertTrue(parser.feed(Data("data: hel".utf8)).isEmpty)
        XCTAssertTrue(parser.feed(Data("lo\n".utf8)).isEmpty)
        let events = parser.feed(Data("\n".utf8))
        XCTAssertEqual(events, [SSEEvent(data: "hello")])
    }

    func testMultiByteUTF8CharacterSplitAcrossFeedsDecodesCorrectly() {
        // "café" — the é is a 2-byte UTF-8 sequence (0xC3 0xA9). Split the
        // raw bytes so the second byte of é arrives in a separate feed.
        var parser = SSEParser()
        let fullLine = Data("data: café\n\n".utf8)
        let splitPoint = fullLine.firstIndex(of: 0xC3)! + 1 // right after the first byte of é
        let firstChunk = fullLine[fullLine.startIndex..<splitPoint]
        let secondChunk = fullLine[splitPoint...]

        XCTAssertTrue(parser.feed(Data(firstChunk)).isEmpty)
        let events = parser.feed(Data(secondChunk))

        XCTAssertEqual(events, [SSEEvent(data: "café")])
    }

    func testMultipleDataLinesInOneEventAreJoinedWithNewline() {
        var parser = SSEParser()
        let events = parser.feed(Data("data: line one\ndata: line two\n\n".utf8))
        XCTAssertEqual(events, [SSEEvent(data: "line one\nline two")])
    }

    func testCommentLinesAreSkipped() {
        var parser = SSEParser()
        let events = parser.feed(Data(": OPENROUTER PROCESSING\ndata: hello\n\n".utf8))
        XCTAssertEqual(events, [SSEEvent(data: "hello")])
    }

    func testCommentOnlyFeedProducesNoEvent() {
        var parser = SSEParser()
        let events = parser.feed(Data(": keep-alive\n".utf8))
        XCTAssertTrue(events.isEmpty)
    }

    func testMultipleEventsInOneFeedAreAllReturned() {
        var parser = SSEParser()
        let events = parser.feed(Data("data: one\n\ndata: two\n\n".utf8))
        XCTAssertEqual(events, [SSEEvent(data: "one"), SSEEvent(data: "two")])
    }

    func testBlankLineWithNoPriorDataLinesProducesNoEvent() {
        var parser = SSEParser()
        let events = parser.feed(Data("\n\n".utf8))
        XCTAssertTrue(events.isEmpty)
    }

    func testDataPrefixWithoutSpaceIsHandled() {
        // Per SSE spec, a single leading space after the colon is
        // stripped, but "data:foo" (no space) is also valid and should
        // decode to "foo".
        var parser = SSEParser()
        let events = parser.feed(Data("data:foo\n\n".utf8))
        XCTAssertEqual(events, [SSEEvent(data: "foo")])
    }

    func testOtherSSEFieldsDoNotBreakParsing() {
        var parser = SSEParser()
        let events = parser.feed(Data("id: 123\nevent: message\ndata: hello\n\n".utf8))
        XCTAssertEqual(events, [SSEEvent(data: "hello")])
    }

    func testEmptyDataLineIsPreservedAsEmptyString() {
        var parser = SSEParser()
        let events = parser.feed(Data("data:\n\n".utf8))
        XCTAssertEqual(events, [SSEEvent(data: "")])
    }
}
