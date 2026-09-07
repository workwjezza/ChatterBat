import Foundation
import SwiftData

/// `ConversationRepository` backed by SwiftData.
///
/// Owns a `ModelContext` and only ever converts to/from the plain
/// `Conversation`/`TranscriptMessage` structs at its public boundary —
/// `PersistedConversation`/`PersistedMessage` instances never escape this
/// file's mapping functions.
///
/// Uses a plain `conversationID: UUID` foreign key on `PersistedMessage`
/// and explicit fetch-then-filter-in-Swift queries throughout, rather
/// than a SwiftData `@Relationship`/`#Predicate`/`sortBy` — see
/// docs/DECISIONS.md: relationship traversal and predicate/sortBy
/// FetchDescriptors all reproducibly crashed the process with
/// EXC_BREAKPOINT on this toolchain (Xcode 26.6 / macOS 26.6.2). Given
/// the expected data volume (one user's local chat history), an
/// unfiltered fetch + Swift-side filter/sort is a fully acceptable
/// trade-off for correctness over marginal query performance.
@MainActor
final class SwiftDataConversationRepository: ConversationRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func loadAllConversations() throws -> [Conversation] {
        let conversations = try context.fetch(FetchDescriptor<PersistedConversation>())
        return conversations
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(Self.map)
    }

    func loadMessages(for conversationID: UUID) throws -> [TranscriptMessage] {
        try allMessages(for: conversationID)
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(Self.map)
    }

    func createConversation(title: String) throws -> Conversation {
        let now = Date.now
        let persisted = PersistedConversation(
            id: UUID(),
            title: title,
            lastMessagePreview: "",
            createdAt: now,
            updatedAt: now
        )
        context.insert(persisted)
        try context.save()
        return Self.map(persisted)
    }

    func rename(conversationID: UUID, to newTitle: String) throws {
        guard let persisted = try fetchConversation(id: conversationID) else { return }
        persisted.title = newTitle
        try context.save()
    }

    func deleteConversation(conversationID: UUID) throws {
        guard let persisted = try fetchConversation(id: conversationID) else { return }
        // No SwiftData cascade rule (see file-level note) — messages are
        // deleted explicitly here.
        for message in try allMessages(for: conversationID) {
            context.delete(message)
        }
        context.delete(persisted)
        try context.save()
    }

    func appendMessage(_ message: TranscriptMessage, toConversation conversationID: UUID) throws {
        guard let conversation = try fetchConversation(id: conversationID) else { return }
        let nextIndex = try allMessages(for: conversationID).map(\.sortIndex).max().map { $0 + 1 } ?? 0
        let persisted = Self.map(message, conversationID: conversationID, sortIndex: nextIndex)
        context.insert(persisted)
        conversation.updatedAt = .now
        conversation.lastMessagePreview = Self.previewText(for: message)
        try context.save()
    }

    func updateMessage(_ message: TranscriptMessage, inConversation conversationID: UUID) throws {
        guard let conversation = try fetchConversation(id: conversationID) else { return }
        guard let persisted = try allMessages(for: conversationID).first(where: { $0.id == message.id }) else { return }
        Self.apply(message, to: persisted)
        conversation.updatedAt = .now
        conversation.lastMessagePreview = Self.previewText(for: message)
        try context.save()
    }

    func deleteMessage(_ messageID: UUID, fromConversation conversationID: UUID) throws {
        guard let persisted = try allMessages(for: conversationID).first(where: { $0.id == messageID }) else { return }
        context.delete(persisted)
        try context.save()
    }

    func interruptAllStreamingMessages() throws {
        let allMessages = try context.fetch(FetchDescriptor<PersistedMessage>())
        let streamingMessages = allMessages.filter { $0.statusRaw == "streaming" }
        guard !streamingMessages.isEmpty else { return }
        for message in streamingMessages {
            message.statusRaw = "interrupted"
        }
        try context.save()
    }

    // MARK: - Private

    private func fetchConversation(id: UUID) throws -> PersistedConversation? {
        let conversations = try context.fetch(FetchDescriptor<PersistedConversation>())
        return conversations.first { $0.id == id }
    }

    private func allMessages(for conversationID: UUID) throws -> [PersistedMessage] {
        let messages = try context.fetch(FetchDescriptor<PersistedMessage>())
        return messages.filter { $0.conversationID == conversationID }
    }

    private static func previewText(for message: TranscriptMessage) -> String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(120))
    }
}
