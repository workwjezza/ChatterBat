import XCTest
@testable import ChatterBat

/// Exercises `AppViewModel`'s repository-backed code paths, using
/// `InMemoryConversationRepository` — distinct from `AppViewModelTests`,
/// which only exercises the no-repository in-memory-only paths.
final class AppViewModelRepositoryTests: XCTestCase {
    @MainActor
    func testLoadFromRepositoryPopulatesConversationsMostRecentFirst() throws {
        let repository = InMemoryConversationRepository()
        let older = try repository.createConversation(title: "Older")
        Thread.sleep(forTimeInterval: 0.01)
        let newer = try repository.createConversation(title: "Newer")
        let viewModel = AppViewModel()

        viewModel.loadFromRepository(repository)

        XCTAssertEqual(viewModel.conversations.map(\.id), [newer.id, older.id])
        XCTAssertEqual(viewModel.selectedConversationID, newer.id)
    }

    @MainActor
    func testStartNewConversationPersistsThroughRepository() throws {
        let repository = InMemoryConversationRepository()
        let viewModel = AppViewModel()
        viewModel.loadFromRepository(repository)

        viewModel.startNewConversation()

        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertEqual(try repository.loadAllConversations().count, 1)
        XCTAssertEqual(viewModel.selectedConversationID, viewModel.conversations.first?.id)
    }

    @MainActor
    func testDeleteRemovesFromRepositoryToo() throws {
        let repository = InMemoryConversationRepository()
        let conversation = try repository.createConversation(title: "Chat")
        let viewModel = AppViewModel()
        viewModel.loadFromRepository(repository)

        viewModel.delete(conversation)

        XCTAssertTrue(viewModel.conversations.isEmpty)
        XCTAssertTrue(try repository.loadAllConversations().isEmpty)
    }

    @MainActor
    func testRenamePersistsThroughRepository() throws {
        let repository = InMemoryConversationRepository()
        let conversation = try repository.createConversation(title: "Old")
        let viewModel = AppViewModel()
        viewModel.loadFromRepository(repository)

        viewModel.rename(conversation, to: "New Title")

        XCTAssertEqual(viewModel.conversations.first?.title, "New Title")
        XCTAssertEqual(try repository.loadAllConversations().first?.title, "New Title")
    }

    @MainActor
    func testRefreshConversationMetadataPullsUpdatedPreviewAndResorts() throws {
        let repository = InMemoryConversationRepository()
        let first = try repository.createConversation(title: "First")
        Thread.sleep(forTimeInterval: 0.01)
        let second = try repository.createConversation(title: "Second")
        let viewModel = AppViewModel()
        viewModel.loadFromRepository(repository)
        XCTAssertEqual(viewModel.conversations.map(\.id), [second.id, first.id])

        // Simulate ChatCoordinator appending a message to the older
        // conversation, then refreshing metadata for it.
        try repository.appendMessage(
            TranscriptMessage(role: .user, content: "new activity", status: .completed),
            toConversation: first.id
        )
        viewModel.refreshConversationMetadata(conversationID: first.id)

        XCTAssertEqual(viewModel.conversations.first?.id, first.id, "Most recently active conversation should sort first.")
        XCTAssertEqual(viewModel.conversations.first?.lastMessagePreview, "new activity")
    }
}
