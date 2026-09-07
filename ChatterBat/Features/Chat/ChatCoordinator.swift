import Foundation
import Observation

/// Owns in-memory conversation transcripts and drives streaming chat
/// requests.
///
/// Stage 3 has no persistence yet (that's Stage 4) — transcripts live
/// only in memory here, keyed by conversation ID. Per the brief, only one
/// generation is active globally; `send` rejects a new send while
/// `generationState` is not `.idle`.
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
    private var activeTask: Task<Void, Never>?

    init(credentialStore: CredentialStore, clients: [AIService: ChatStreamingClient]) {
        self.credentialStore = credentialStore
        self.clients = clients
    }

    func messages(for conversationID: UUID) -> [TranscriptMessage] {
        transcripts[conversationID] ?? []
    }

    /// Whether sending the next message to `model.service` would share
    /// this conversation's existing history with a *different* service
    /// than the one that has received it so far. Per the brief, callers
    /// must surface this before sending, not send silently.
    func wouldShareHistoryAcrossServices(conversationID: UUID, nextService: AIService) -> Bool {
        guard let previous = lastUsedService[conversationID] else { return false }
        return previous != nextService && !(transcripts[conversationID] ?? []).isEmpty
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

        transcripts[conversationID, default: []].append(userMessage)
        transcripts[conversationID, default: []].append(assistantMessage)
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
    /// `send` again.
    func retryLastTurn(in conversationID: UUID, using model: ModelInfo) {
        guard generationState == .idle else { return }
        var messages = transcripts[conversationID] ?? []
        guard let lastAssistant = messages.last, lastAssistant.role == .assistant else { return }
        guard case .failed = lastAssistant.status else { return }
        messages.removeLast()
        guard let lastUser = messages.last, lastUser.role == .user else { return }
        messages.removeLast()
        transcripts[conversationID] = messages
        send(text: lastUser.content, in: conversationID, using: model)
    }

    // MARK: - Private

    private func eligibleOutgoingMessages(for conversationID: UUID) -> [OutgoingChatMessage] {
        (transcripts[conversationID] ?? [])
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

        do {
            let stream = client.streamChatCompletion(apiKey: apiKey, modelID: model.modelID, messages: outgoing)
            for try await event in stream {
                if Task.isCancelled { break }
                apply(event, toMessage: assistantMessageID, in: conversationID)
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
    }

    private func markCompletedIfStillStreaming(_ messageID: UUID, in conversationID: UUID) {
        update(messageID, in: conversationID) { message in
            if message.status == .streaming { message.status = .completed }
        }
    }

    private func fail(_ messageID: UUID, in conversationID: UUID, message errorMessage: String) {
        update(messageID, in: conversationID) { $0.status = .failed(errorMessage) }
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
}
