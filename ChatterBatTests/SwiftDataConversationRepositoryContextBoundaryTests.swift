import XCTest
import SwiftData
@testable import ChatterBat

/// Exercises `SwiftDataConversationRepository`'s Stage 6
/// context-boundary methods against an isolated, in-memory
/// `ModelContainer`.
///
/// IMPORTANT: every test constructs `ChatterBatModelContainer.inMemory()`
/// and `SwiftDataConversationRepository` inline, directly in the test
/// method body — never via `setUp()`/a helper function. See
/// `SwiftDataConversationRepositoryTests`'s file-level doc comment and
/// docs/DECISIONS.md for why.
@MainActor
final class SwiftDataConversationRepositoryContextBoundaryTests: XCTestCase {
    func testNewConversationHasNoContextBoundaryByDefault() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Test")

        XCTAssertNil(try repository.contextBoundaryMessageID(for: conversation.id))
    }

    func testSetContextBoundaryPersistsAndIsLoadable() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Test")
        let message = TranscriptMessage(role: .user, content: "hi", status: .completed)
        try repository.appendMessage(message, toConversation: conversation.id)

        try repository.setContextBoundary(message.id, forConversation: conversation.id)

        XCTAssertEqual(try repository.contextBoundaryMessageID(for: conversation.id), message.id)
    }

    func testClearingContextBoundaryPersistsNil() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Test")
        let message = TranscriptMessage(role: .user, content: "hi", status: .completed)
        try repository.appendMessage(message, toConversation: conversation.id)
        try repository.setContextBoundary(message.id, forConversation: conversation.id)

        try repository.setContextBoundary(nil, forConversation: conversation.id)

        XCTAssertNil(try repository.contextBoundaryMessageID(for: conversation.id))
    }

    func testSetContextBoundaryOnUnknownConversationDoesNotThrow() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        // Deliberately a conversation ID never created — mirrors the
        // repository's existing "no-op on unknown ID" behavior for
        // rename/deleteConversation rather than throwing.
        XCTAssertNoThrow(try repository.setContextBoundary(UUID(), forConversation: UUID()))
    }

    func testContextBoundaryDoesNotAffectDeletingOrLoadingMessages() throws {
        let container = ChatterBatModelContainer.inMemory()
        let repository = SwiftDataConversationRepository(context: container.mainContext)

        let conversation = try repository.createConversation(title: "Test")
        let first = TranscriptMessage(role: .user, content: "first", status: .completed)
        let second = TranscriptMessage(role: .user, content: "second", status: .completed)
        try repository.appendMessage(first, toConversation: conversation.id)
        try repository.appendMessage(second, toConversation: conversation.id)
        try repository.setContextBoundary(second.id, forConversation: conversation.id)

        // Setting a boundary must never hide or delete any message —
        // it only affects what ChatCoordinator later sends as context.
        let loaded = try repository.loadMessages(for: conversation.id)
        XCTAssertEqual(loaded.map(\.content), ["first", "second"])
    }
}
