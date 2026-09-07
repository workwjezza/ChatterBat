import Foundation
import Observation

/// Owns conversation transcripts and drives streaming chat requests.
///
/// As of Stage 4, transcripts are backed by a `ConversationRepository`
/// (SwiftData): each conversation's messages are lazily loaded on first
/// access and cached in `transcripts` for the rest of the session.
/// Per the brief ("Do not persist every changing token" /
/// "checkpoint partial output, not on every token"), in-progress content
/// deltas are checkpointed to the repository periodically
/// (`checkpointInterval`) rather than on every single delta, with an
/// unconditional final write on every terminal state
/// (completed/cancelled/failed). Per the brief, only one generation is
/// active globally; `send` rejects a new send while `generationState` is
/// not `.idle`.
@Observable
@MainActor
final class ChatCoordinator {
    private(set) var transcripts: [UUID: [TranscriptMessage]] = [:]
    private(set) var generationState: GenerationState = .idle

    /// Records, per conversation, which service has actually received
    /// this conversation's history so far (i.e. the service used for the
    /// most recent successfully-sent turn). `nil` means no message has
    /// been sent yet in this conversation. Used to detect a cross-service
    /// switch that needs disclosure before the *next* send — per the
    /// brief, this must never trigger merely from opening the picker.
    private(set) var lastUsedService: [UUID: AIService] = [:]

    private let credentialStore: CredentialStore
    private let clients: [AIService: ChatStreamingClient]
    private let repository: ConversationRepository?
    private var activeTask: Task<Void, Never>?
    private var loadedConversationIDs: Set<UUID> = []
    /// Checkpoint the streaming assistant message to the repository
    /// every this many content-delta events, rather than on every single
    /// one, per the brief's "not on every token" guidance. A value of 1
    /// would checkpoint every delta; tests use that to verify
    /// checkpointing happens at all without waiting for a large volume
    /// of deltas.
    private let checkpointInterval: Int

    init(
        credentialStore: CredentialStore,
        clients: [AIService: ChatStreamingClient],
        repository: ConversationRepository? = nil,
        checkpointInterval: Int = 20
    ) {
        self.credentialStore = credentialStore
        self.clients = clients
        self.repository = repository
        self.checkpointInterval = max(1, checkpointInterval)
    }

    /// Must be called once at launch, before any UI reads messages, so a
    /// message left `.streaming` by a previous quit is rewritten to
    /// `.interrupted` before it's ever displayed as if still live.
    func markInterruptedGenerationsAtLaunch() {
        guard let repository else { return }
        do {
            try repository.interruptAllStreamingMessages()
        } catch {
            assertionFailure("Failed to mark interrupted generations at launch: \(error)")
        }
    }

    /// Returns this conversation's transcript, lazily loading it from the
    /// repository on first access and caching the result for the rest of
    /// the session.
    func messages(for conversationID: UUID) -> [TranscriptMessage] {
        if !loadedConversationIDs.contains(conversationID), let repository {
            loadedConversationIDs.insert(conversationID)
            do {
                transcripts[conversationID] = try repository.loadMessages(for: conversationID)
            } catch {
                assertionFailure("Failed to load messages for \(conversationID): \(error)")
                transcripts[conversationID] = []
            }
        }
        return transcripts[conversationID] ?? []
    }

    /// Whether sending the next message to `model.service` would share
    /// this conversation's existing history with a *different* service
    /// than the one that has received it so far. Per the brief, callers
    /// must surface this before sending, not send silently.
    func wouldShareHistoryAcrossServices(conversationID: UUID, nextService: AIService) -> Bool {
        guard let previous = lastUsedService[conversationID] else { return false }
        return previous != nextService && !messages(for: conversationID).isEmpty
    }

    /// Sends `text` as a new user turn in `conversationID` using `model`.
    /// No-ops if a generation is already active anywhere in the app, or
    /// if `text` is empty after trimming — callers should disable Send in
    /// those cases, but this guards against a duplicate/racy invocation
    /// regardless.
    func send(text: String, in conversationID: UUID, using model: ModelInfo) {
        guard generationState == .idle else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = TranscriptMessage(role: .user, content: trimmed, status: .completed)
        let assistantMessage = TranscriptMessage(
            role: .assistant,
            content: "",
            status: .streaming,
            attribution: model.identity
        )
        let assistantMessageID = assistantMessage.id
        let outgoing = eligibleOutgoingMessages(for: conversationID) + [
            OutgoingChatMessage(role: .user, content: trimmed)
        ]

        appendAndPersist(userMessage, in: conversationID)
        appendAndPersist(assistantMessage, in: conversationID)
        generationState = .connecting(conversationID: conversationID)

        guard let key = (try? credentialStore.loadKey(for: model.service)) ?? nil else {
            fail(assistantMessageID, in: conversationID, message: "No API key configured for \(model.service.displayName). Connect it in Settings → Accounts.")
            generationState = .idle
            return
        }
        guard let client = clients[model.service] else {
            fail(assistantMessageID, in: conversationID, message: "\(model.service.displayName) is not available.")
            generationState = .idle
            return
        }

        activeTask = Task { [weak self] in
            await self?.runStream(
                client: client,
                apiKey: key,
                model: model,
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                outgoing: outgoing
            )
        }
    }

    /// Cancels the active generation, if any. The assistant message's
    /// partial content is preserved and marked `.cancelled`. Per the
    /// brief, this cancels the actual network task but does not
    /// guarantee the provider itself stopped billing.
    func stopGeneration() {
        activeTask?.cancel()
    }

    /// Re-sends the last user turn in `conversationID` after a failure.
    /// Per the brief, retry is always explicit — never automatic.
    /// Removes the failed assistant message (and, if the *last* message
    /// is the matching user turn, does not duplicate it) before calling
    /// `send` again — from both the in-memory transcript and the
    /// repository.
    func retryLastTurn(in conversationID: UUID, using model: ModelInfo) {
        guard generationState == .idle else { return }
        var messages = self.messages(for: conversationID)
        guard let lastAssistant = messages.last, lastAssistant.role == .assistant else { return }
        guard case .failed = lastAssistant.status else { return }
        messages.removeLast()
        guard let lastUser = messages.last, lastUser.role == .user else { return }
        messages.removeLast()

        deleteAndPersist(lastAssistant.id, in: conversationID)
        deleteAndPersist(lastUser.id, in: conversationID)
        transcripts[conversationID] = messages

        send(text: lastUser.content, in: conversationID, using: model)
    }

    // MARK: - Private

    private func eligibleOutgoingMessages(for conversationID: UUID) -> [OutgoingChatMessage] {
        messages(for: conversationID)
            .filter(\.isEligibleForContext)
            .map { OutgoingChatMessage(role: $0.role, content: $0.content) }
    }

    private func runStream(
        client: ChatStreamingClient,
        apiKey: String,
        model: ModelInfo,
        conversationID: UUID,
        assistantMessageID: UUID,
        outgoing: [OutgoingChatMessage]
    ) async {
        generationState = .streaming(conversationID: conversationID)
        var deltasSinceCheckpoint = 0

        do {
            let stream = client.streamChatCompletion(apiKey: apiKey, modelID: model.modelID, messages: outgoing)
            for try await event in stream {
                if Task.isCancelled { break }
                if case .contentDelta = event {
                    deltasSinceCheckpoint += 1
                }
                apply(event, toMessage: assistantMessageID, in: conversationID)
                if deltasSinceCheckpoint >= checkpointInterval {
                    deltasSinceCheckpoint = 0
                    persistCurrentState(of: assistantMessageID, in: conversationID)
                }
            }
            if Task.isCancelled {
                markCancelled(assistantMessageID, in: conversationID)
            } else {
                markCompletedIfStillStreaming(assistantMessageID, in: conversationID)
                lastUsedService[conversationID] = model.service
            }
        } catch is CancellationError {
            markCancelled(assistantMessageID, in: conversationID)
        } catch let error as ChatRequestError {
            fail(assistantMessageID, in: conversationID, message: error.userMessage)
        } catch {
            fail(assistantMessageID, in: conversationID, message: error.localizedDescription)
        }

        generationState = .idle
        activeTask = nil
    }

    private func apply(_ event: ChatStreamEvent, toMessage messageID: UUID, in conversationID: UUID) {
        switch event {
        case .contentDelta(let text):
            update(messageID, in: conversationID) { $0.content += text }
        case .usage(let usage):
            update(messageID, in: conversationID) { $0.usage = usage }
        case .finished, .ignorable, .streamError:
            break
        }
    }

    private func markCancelled(_ messageID: UUID, in conversationID: UUID) {
        update(messageID, in: conversationID) { message in
            if message.status == .streaming { message.status = .cancelled }
        }
        persistCurrentState(of: messageID, in: conversationID)
    }

    private func markCompletedIfStillStreaming(_ messageID: UUID, in conversationID: UUID) {
        update(messageID, in: conversationID) { message in
            if message.status == .streaming { message.status = .completed }
        }
        persistCurrentState(of: messageID, in: conversationID)
    }

    private func fail(_ messageID: UUID, in conversationID: UUID, message errorMessage: String) {
        update(messageID, in: conversationID) { $0.status = .failed(errorMessage) }
        persistCurrentState(of: messageID, in: conversationID)
    }

    /// Applies `mutation` to the message with `messageID` in
    /// `conversationID`'s transcript, if it still exists. Scoping every
    /// update to both IDs together (rather than a single global "current
    /// streaming message" pointer) is what prevents a stale event from a
    /// superseded stream from ever mutating a different conversation's
    /// transcript.
    private func update(_ messageID: UUID, in conversationID: UUID, _ mutation: (inout TranscriptMessage) -> Void) {
        guard var messages = transcripts[conversationID] else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        mutation(&messages[index])
        transcripts[conversationID] = messages
    }

    private func appendAndPersist(_ message: TranscriptMessage, in conversationID: UUID) {
        transcripts[conversationID, default: []].append(message)
        loadedConversationIDs.insert(conversationID)
        guard let repository else { return }
        do {
            try repository.appendMessage(message, toConversation: conversationID)
        } catch {
            assertionFailure("Failed to persist new message \(message.id): \(error)")
        }
    }

    private func deleteAndPersist(_ messageID: UUID, in conversationID: UUID) {
        guard let repository else { return }
        do {
            try repository.deleteMessage(messageID, fromConversation: conversationID)
        } catch {
            assertionFailure("Failed to delete message \(messageID): \(error)")
        }
    }

    /// Writes the current in-memory state of one message to the
    /// repository. Used both for periodic mid-stream checkpoints and for
    /// the unconditional final write on every terminal status.
    private func persistCurrentState(of messageID: UUID, in conversationID: UUID) {
        guard let repository else { return }
        guard let message = transcripts[conversationID]?.first(where: { $0.id == messageID }) else { return }
        do {
            try repository.updateMessage(message, inConversation: conversationID)
        } catch {
            assertionFailure("Failed to checkpoint message \(messageID): \(error)")
        }
    }
}
