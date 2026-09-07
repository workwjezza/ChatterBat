import Foundation
import Observation

/// Root presentation state for the conversation list.
///
/// As of Stage 4, this is backed by a real `ConversationRepository`
/// (SwiftData) rather than in-memory-only state. The `conversations:`
/// initializer parameter is retained only for previews/tests that want
/// to seed state without touching a repository at all; production code
/// always goes through `loadFromRepository()`.
@Observable
@MainActor
final class AppViewModel {
    private(set) var conversations: [Conversation]
    var selectedConversationID: Conversation.ID?
    var isModelPickerPresented = false
    var searchText = ""

    /// The model that would be used for the *next* message sent. Not
    /// persisted per-conversation yet — this is a simple, single
    /// app-wide "current selection," consistent with the single global
    /// generation slot. Per the brief, selecting a model here must never
    /// itself send a request.
    var selectedModel: ModelInfo?

    /// `nil` until `loadFromRepository()` runs (or in previews/tests that
    /// never call it), in which case conversation-list mutations stay
    /// in-memory-only — this lets existing previews/tests keep working
    /// unchanged.
    private var repository: ConversationRepository?

    init(conversations: [Conversation] = []) {
        self.conversations = conversations
        self.selectedConversationID = conversations.first?.id
    }

    /// Loads persisted conversations (most-recently-updated first) and
    /// selects the most recent one, if any. Call once at launch, after
    /// the repository has already run `interruptAllStreamingMessages()`
    /// (see `ChatCoordinator.loadPersistedState`), so the list never
    /// briefly shows a message as still "streaming."
    ///
    /// NOTE: prefer `attachRepository(_:initialConversations:)` in
    /// production — see its doc comment for why the initial fetch is
    /// deliberately done outside this method's caller (a SwiftUI view)
    /// on this toolchain.
    func loadFromRepository(_ repository: ConversationRepository) {
        self.repository = repository
        do {
            conversations = try repository.loadAllConversations()
            selectedConversationID = conversations.first?.id
        } catch {
            // A load failure must not be silently treated as "no
            // conversations yet" — that would look identical to a
            // legitimately empty history to the user. Since Stage 4 has
            // no dedicated error-banner UI, this is surfaced honestly via
            // assertionFailure in debug builds; Stage 5+ should add a
            // visible error state for this path.
            assertionFailure("Failed to load conversations: \(error)")
            conversations = []
        }
    }

    /// Attaches a repository for future writes (create/rename/delete)
    /// using conversations that were *already fetched* by the caller —
    /// this view model never itself calls `loadAllConversations()` in
    /// this path.
    ///
    /// Why this exists as a separate method from `loadFromRepository`:
    /// on this toolchain, calling `ModelContext.fetch` from within a
    /// SwiftUI view's `init`, `.task {}`, or `.onAppear` (even deferred
    /// via `DispatchQueue.main.async`) reproducibly crashed the app at
    /// launch (EXC_BREAKPOINT inside AppKit's window-restoration
    /// re-entrancy — see docs/DECISIONS.md). The one place that never
    /// crashed was a plain synchronous call made before any SwiftUI view
    /// exists at all, i.e. inside `AppDependencies.live()`. So
    /// `AppDependencies.live()` performs the initial fetch and passes
    /// the result here.
    func attachRepository(_ repository: ConversationRepository, initialConversations: [Conversation]) {
        self.repository = repository
        conversations = initialConversations
        selectedConversationID = conversations.first?.id
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

    /// Creates a new conversation (persisted immediately if a repository
    /// is attached) and selects it.
    func startNewConversation() {
        if let repository {
            do {
                let conversation = try repository.createConversation(title: "New Chat")
                conversations.insert(conversation, at: 0)
                selectedConversationID = conversation.id
                return
            } catch {
                assertionFailure("Failed to create a new conversation: \(error)")
            }
        }
        let conversation = Conversation(title: "New Chat", updatedAt: .now)
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
    }

    func delete(_ conversation: Conversation) {
        if let repository {
            do {
                try repository.deleteConversation(conversationID: conversation.id)
            } catch {
                assertionFailure("Failed to delete conversation \(conversation.id): \(error)")
                return
            }
        }
        conversations.removeAll { $0.id == conversation.id }
        if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first?.id
        }
    }

    func rename(_ conversation: Conversation, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else {
            return
        }
        if let repository {
            do {
                try repository.rename(conversationID: conversation.id, to: trimmed)
            } catch {
                assertionFailure("Failed to rename conversation \(conversation.id): \(error)")
                return
            }
        }
        conversations[index].title = trimmed
    }

    /// Refreshes one conversation's `lastMessagePreview`/`updatedAt` from
    /// the repository and re-sorts the list, most-recent first. Called
    /// by `RootView` after `ChatCoordinator` appends/updates a message so
    /// the sidebar reflects new activity without polling.
    func refreshConversationMetadata(conversationID: UUID) {
        guard let repository else { return }
        do {
            guard let updated = try repository.loadAllConversations().first(where: { $0.id == conversationID }) else {
                return
            }
            guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
            conversations[index] = updated
            conversations.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            assertionFailure("Failed to refresh conversation \(conversationID): \(error)")
        }
    }
}
