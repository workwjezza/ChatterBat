import Foundation
import Observation

/// Root presentation state for the Stage 0 shell.
///
/// This is intentionally minimal: it only tracks the in-memory conversation
/// list and the current selection so the split-view navigation and toolbar
/// actions (New Chat, model picker placeholder) have something real to
/// operate on. No networking, persistence, or credential access happens
/// here. Later stages will introduce a chat coordinator, catalog service,
/// and repository that this view model will depend on instead of demo data.
@Observable
@MainActor
final class AppViewModel {
    private(set) var conversations: [Conversation]
    var selectedConversationID: Conversation.ID?
    var isModelPickerPresented = false
    var searchText = ""

    init(conversations: [Conversation] = DemoFixtures.conversations) {
        self.conversations = conversations
        self.selectedConversationID = conversations.first?.id
    }

    var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    /// Creates a new, empty demo conversation and selects it.
    ///
    /// Stage 3/4 will replace this with a real conversation created against
    /// the persistence repository, not an in-memory placeholder.
    func startNewConversation() {
        let conversation = Conversation(
            title: "New Chat",
            preview: "Say something to get started.",
            updatedAt: .now
        )
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first?.id
        }
    }

    func rename(_ conversation: Conversation, to newTitle: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else {
            return
        }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversations[index].title = trimmed
    }
}
