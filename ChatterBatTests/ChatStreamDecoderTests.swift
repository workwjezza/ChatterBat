import XCTest
@testable import ChatterBat

final class ChatStreamDecoderTests: XCTestCase {
    func testCombinedFramePreservesContentFinishAndAccounting() {
        let payload = #"{"choices":[{"delta":{"content":"tail"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1740,"completion_tokens":111,"total_tokens":1851},"cost":{"usd":0.0103275}}"#
        XCTAssertEqual(ChatStreamDecoder.decodeEvents(payload), [
            .contentDelta("tail"), .finished(reason: "stop"),
            .usage(ChatUsage(promptTokens: 1740, completionTokens: 111, totalTokens: 1851, costUSD: Decimal(string: "0.0103275")))
        ])
    }

    func testCostOnlyFrameAndUsageSnapshotsMergeWithoutDoubleCounting() {
        let initial = ChatUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15)
        let payload = #"{"choices":[],"cost":{"usd":0.01}}"#
        guard case .usage(let cost) = ChatStreamDecoder.decodeEvents(payload).first else {
            return XCTFail("Expected cost event")
        }
        let merged = initial.merging(cost).merging(initial)
        XCTAssertEqual(merged.totalTokens, 15)
        XCTAssertEqual(merged.costUSD, Decimal(string: "0.01"))
    }

    func testToolCallAndUsageInSameFrameAreBothPreserved() {
        let payload = #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"x","function":{"name":"read_file","arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":20}}"#
        XCTAssertEqual(ChatStreamDecoder.decodeEvents(payload), [
            .toolCallDelta(index: 0, id: "x", name: "read_file", argumentsFragment: "{}"),
            .finished(reason: "tool_calls"),
            .usage(ChatUsage(promptTokens: 20, completionTokens: nil, totalTokens: nil))
        ])
    }

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

    // MARK: - Stage 7: tool call deltas

    func testFirstToolCallChunkExtractsIdNameAndArgumentsFragment() {
        let payload = #"""
        {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{\"rea"}}]},"finish_reason":null}]}
        """#
        XCTAssertEqual(
            ChatStreamDecoder.decode(payload),
            .toolCallDelta(index: 0, id: "call_1", name: "read_file", argumentsFragment: "{\"rea")
        )
    }

    func testSubsequentToolCallChunkOmitsIdAndNameButCarriesArgumentsFragment() {
        let payload = #"""
        {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"son\": \"x\"}"}}]},"finish_reason":null}]}
        """#
        XCTAssertEqual(
            ChatStreamDecoder.decode(payload),
            .toolCallDelta(index: 0, id: nil, name: nil, argumentsFragment: "son\": \"x\"}")
        )
    }

    func testToolCallDeltaTakesPrecedenceOverFinishReasonInSameChunk() {
        let payload = #"""
        {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"list_directory","arguments":""}}]},"finish_reason":"tool_calls"}]}
        """#
        XCTAssertEqual(
            ChatStreamDecoder.decode(payload),
            .toolCallDelta(index: 0, id: "call_1", name: "list_directory", argumentsFragment: "")
        )
    }
}
