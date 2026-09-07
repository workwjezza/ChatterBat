import XCTest
import SwiftData
@testable import ChatterBat

/// Exercises `SwiftDataConversationRepository` against an isolated,
/// in-memory `ModelContainer` — per the brief's testing contract,
/// persistence tests must never touch a real on-disk store shared with
/// the running app.
///
/// IMPORTANT: every test constructs `ChatterBatModelContainer.inMemory()`
/// and `SwiftDataConversationRepository` *inline*, directly in the test
/// method body — never via `setUp()`/`tearDown()`, and never via a
/// `private func` helper (even a `@MainActor` one). Both of those
/// patterns were empirically proven (see docs/DECISIONS.md) to
/// reproducibly hang the test process for ~20s until an XCTest timeout
/// killed and relaunched it, on this toolchain (Xcode 26.6 /
/// macOS 26.6.2) — while byte-for-bit identical code inlined directly in
/// the test method runs in milliseconds. This looks like a toolchain/
/// debugger-instrumentation quirk around calling into this specific
/// construction path through any intermediate function, not a bug in
/// the production code itself. Do not "clean up" this duplication by
/// reintroducing a shared setup helper without re-verifying against a
/// real timed test run first.
@MainActor
final class SwiftDataConversationRepositoryTests: XCTestCase {
    func testCreateConversationPersistsAndIsLoadable() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let created = try repository.createConversation(title: "Test Chat")
        let loaded = try repository.loadAllConversations()

        XCTAssertEqual(loaded.map(\.id), [created.id])
        XCTAssertEqual(loaded.first?.title, "Test Chat")
        XCTAssertEqual(loaded.first?.lastMessagePreview, "")
    }

    func testLoadAllConversationsOrdersByMostRecentlyUpdatedFirst() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let first = try repository.createConversation(title: "First")
        try repository.appendMessage(
            TranscriptMessage(role: .user, content: "hi", status: .completed),
            toConversation: first.id
        )
        Thread.sleep(forTimeInterval: 0.01)
        let second = try repository.createConversation(title: "Second")

        let loaded = try repository.loadAllConversations()

        XCTAssertEqual(loaded.map(\.title), ["Second", "First"])
        _ = second
    }

    func testAppendMessagePreservesOrderAndUpdatesPreview() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Chat")
        let first = TranscriptMessage(role: .user, content: "First message", status: .completed)
        let second = TranscriptMessage(role: .assistant, content: "Second message", status: .completed)

        try repository.appendMessage(first, toConversation: conversation.id)
        try repository.appendMessage(second, toConversation: conversation.id)

        let messages = try repository.loadMessages(for: conversation.id)
        XCTAssertEqual(messages.map(\.content), ["First message", "Second message"])

        let reloaded = try repository.loadAllConversations().first { $0.id == conversation.id }
        XCTAssertEqual(reloaded?.lastMessagePreview, "Second message")
    }

    func testUpdateMessageOverwritesContentStatusAndUsage() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Chat")
        var message = TranscriptMessage(role: .assistant, content: "partial", status: .streaming)
        try repository.appendMessage(message, toConversation: conversation.id)

        message.content = "partial complete"
        message.status = .completed
        message.usage = ChatUsage(promptTokens: 3, completionTokens: 4, totalTokens: 7)
        try repository.updateMessage(message, inConversation: conversation.id)

        let reloaded = try repository.loadMessages(for: conversation.id).first
        XCTAssertEqual(reloaded?.content, "partial complete")
        XCTAssertEqual(reloaded?.status, .completed)
        XCTAssertEqual(reloaded?.usage, ChatUsage(promptTokens: 3, completionTokens: 4, totalTokens: 7))
    }

    func testFailedMessagePreservesFailureMessageAcrossReload() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Chat")
        let message = TranscriptMessage(role: .assistant, content: "", status: .failed("Network error: timed out"))
        try repository.appendMessage(message, toConversation: conversation.id)

        let reloaded = try repository.loadMessages(for: conversation.id).first
        XCTAssertEqual(reloaded?.status, .failed("Network error: timed out"))
    }

    func testAttributionRoundTripsServiceAndModelID() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Chat")
        let identity = ModelIdentity(service: .venice, modelID: "llama-3.2-3b")
        let message = TranscriptMessage(role: .assistant, content: "hi", status: .completed, attribution: identity)
        try repository.appendMessage(message, toConversation: conversation.id)

        let reloaded = try repository.loadMessages(for: conversation.id).first
        XCTAssertEqual(reloaded?.attribution, identity)
    }
}
