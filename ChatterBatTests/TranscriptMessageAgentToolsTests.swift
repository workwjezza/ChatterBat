import XCTest
@testable import ChatterBat

final class TranscriptMessageAgentToolsTests: XCTestCase {
    func testToolMessageIsNeverEligibleForContextRegardlessOfStatus() {
        let statuses: [MessageStatus] = [.completed, .streaming, .cancelled, .failed("x"), .interrupted, .awaitingApproval, .toolDenied]
        for status in statuses {
            let message = TranscriptMessage(role: .tool, content: "result", status: status)
            XCTAssertFalse(message.isEligibleForContext, "Expected .tool message with status \(status) to be ineligible.")
        }
    }

    func testAwaitingApprovalAssistantMessageIsNotEligibleForContext() {
        let message = TranscriptMessage(role: .assistant, content: "", status: .awaitingApproval)
        XCTAssertFalse(message.isEligibleForContext)
    }

    func testToolDeniedAssistantMessageIsNotEligibleForContext() {
        let message = TranscriptMessage(role: .assistant, content: "denied", status: .toolDenied)
        XCTAssertFalse(message.isEligibleForContext)
    }

    func testOutgoingToolCallAndToolCallIDDefaultToEmptyAndNil() {
        let message = OutgoingChatMessage(role: .assistant, content: "hi")
        XCTAssertEqual(message.toolCalls, [])
        XCTAssertNil(message.toolCallID)
    }

    func testToolInvocationRecordIdentifiableIDMatchesToolCallID() {
        let record = ToolInvocationRecord(tool: .readFile, toolCallID: "call_42", modelStatedReason: "x")
        XCTAssertEqual(record.id, "call_42")
    }
}
