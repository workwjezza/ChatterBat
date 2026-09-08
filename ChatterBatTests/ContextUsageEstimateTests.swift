import XCTest
@testable import ChatterBat

final class ContextUsageEstimateTests: XCTestCase {
    func testEmptyMessagesProduceZeroEstimate() {
        let estimate = ContextUsageEstimate.estimate(for: [], contextLength: 1000)
        XCTAssertEqual(estimate.messageCount, 0)
        XCTAssertEqual(estimate.characterCount, 0)
        XCTAssertEqual(estimate.estimatedTokens, 0)
        XCTAssertEqual(estimate.percentOfContextWindow, 0)
    }

    func testEstimatedTokensUsesFourCharactersPerTokenHeuristic() {
        let messages = [OutgoingChatMessage(role: .user, content: String(repeating: "a", count: 400))]
        let estimate = ContextUsageEstimate.estimate(for: messages, contextLength: nil)
        XCTAssertEqual(estimate.characterCount, 400)
        XCTAssertEqual(estimate.estimatedTokens, 100)
    }

    func testPercentOfContextWindowIsNilWhenContextLengthUnknown() {
        let messages = [OutgoingChatMessage(role: .user, content: "hello")]
        let estimate = ContextUsageEstimate.estimate(for: messages, contextLength: nil)
        XCTAssertNil(estimate.percentOfContextWindow)
    }

    func testPercentOfContextWindowIsNilWhenContextLengthIsZeroOrNegative() {
        let messages = [OutgoingChatMessage(role: .user, content: "hello")]
        XCTAssertNil(ContextUsageEstimate.estimate(for: messages, contextLength: 0).percentOfContextWindow)
        XCTAssertNil(ContextUsageEstimate.estimate(for: messages, contextLength: -5).percentOfContextWindow)
    }

    func testPercentOfContextWindowComputedWhenContextLengthKnown() {
        let messages = [OutgoingChatMessage(role: .user, content: String(repeating: "a", count: 400))]
        // 400 chars -> 100 estimated tokens; context length 200 -> 50%.
        let estimate = ContextUsageEstimate.estimate(for: messages, contextLength: 200)
        XCTAssertEqual(estimate.percentOfContextWindow, 50)
    }

    func testMessageCountReflectsAllMessagesPassedIn() {
        let messages = [
            OutgoingChatMessage(role: .user, content: "a"),
            OutgoingChatMessage(role: .assistant, content: "b"),
            OutgoingChatMessage(role: .user, content: "c")
        ]
        let estimate = ContextUsageEstimate.estimate(for: messages, contextLength: nil)
        XCTAssertEqual(estimate.messageCount, 3)
    }
}
