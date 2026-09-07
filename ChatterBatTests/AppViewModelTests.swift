import XCTest
@testable import ChatterBat

/// Basic behavioral tests for the Stage 0 root view model.
///
/// These exercise only in-memory demo state. No networking, Keychain, or
/// persistence is involved, matching the Stage 0 scope.
final class AppViewModelTests: XCTestCase {
    @MainActor
    func testInitialSelectionDefaultsToFirstConversation() {
        let conversations = [
            Conversation(title: "First", preview: "a"),
            Conversation(title: "Second", preview: "b")
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
        let first = Conversation(title: "First", preview: "a")
        let second = Conversation(title: "Second", preview: "b")
        let viewModel = AppViewModel(conversations: [first, second])
        viewModel.selectedConversationID = first.id

        viewModel.delete(first)

        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertEqual(viewModel.selectedConversationID, second.id)
    }

    @MainActor
    func testRenameTrimsWhitespaceAndIgnoresEmptyTitle() {
        let conversation = Conversation(title: "Original", preview: "a")
        let viewModel = AppViewModel(conversations: [conversation])

        viewModel.rename(conversation, to: "  Renamed  ")
        XCTAssertEqual(viewModel.conversations.first?.title, "Renamed")

        viewModel.rename(conversation, to: "   ")
        XCTAssertEqual(viewModel.conversations.first?.title, "Renamed")
    }

    @MainActor
    func testFilteredConversationsMatchesCaseInsensitiveSearch() {
        let conversations = [
            Conversation(title: "Swift Tips", preview: "a"),
            Conversation(title: "Cooking Notes", preview: "b")
        ]
        let viewModel = AppViewModel(conversations: conversations)

        viewModel.searchText = "swift"

        XCTAssertEqual(viewModel.filteredConversations.map(\.title), ["Swift Tips"])
    }
}
