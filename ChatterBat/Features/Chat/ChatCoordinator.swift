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
    /// Cached context boundaries, keyed by conversation ID. The value
    /// itself is `UUID?` (so the dictionary entry is `UUID??`) so that
    /// "boundary explicitly cleared to full-history" (cached as
    /// `.some(nil)`) is distinguishable from "never loaded from the
    /// repository yet" (no entry at all) — a plain `[UUID: UUID]`
    /// cannot represent that distinction, since assigning `nil` would
    /// remove the entry instead of caching "no boundary."
    private var contextBoundaries: [UUID: UUID?] = [:]
    /// Checkpoint the streaming assistant message to the repository
    /// every this many content-delta events, rather than on every single
    /// one, per the brief's "not on every token" guidance. A value of 1
    /// would checkpoint every delta; tests use that to verify
    /// checkpointing happens at all without waiting for a large volume
    /// of deltas.
    private let checkpointInterval: Int
    /// Stage 7: how the app presents the native panel a user picks a
    /// file/folder through — real `NSOpenPanel` in production,
    /// scripted in tests. Injected (rather than hard-coded to the
    /// real presenter) so `ChatCoordinator`'s agent-tools tests never
    /// pop a real system panel, per the brief's testing contract.
    private let toolPanelPresenter: AgentToolPanelPresenting
    /// Per-conversation state for an in-progress agent-tools round
    /// trip — see `ActiveToolContext`'s doc comment. Only ever
    /// non-`nil` while `generationState` for that conversation is
    /// `.streaming` (mid-tool-call-round) or `.awaitingToolApproval`.
    private var activeToolContexts: [UUID: ActiveToolContext] = [:]
    /// Defensive cap on how many tool-call round trips one turn may
    /// make before ChatterBat stops offering tools and forces a final
    /// answer. This is *not* the safety mechanism Stage 7 relies on —
    /// every single round trip already requires its own explicit user
    /// approval regardless of this cap — it exists only to bound how
    /// long a fully-cooperative user clicking "Approve" repeatedly
    /// could keep one turn going.
    private let maxToolCallsPerTurn = 4

    init(
        credentialStore: CredentialStore,
        clients: [AIService: ChatStreamingClient],
        repository: ConversationRepository? = nil,
        checkpointInterval: Int = 20,
        toolPanelPresenter: AgentToolPanelPresenting = AgentToolPanelPresenter()
    ) {
        self.credentialStore = credentialStore
        self.clients = clients
        self.repository = repository
        self.checkpointInterval = max(1, checkpointInterval)
        self.toolPanelPresenter = toolPanelPresenter
    }

    /// Per-turn agent-tools state, kept only in memory (never
    /// persisted — a `.tool` message left `awaitingApproval` at quit
    /// becomes `.interrupted` on relaunch rather than silently
    /// resuming, exactly like an interrupted `.streaming` message).
    private struct ActiveToolContext {
        let model: ModelInfo
        let settings: AdvancedChatSettings
        let tools: [AgentTool]
        let assistantMessageID: UUID
        /// The exact message list already sent so far this turn —
        /// grows by one assistant/tool pair per approved round. This
        /// is what makes the tool-calling round trip work without
        /// ever reconstructing `tool_calls`/tool-result messages from
        /// persisted transcript history (see
        /// `TranscriptMessage.isEligibleForContext`'s doc comment).
        var outgoingSoFar: [OutgoingChatMessage]
        var pendingCall: OutgoingToolCall?
        var toolMessageID: UUID?
        /// The assistant message's own content at the moment it
        /// requested `pendingCall` — needed to correctly replay that
        /// assistant turn (content + `tool_calls`) on the follow-up
        /// request.
        var assistantContentAtCallTime: String = ""
        var roundCount: Int = 0
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

    /// The message ID (if any) marking where this conversation's sent
    /// context currently starts — see `setContextBoundary`'s doc
    /// comment. `nil` means "full history."
    func contextBoundaryMessageID(for conversationID: UUID) -> UUID? {
        if let cachedEntry = contextBoundaries[conversationID] {
            return cachedEntry
        }
        guard let repository else { return nil }
        do {
            let loaded = try repository.contextBoundaryMessageID(for: conversationID)
            contextBoundaries[conversationID] = loaded
            return loaded
        } catch {
            assertionFailure("Failed to load context boundary for \(conversationID): \(error)")
            return nil
        }
    }

    /// Sets a "start context here" boundary: messages at or after
    /// `messageID` are still shown in full in the transcript (nothing
    /// is deleted or hidden), but only those messages are sent as
    /// context to the provider on future turns. Per the brief's
    /// context-management requirement, this is always an explicit,
    /// visible user action — never automatic truncation.
    ///
    /// Passing `nil` clears the boundary, restoring full history as
    /// context.
    func setContextBoundary(_ messageID: UUID?, in conversationID: UUID) {
        // `updateValue(_:forKey:)` makes the intent unambiguous on a
        // `[UUID: UUID?]` dictionary: it always sets the entry to
        // `messageID` (even when `messageID` is `nil`), rather than
        // relying on subscript-assignment's optional-promotion
        // behavior to avoid accidentally *removing* the entry — which
        // would defeat the point of caching "explicitly cleared" as
        // distinct from "never loaded from the repository."
        contextBoundaries.updateValue(messageID, forKey: conversationID)
        guard let repository else { return }
        do {
            try repository.setContextBoundary(messageID, forConversation: conversationID)
        } catch {
            assertionFailure("Failed to persist context boundary for \(conversationID): \(error)")
        }
    }

    /// An estimate (never authoritative — see `ContextUsageEstimate`)
    /// of how much of `model`'s context window the *next* send would
    /// use, given the current transcript and context boundary.
    func contextUsageEstimate(for conversationID: UUID, model: ModelInfo) -> ContextUsageEstimate {
        ContextUsageEstimate.estimate(for: eligibleOutgoingMessages(for: conversationID), contextLength: model.contextLength)
    }

    /// Sends `text` as a new user turn in `conversationID` using `model`.
    /// No-ops if a generation is already active anywhere in the app, or
    /// if `text` is empty after trimming — callers should disable Send in
    /// those cases, but this guards against a duplicate/racy invocation
    /// regardless.
    ///
    /// `settings` is narrowed to what actually applies to `model` via
    /// `AdvancedChatSettings.applicable(to:)` before being sent — see
    /// that method's doc comment for why unknown capability support is
    /// treated as unsupported for this purpose.
    ///
    /// `tools` (Stage 7, defaults to `[]` — no pre-Stage-7 call site
    /// needed to change) is offered to the model only when
    /// `model.supportsTools == .supported` — the same "unknown is
    /// treated as unsupported for request-safety" posture
    /// `AdvancedChatSettings.applicable(to:)` already uses, applied
    /// here to tools instead. Every individual tool call the model
    /// then requests still pauses for the user's explicit approval —
    /// see `pendingToolApproval(for:)`/`respondToToolApproval(in:approve:)`
    /// — this parameter only controls whether tools are *offered* at
    /// all, never whether one runs unapproved.
    func send(
        text: String,
        in conversationID: UUID,
        using model: ModelInfo,
        settings: AdvancedChatSettings = AdvancedChatSettings(),
        tools: [AgentTool] = []
    ) {
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
        let applicableSettings = settings.applicable(to: model)
        let applicableTools = model.supportsTools == .supported ? tools : []

        appendAndPersist(userMessage, in: conversationID)
        appendAndPersist(assistantMessage, in: conversationID)
        generationState = .connecting(conversationID: conversationID)
        activeToolContexts[conversationID] = nil

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
                outgoing: outgoing,
                settings: applicableSettings,
                tools: applicableTools
            )
        }
    }

    /// Cancels the active generation, if any. The assistant message's
    /// partial content is preserved and marked `.cancelled`. Per the
    /// brief, this cancels the actual network task but does not
    /// guarantee the provider itself stopped billing.
    ///
    /// Stage 7: while a tool approval is pending (no network task is
    /// active at that point — see `pendingToolApproval(for:)`),
    /// Stop/Escape instead denies that pending tool call, so the
    /// button is never a dead no-op while the approval sheet is
    /// showing.
    func stopGeneration() {
        if case .awaitingToolApproval(let conversationID) = generationState {
            respondToToolApproval(in: conversationID, approve: false)
            return
        }
        activeTask?.cancel()
    }

    /// The tool call currently awaiting the user's explicit
    /// approve/deny decision in `conversationID`, or `nil` if none.
    /// Drives the approval sheet — see `AgentToolApprovalView`.
    func pendingToolApproval(for conversationID: UUID) -> ToolInvocationRecord? {
        guard case .awaitingToolApproval(let activeConversationID) = generationState, activeConversationID == conversationID else {
            return nil
        }
        guard let toolMessageID = activeToolContexts[conversationID]?.toolMessageID else { return nil }
        return messages(for: conversationID).first { $0.id == toolMessageID }?.toolInvocation
    }

    /// Resolves the currently-pending tool approval for
    /// `conversationID` (a no-op if none is pending, or if
    /// `conversationID` isn't the one currently awaiting approval).
    ///
    /// `approve: true` runs `AgentToolExecutor`, which presents the
    /// native panel and only reads whatever the user then actually
    /// picks there — a second, independent point of user control
    /// beyond this call. `approve: false` never touches the
    /// filesystem. Either way (including a cancelled panel, or a real
    /// read failure), the outcome is fed back to the model as the
    /// tool's result content — never silently swallowed — so the
    /// model can respond honestly (e.g. explain it couldn't read the
    /// file, or continue without it).
    func respondToToolApproval(in conversationID: UUID, approve: Bool) {
        guard case .awaitingToolApproval(let activeConversationID) = generationState, activeConversationID == conversationID else {
            return
        }
        guard
            let context = activeToolContexts[conversationID],
            let pendingCall = context.pendingCall,
            let toolMessageID = context.toolMessageID,
            let tool = AgentTool(rawValue: pendingCall.name)
        else { return }

        activeTask = Task { [weak self] in
            await self?.resolveToolApproval(
                approve: approve,
                tool: tool,
                pendingCall: pendingCall,
                toolMessageID: toolMessageID,
                conversationID: conversationID
            )
        }
    }

    /// Re-sends the last user turn in `conversationID` after a failure.
    /// Per the brief, retry is always explicit — never automatic.
    /// Removes the failed assistant message (and, if the *last* message
    /// is the matching user turn, does not duplicate it) before calling
    /// `send` again — from both the in-memory transcript and the
    /// repository.
    func retryLastTurn(
        in conversationID: UUID,
        using model: ModelInfo,
        settings: AdvancedChatSettings = AdvancedChatSettings(),
        tools: [AgentTool] = []
    ) {
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

        send(text: lastUser.content, in: conversationID, using: model, settings: settings, tools: tools)
    }

    // MARK: - Private

    /// Messages eligible to be sent as context for the next turn: all
    /// context-eligible messages (per `TranscriptMessage.isEligibleForContext`),
    /// further restricted to those at or after this conversation's
    /// context boundary, if one is set — see `setContextBoundary`.
    private func eligibleOutgoingMessages(for conversationID: UUID) -> [OutgoingChatMessage] {
        let all = messages(for: conversationID)
        let fromBoundary: [TranscriptMessage] = {
            guard let boundaryID = contextBoundaryMessageID(for: conversationID) else { return all }
            guard let boundaryIndex = all.firstIndex(where: { $0.id == boundaryID }) else { return all }
            return Array(all[boundaryIndex...])
        }()
        return fromBoundary
            .filter(\.isEligibleForContext)
            .map { OutgoingChatMessage(role: $0.role, content: $0.content) }
    }

    private func runStream(
        client: ChatStreamingClient,
        apiKey: String,
        model: ModelInfo,
        conversationID: UUID,
        assistantMessageID: UUID,
        outgoing: [OutgoingChatMessage],
        settings: AdvancedChatSettings,
        tools: [AgentTool],
        roundCount: Int = 0
    ) async {
        generationState = .streaming(conversationID: conversationID)
        var deltasSinceCheckpoint = 0
        // Stage 7: accumulated tool-call fragments — see
        // `ChatStreamEvent.toolCallDelta`'s doc comment on why only
        // one in-flight call (index 0) needs tracking here.
        var pendingCallID: String?
        var pendingCallName: String?
        var pendingCallArguments = ""
        var didRequestTool = false

        do {
            let stream = client.streamChatCompletion(apiKey: apiKey, modelID: model.modelID, messages: outgoing, settings: settings, tools: tools)
            for try await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .contentDelta:
                    deltasSinceCheckpoint += 1
                    apply(event, toMessage: assistantMessageID, in: conversationID)
                case .toolCallDelta(_, let id, let name, let argumentsFragment):
                    didRequestTool = true
                    if let id { pendingCallID = id }
                    if let name { pendingCallName = name }
                    pendingCallArguments += argumentsFragment
                default:
                    apply(event, toMessage: assistantMessageID, in: conversationID)
                }
                if deltasSinceCheckpoint >= checkpointInterval {
                    deltasSinceCheckpoint = 0
                    persistCurrentState(of: assistantMessageID, in: conversationID)
                }
            }
            if Task.isCancelled {
                markCancelled(assistantMessageID, in: conversationID)
            } else if didRequestTool, let callName = pendingCallName {
                handleToolCallRequested(
                    callID: pendingCallID ?? UUID().uuidString,
                    callName: callName,
                    argumentsJSON: pendingCallArguments,
                    model: model,
                    settings: settings,
                    tools: tools,
                    conversationID: conversationID,
                    assistantMessageID: assistantMessageID,
                    outgoing: outgoing,
                    roundCount: roundCount
                )
                return
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
        activeToolContexts[conversationID] = nil
    }

    private func apply(_ event: ChatStreamEvent, toMessage messageID: UUID, in conversationID: UUID) {
        switch event {
        case .contentDelta(let text):
            update(messageID, in: conversationID) { $0.content += text }
        case .usage(let usage):
            update(messageID, in: conversationID) { $0.usage = usage }
        case .finished, .ignorable, .streamError, .toolCallDelta:
            break
        }
    }

    /// Called once a stream ends having requested a tool call. Leaves
    /// the assistant message's own status as `.streaming` (its
    /// content — if any accompanying text preceded the call — is
    /// preserved as-is) and appends a new `.tool`-role message
    /// carrying a `ToolInvocationRecord` in `.awaitingApproval` status
    /// — the permanent, visible record of what's being asked, shown
    /// before any decision is made, per the brief's "every tool
    /// invocation must be visible... before it runs."
    private func handleToolCallRequested(
        callID: String,
        callName: String,
        argumentsJSON: String,
        model: ModelInfo,
        settings: AdvancedChatSettings,
        tools: [AgentTool],
        conversationID: UUID,
        assistantMessageID: UUID,
        outgoing: [OutgoingChatMessage],
        roundCount: Int
    ) {
        let reason = Self.extractReason(fromArgumentsJSON: argumentsJSON)
        let toolInvocation: ToolInvocationRecord
        if let tool = AgentTool(rawValue: callName) {
            toolInvocation = ToolInvocationRecord(tool: tool, toolCallID: callID, modelStatedReason: reason)
        } else {
            // The model named a tool ChatterBat never offered it —
            // treat this the same as a denial rather than guessing
            // what it meant; nothing is ever run for an unrecognized
            // tool name.
            toolInvocation = ToolInvocationRecord(tool: .readFile, toolCallID: callID, modelStatedReason: reason)
        }
        // The assistant message's own turn ends here — it requested a
        // tool rather than a final answer, so it's marked completed
        // now with whatever text (often none) preceded the request.
        // The tool call itself lives entirely in the new `.tool`
        // message appended below, per the brief's requirement that
        // the invocation be its own visible, separate record.
        markCompletedIfStillStreaming(assistantMessageID, in: conversationID)

        let toolMessage = TranscriptMessage(
            role: .tool,
            content: "",
            status: .awaitingApproval,
            toolInvocation: toolInvocation
        )
        appendAndPersist(toolMessage, in: conversationID)

        let assistantContent = messages(for: conversationID).first { $0.id == assistantMessageID }?.content ?? ""
        activeToolContexts[conversationID] = ActiveToolContext(
            model: model,
            settings: settings,
            tools: tools,
            assistantMessageID: assistantMessageID,
            outgoingSoFar: outgoing,
            pendingCall: OutgoingToolCall(id: callID, name: callName, argumentsJSON: argumentsJSON),
            toolMessageID: toolMessage.id,
            assistantContentAtCallTime: assistantContent,
            roundCount: roundCount
        )

        guard AgentTool(rawValue: callName) != nil else {
            // The model asked for a tool name ChatterBat never
            // offered it — there is nothing valid to show an approval
            // sheet for, so this is resolved immediately (no approval
            // step, since nothing runnable was ever proposed) rather
            // than left waiting on a decision that can't be made.
            let pendingCall = OutgoingToolCall(id: callID, name: callName, argumentsJSON: argumentsJSON)
            let message = "ChatterBat doesn't offer a tool named \"\(callName)\"."
            update(toolMessage.id, in: conversationID) { transcript in
                transcript.status = .toolDenied
                transcript.content = message
            }
            persistCurrentState(of: toolMessage.id, in: conversationID)
            activeTask = Task { [weak self] in
                await self?.continueAfterToolOutcome(
                    resultText: message,
                    pendingCall: pendingCall,
                    conversationID: conversationID
                )
            }
            return
        }

        generationState = .awaitingToolApproval(conversationID: conversationID)
        activeTask = nil
    }

    /// Executes (or denies) the pending tool call, records the
    /// outcome permanently on the `.tool` message, and — unless the
    /// round cap was hit — sends a follow-up request replaying the
    /// assistant's tool request and this result, so the model can
    /// produce its actual answer (or request another tool, which
    /// loops back through this same approval flow).
    private func resolveToolApproval(
        approve: Bool,
        tool: AgentTool,
        pendingCall: OutgoingToolCall,
        toolMessageID: UUID,
        conversationID: UUID
    ) async {
        let outcome: AgentToolExecutionResult = approve
            ? await AgentToolExecutor.run(tool, using: toolPanelPresenter)
            : .cancelled

        let resultText: String
        switch outcome {
        case .success(let itemName, let resultTextValue):
            update(toolMessageID, in: conversationID) { message in
                message.status = .completed
                message.content = resultTextValue
                message.toolInvocation?.approvedItemName = itemName
            }
            resultText = resultTextValue
        case .cancelled:
            let reason = approve ? "The user cancelled the file/folder picker." : "The user denied this tool request."
            update(toolMessageID, in: conversationID) { message in
                message.status = .toolDenied
                message.content = reason
            }
            resultText = reason
        case .failure(let errorMessage):
            update(toolMessageID, in: conversationID) { message in
                message.status = .completed
                message.content = errorMessage
            }
            resultText = errorMessage
        }
        persistCurrentState(of: toolMessageID, in: conversationID)

        await continueAfterToolOutcome(resultText: resultText, pendingCall: pendingCall, conversationID: conversationID)
    }

    /// Shared continuation after a tool result (of any kind — a real
    /// read, a denial, an unrecognized tool name) is known: builds
    /// and sends the follow-up request replaying the assistant's tool
    /// request and this result, so the model can respond.
    private func continueAfterToolOutcome(resultText: String, pendingCall: OutgoingToolCall, conversationID: UUID) async {
        guard let context = activeToolContexts[conversationID] else { return }

        let nextRoundCount = context.roundCount + 1
        let nextOutgoing = context.outgoingSoFar + [
            OutgoingChatMessage(
                role: .assistant,
                content: context.assistantContentAtCallTime,
                toolCalls: [pendingCall]
            ),
            OutgoingChatMessage(role: .tool, content: resultText, toolCallID: pendingCall.id)
        ]
        // The follow-up gets its own new assistant message in the
        // transcript — the original assistant message already ended
        // (marked `.completed`) when the tool was requested.
        let nextAssistantMessage = TranscriptMessage(
            role: .assistant,
            content: "",
            status: .streaming,
            attribution: context.model.identity
        )
        appendAndPersist(nextAssistantMessage, in: conversationID)

        guard
            let key = (try? credentialStore.loadKey(for: context.model.service)) ?? nil,
            let client = clients[context.model.service]
        else {
            fail(nextAssistantMessage.id, in: conversationID, message: "No API key configured for \(context.model.service.displayName). Connect it in Settings → Accounts.")
            generationState = .idle
            activeToolContexts[conversationID] = nil
            return
        }

        // Round cap reached: stop offering tools on the next request
        // so the model is forced toward a final answer instead of
        // looping indefinitely — every round up to this point still
        // required its own explicit approval, so this is a bound on
        // *duration*, not a bypass of the approval requirement.
        let offeredTools = nextRoundCount >= maxToolCallsPerTurn ? [] : context.tools

        await runStream(
            client: client,
            apiKey: key,
            model: context.model,
            conversationID: conversationID,
            assistantMessageID: nextAssistantMessage.id,
            outgoing: nextOutgoing,
            settings: context.settings,
            tools: offeredTools,
            roundCount: nextRoundCount
        )
    }

    /// Extracts the model-supplied `reason` argument from a tool
    /// call's raw JSON arguments string, or a fallback string if the
    /// arguments aren't valid JSON / don't contain that field — never
    /// crashes on malformed model output.
    private static func extractReason(fromArgumentsJSON json: String) -> String {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let reason = object["reason"] as? String,
            !reason.isEmpty
        else {
            return "No reason given."
        }
        return reason
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
