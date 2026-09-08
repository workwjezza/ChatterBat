import XCTest
import SwiftData
@testable import ChatterBat

/// Stage 7: verifies the new, plain-additive `PersistedMessage`
/// tool-invocation columns round-trip correctly. Follows this
/// project's established pattern (see `SwiftDataConversationRepositoryTests`'s
/// doc comment) of constructing the in-memory container and repository
/// inline, directly in each test body, never via `setUp()` or a
/// helper function, on this toolchain.
@MainActor
final class SwiftDataConversationRepositoryAgentToolsTests: XCTestCase {
    func testToolInvocationRecordRoundTripsThroughPersistence() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Tools")
        let toolMessage = TranscriptMessage(
            role: .tool,
            content: "file contents",
            status: .completed,
            toolInvocation: ToolInvocationRecord(
                tool: .readFile,
                toolCallID: "call_1",
                modelStatedReason: "need it",
                approvedItemName: "notes.txt"
            )
        )
        try repository.appendMessage(toolMessage, toConversation: conversation.id)

        let loaded = try repository.loadMessages(for: conversation.id)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.role, .tool)
        XCTAssertEqual(loaded.first?.status, .completed)
        XCTAssertEqual(loaded.first?.toolInvocation?.tool, .readFile)
        XCTAssertEqual(loaded.first?.toolInvocation?.toolCallID, "call_1")
        XCTAssertEqual(loaded.first?.toolInvocation?.modelStatedReason, "need it")
        XCTAssertEqual(loaded.first?.toolInvocation?.approvedItemName, "notes.txt")
    }

    func testOrdinaryMessageHasNilToolInvocationAfterRoundTrip() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Chat")
        try repository.appendMessage(
            TranscriptMessage(role: .user, content: "hi", status: .completed),
            toConversation: conversation.id
        )

        let loaded = try repository.loadMessages(for: conversation.id)

        XCTAssertNil(loaded.first?.toolInvocation)
    }

    func testAwaitingApprovalMessageIsInterruptedAtLaunchLikeStreaming() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Tools")
        let toolMessage = TranscriptMessage(
            role: .tool,
            content: "",
            status: .awaitingApproval,
            toolInvocation: ToolInvocationRecord(tool: .readFile, toolCallID: "call_1", modelStatedReason: "x")
        )
        try repository.appendMessage(toolMessage, toConversation: conversation.id)

        try repository.interruptAllStreamingMessages()

        let loaded = try repository.loadMessages(for: conversation.id)
        XCTAssertEqual(loaded.first?.status, .interrupted)
    }

    func testUpdateMessagePreservesApprovedItemNameWrittenAfterInitialAppend() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Tools")
        var toolMessage = TranscriptMessage(
            role: .tool,
            content: "",
            status: .awaitingApproval,
            toolInvocation: ToolInvocationRecord(tool: .readFile, toolCallID: "call_1", modelStatedReason: "x")
        )
        try repository.appendMessage(toolMessage, toConversation: conversation.id)

        toolMessage.status = .completed
        toolMessage.content = "contents"
        toolMessage.toolInvocation?.approvedItemName = "picked.txt"
        try repository.updateMessage(toolMessage, inConversation: conversation.id)

        let loaded = try repository.loadMessages(for: conversation.id)
        XCTAssertEqual(loaded.first?.status, .completed)
        XCTAssertEqual(loaded.first?.toolInvocation?.approvedItemName, "picked.txt")
    }
}
