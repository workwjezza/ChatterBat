import XCTest
@testable import ChatterBat

/// Basic behavioral tests for `AppViewModel`'s no-repository-attached
/// code paths (the `conversations:` initializer never calls
/// `loadFromRepository`, so these exercise pure in-memory list
/// mutation). Repository-backed behavior is covered separately in
/// `AppViewModelRepositoryTests`.
final class AppViewModelTests: XCTestCase {
    @MainActor
    func testInitialSelectionDefaultsToFirstConversation() {
        let conversations = [
            Conversation(title: "First", lastMessagePreview: "a"),
            Conversation(title: "Second", lastMessagePreview: "b")
        ]
        let viewModel = AppViewModel(conversations: conversations)

        XCTAssertEqual(viewModel.selectedConversationID, conversations.first?.id)
    }

    @MainActor
    func testStartNewConversationInsertsAtFrontAndSelectsIt() {
        let viewModel = AppViewModel(conversations: [])

        viewModel.startNewConversation()

        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertEqual(viewModel.selectedConversationID, viewModel.conversations.first?.id)
    }

    @MainActor
    func testDeleteSelectedConversationReassignsSelection() {
        let first = Conversation(title: "First", lastMessagePreview: "a")
        let second = Conversation(title: "Second", lastMessagePreview: "b")
        let viewModel = AppViewModel(conversations: [first, second])
        viewModel.selectedConversationID = first.id

        viewModel.delete(first)

        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertEqual(viewModel.selectedConversationID, second.id)
    }

    @MainActor
    func testRenameTrimsWhitespaceAndIgnoresEmptyTitle() {
        let conversation = Conversation(title: "Original", lastMessagePreview: "a")
        let viewModel = AppViewModel(conversations: [conversation])

        viewModel.rename(conversation, to: "  Renamed  ")
        XCTAssertEqual(viewModel.conversations.first?.title, "Renamed")

        viewModel.rename(conversation, to: "   ")
        XCTAssertEqual(viewModel.conversations.first?.title, "Renamed")
    }

    @MainActor
    func testFilteredConversationsMatchesCaseInsensitiveSearch() {
        let conversations = [
            Conversation(title: "Swift Tips", lastMessagePreview: "a"),
            Conversation(title: "Cooking Notes", lastMessagePreview: "b")
        ]
        let viewModel = AppViewModel(conversations: conversations)

        viewModel.searchText = "swift"

        XCTAssertEqual(viewModel.filteredConversations.map(\.title), ["Swift Tips"])
    }
}
