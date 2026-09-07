import XCTest
import SwiftData
@testable import ChatterBat

/// See `SwiftDataConversationRepositoryTests`'s doc comment: every test
/// here constructs its container/repository fully inline — never via
/// `setUp()`, and never via a helper function — because both of those
/// indirections reproducibly hung the test process on this toolchain.
@MainActor
final class SwiftDataConversationRepositoryAdditionalTests: XCTestCase {
    func testDeleteConversationCascadesToMessages() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Chat")
        try repository.appendMessage(
            TranscriptMessage(role: .user, content: "hi", status: .completed),
            toConversation: conversation.id
        )

        try repository.deleteConversation(conversationID: conversation.id)

        XCTAssertTrue(try repository.loadAllConversations().isEmpty)
        XCTAssertTrue(try repository.loadMessages(for: conversation.id).isEmpty)
    }

    func testDeleteMessageRemovesOnlyThatMessage() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Chat")
        let keep = TranscriptMessage(role: .user, content: "keep", status: .completed)
        let remove = TranscriptMessage(role: .assistant, content: "remove", status: .completed)
        try repository.appendMessage(keep, toConversation: conversation.id)
        try repository.appendMessage(remove, toConversation: conversation.id)

        try repository.deleteMessage(remove.id, fromConversation: conversation.id)

        let messages = try repository.loadMessages(for: conversation.id)
        XCTAssertEqual(messages.map(\.content), ["keep"])
    }

    func testRenameUpdatesTitle() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Old Title")

        try repository.rename(conversationID: conversation.id, to: "New Title")

        let reloaded = try repository.loadAllConversations().first
        XCTAssertEqual(reloaded?.title, "New Title")
    }

    func testInterruptAllStreamingMessagesRewritesStatusAcrossConversations() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversationA = try repository.createConversation(title: "A")
        let conversationB = try repository.createConversation(title: "B")
        let streamingA = TranscriptMessage(role: .assistant, content: "mid-stream", status: .streaming)
        let streamingB = TranscriptMessage(role: .assistant, content: "also mid-stream", status: .streaming)
        let completed = TranscriptMessage(role: .assistant, content: "done", status: .completed)
        try repository.appendMessage(streamingA, toConversation: conversationA.id)
        try repository.appendMessage(streamingB, toConversation: conversationB.id)
        try repository.appendMessage(completed, toConversation: conversationA.id)

        try repository.interruptAllStreamingMessages()

        let messagesA = try repository.loadMessages(for: conversationA.id)
        let messagesB = try repository.loadMessages(for: conversationB.id)
        XCTAssertEqual(messagesA.first { $0.id == streamingA.id }?.status, .interrupted)
        XCTAssertEqual(messagesA.first { $0.id == completed.id }?.status, .completed, "Only streaming messages should change.")
        XCTAssertEqual(messagesB.first { $0.id == streamingB.id }?.status, .interrupted)
    }

    func testLoadMessagesForUnknownConversationReturnsEmptyRatherThanThrowing() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let messages = try repository.loadMessages(for: UUID())
        XCTAssertTrue(messages.isEmpty)
    }
}
