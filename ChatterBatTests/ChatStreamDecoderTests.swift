import XCTest
@testable import ChatterBat

final class ChatStreamDecoderTests: XCTestCase {
    func testDoneSentinelReturnsNil() {
        XCTAssertNil(ChatStreamDecoder.decode("[DONE]"))
    }

    func testInvalidJSONReturnsNilRatherThanCrashing() {
        XCTAssertNil(ChatStreamDecoder.decode("not json at all"))
    }

    func testContentDeltaIsExtracted() {
        let payload = #"{"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}"#
        XCTAssertEqual(ChatStreamDecoder.decode(payload), .contentDelta("Hello"))
    }

    func testEmptyContentDeltaIsIgnorableNotADelta() {
        let payload = #"{"choices":[{"index":0,"delta":{"content":""},"finish_reason":null}]}"#
        XCTAssertEqual(ChatStreamDecoder.decode(payload), .ignorable)
    }

    func testFinishReasonIsExtractedWhenNoContent() {
        let payload = #"{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#
        XCTAssertEqual(ChatStreamDecoder.decode(payload), .finished(reason: "stop"))
    }

    func testUsageOnlyFrameWithEmptyChoicesIsExtracted() {
        let payload = #"{"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#
        XCTAssertEqual(
            ChatStreamDecoder.decode(payload),
            .usage(ChatUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15))
        )
    }

    func testMidStreamErrorInsideHTTP200IsDetected() {
        // Exact shape from https://openrouter.ai/docs/api-reference/streaming
        let payload = #"""
        {"id":"cmpl-abc123","object":"chat.completion.chunk","created":1234567890,"model":"openai/gpt-4o","provider":"openai","error":{"code":"server_error","message":"Provider disconnected unexpectedly"},"choices":[{"index":0,"delta":{"content":""},"finish_reason":"error"}]}
        """#
        XCTAssertEqual(ChatStreamDecoder.decode(payload), .streamError("Provider disconnected unexpectedly"))
    }

    func testMissingOptionalFieldsDoNotCrash() {
        let payload = #"{"choices":[{}]}"#
        XCTAssertEqual(ChatStreamDecoder.decode(payload), .ignorable)
    }

    func testContentTakesPrecedenceOverFinishReasonInSameChunk() {
        let payload = #"{"choices":[{"delta":{"content":"tail"},"finish_reason":"stop"}]}"#
        XCTAssertEqual(ChatStreamDecoder.decode(payload), .contentDelta("tail"))
    }

    func testMalformedErrorObjectStillReportsStreamErrorWithFallbackMessage() {
        let payload = #"{"error":{"code":"x"},"choices":[{"finish_reason":"error"}]}"#
        XCTAssertEqual(ChatStreamDecoder.decode(payload), .streamError("The provider reported a stream error."))
    }

    func testVeniceCostUSDIsExtractedAlongsideUsage() {
        let payload = #"{"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15},"cost":{"usd":0.00042,"diem":0}}"#
        XCTAssertEqual(
            ChatStreamDecoder.decode(payload),
            .usage(ChatUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15, costUSD: Decimal(string: "0.00042"), costCredits: nil))
        )
    }

    func testOpenRouterCostCreditsIsExtractedAlongsideUsageAndNeverTreatedAsUSD() {
        let payload = #"{"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15,"cost":0.95}}"#
        let decoded = ChatStreamDecoder.decode(payload)
        XCTAssertEqual(
            decoded,
            .usage(ChatUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15, costUSD: nil, costCredits: Decimal(string: "0.95")))
        )
        guard case .usage(let usage) = decoded else { return XCTFail("Expected .usage") }
        XCTAssertNil(usage.costUSD)
    }

    func testMissingCostFieldsLeaveBothCostFieldsNil() {
        let payload = #"{"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#
        guard case .usage(let usage) = ChatStreamDecoder.decode(payload) else { return XCTFail("Expected .usage") }
        XCTAssertNil(usage.costUSD)
        XCTAssertNil(usage.costCredits)
    }
}
