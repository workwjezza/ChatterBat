import Foundation

/// Persistence boundary for conversations and their transcripts.
///
/// Exposes only plain, `Sendable` domain types (`Conversation`,
/// `TranscriptMessage`) — never a SwiftData `@Model` instance — per the
/// brief's rule against passing SwiftData model instances between
/// actors. All methods are `@MainActor` because the underlying SwiftData
/// `ModelContext` this protocol wraps is itself main-actor-bound in this
/// app (see `SwiftDataConversationRepository`); callers on the main
/// actor (view models) call these directly, and no background actor
/// touches persistence.
@MainActor
protocol ConversationRepository: AnyObject {
    /// Loads every conversation (not their messages), most-recently-
    /// updated first. Called once at launch by `AppViewModel`.
    func loadAllConversations() throws -> [Conversation]

    /// Loads one conversation's ordered messages. Called lazily by
    /// `ChatCoordinator` the first time a conversation's transcript is
    /// accessed, rather than eager-loading every conversation's full
    /// history at launch.
    func loadMessages(for conversationID: UUID) throws -> [TranscriptMessage]

    /// Creates and persists a new, empty conversation.
    func createConversation(title: String) throws -> Conversation

    func rename(conversationID: UUID, to newTitle: String) throws

    /// Deletes a conversation and all of its messages (cascade). Does
    /// not touch any provider credential — per the brief, conversation
    /// deletion and account disconnection are separate concerns.
    func deleteConversation(conversationID: UUID) throws

    /// Appends a new message to a conversation and updates the
    /// conversation's `updatedAt`/`lastMessagePreview`.
    func appendMessage(_ message: TranscriptMessage, toConversation conversationID: UUID) throws

    /// Overwrites the persisted state of an existing message (content,
    /// status, usage) — used for checkpointing a streaming message and
    /// for writing its final terminal state.
    func updateMessage(_ message: TranscriptMessage, inConversation conversationID: UUID) throws

    /// Removes a single message (used by retry, which removes the failed
    /// assistant reply and its preceding user turn before re-sending).
    func deleteMessage(_ messageID: UUID, fromConversation conversationID: UUID) throws

    /// Marks every message still `.streaming` (in any conversation) as
    /// `.interrupted`. Called once at launch, before any UI reads
    /// messages, so a message that was mid-stream when the app last quit
    /// is never displayed as if still live nor silently resumed.
    func interruptAllStreamingMessages() throws
}
