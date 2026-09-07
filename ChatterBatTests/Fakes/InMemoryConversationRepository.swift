import Foundation
@testable import ChatterBat

/// In-memory `ConversationRepository` double. Never touches SwiftData —
/// used by `ChatCoordinator`/`AppViewModel` tests that need to verify
/// *that* persistence calls happen and with what data, without needing a
/// full SwiftData round trip (that's what
/// `SwiftDataConversationRepositoryTests` is for).
@MainActor
final class InMemoryConversationRepository: ConversationRepository {
    private(set) var conversations: [Conversation] = []
    private(set) var messagesByConversation: [UUID: [TranscriptMessage]] = [:]

    private(set) var appendCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteMessageCallCount = 0
    private(set) var interruptCallCount = 0

    func loadAllConversations() throws -> [Conversation] {
        conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadMessages(for conversationID: UUID) throws -> [TranscriptMessage] {
        messagesByConversation[conversationID] ?? []
    }

    func createConversation(title: String) throws -> Conversation {
        let conversation = Conversation(title: title, updatedAt: .now)
        conversations.append(conversation)
        messagesByConversation[conversation.id] = []
        return conversation
    }

    func rename(conversationID: UUID, to newTitle: String) throws {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].title = newTitle
    }

    func deleteConversation(conversationID: UUID) throws {
        conversations.removeAll { $0.id == conversationID }
        messagesByConversation[conversationID] = nil
    }

    func appendMessage(_ message: TranscriptMessage, toConversation conversationID: UUID) throws {
        appendCallCount += 1
        messagesByConversation[conversationID, default: []].append(message)
        touchConversation(conversationID, preview: message.content)
    }

    func updateMessage(_ message: TranscriptMessage, inConversation conversationID: UUID) throws {
        updateCallCount += 1
        guard var messages = messagesByConversation[conversationID] else { return }
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index] = message
        messagesByConversation[conversationID] = messages
        touchConversation(conversationID, preview: message.content)
    }

    func deleteMessage(_ messageID: UUID, fromConversation conversationID: UUID) throws {
        deleteMessageCallCount += 1
        messagesByConversation[conversationID]?.removeAll { $0.id == messageID }
    }

    func interruptAllStreamingMessages() throws {
        interruptCallCount += 1
        for (conversationID, messages) in messagesByConversation {
            messagesByConversation[conversationID] = messages.map { message in
                var copy = message
                if copy.status == .streaming { copy.status = .interrupted }
                return copy
            }
        }
    }

    private func touchConversation(_ conversationID: UUID, preview: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].updatedAt = .now
        conversations[index].lastMessagePreview = preview
    }
}
