import Foundation

/// Status of one transcript message, mirroring the generation lifecycle
/// described in the brief: "idle, connecting, streaming, completed,
/// cancelled, failed, interrupted."
enum MessageStatus: Hashable, Sendable {
    case streaming
    case completed
    /// User pressed Stop. Content up to that point is preserved and
    /// visibly marked, per the brief — this is not the same as `.failed`.
    case cancelled
    case failed(String)
    /// Set on relaunch for a message that was still `.streaming` when the
    /// app last quit. Stage 3 has no persistence yet, so this value is
    /// unused today but is defined now so Stage 4's repository has a
    /// matching status to write on load, per the brief's requirement that
    /// unfinished generations become `.interrupted`, not still streaming.
    case interrupted
    /// Stage 7: a `.tool`-role message is waiting for the user's
    /// explicit approve/deny decision — see `ChatCoordinator.provideToolResult`.
    /// Never automatically resolved; a message left in this state at
    /// quit is rewritten to `.interrupted` at next launch, the same
    /// way `.streaming` is (see `ConversationRepository.interruptAllStreamingMessages`).
    case awaitingApproval
    /// Stage 7: the model requested a tool call and the user explicitly
    /// declined it (or dismissed the approval sheet, or cancelled the
    /// picker after approving the *request*). Distinct from `.failed`
    /// — nothing went wrong; the user made a deliberate choice, and
    /// that choice is preserved visibly rather than looking like an
    /// error.
    case toolDenied
}

/// A permanent, visible record of one agent-tool invocation — Stage 7.
/// Attached to a `.tool`-role `TranscriptMessage` so the transcript is
/// an honest, permanent audit trail of every tool ChatterBat ever
/// asked to run and what the user decided, never a hidden call.
struct ToolInvocationRecord: Identifiable, Hashable, Sendable {
    let tool: AgentTool
    let toolCallID: String
    /// The model's own stated reason for wanting this tool (from its
    /// `reason` argument) — shown to the user verbatim at approval
    /// time and preserved here afterward for the permanent record.
    let modelStatedReason: String
    /// `nil` while awaiting approval. Once decided: the file/directory
    /// name the user actually picked via the native panel (never a
    /// full path — see `AgentToolExecutor`'s doc comment on why only
    /// the last path component is ever shown or sent to the model),
    /// or `nil` if the user denied or cancelled the panel.
    var approvedItemName: String?

    /// Conforms to `Identifiable` (keyed on the tool call's own ID,
    /// which is already unique) purely so SwiftUI's `.sheet(item:)`
    /// can present the approval sheet directly from this value.
    var id: String { toolCallID }
}

/// One message in a conversation's in-memory transcript.
///
/// This is the Stage 3 in-memory shape. Stage 4 persists an equivalent
/// shape via SwiftData; this type intentionally has no persistence
/// concerns of its own.
struct TranscriptMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    var status: MessageStatus
    /// The exact service/model that produced (or is producing) this
    /// message. `nil` for user messages, which have no attribution.
    var attribution: ModelIdentity?
    var usage: ChatUsage?
    /// Non-`nil` only for `.tool`-role messages — see
    /// `ToolInvocationRecord`'s doc comment.
    var toolInvocation: ToolInvocationRecord?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        status: MessageStatus,
        attribution: ModelIdentity? = nil,
        usage: ChatUsage? = nil,
        toolInvocation: ToolInvocationRecord? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
        self.attribution = attribution
        self.usage = usage
        self.toolInvocation = toolInvocation
    }

    /// Whether this message's content is eligible to be included as
    /// context in a future request to the same service.
    ///
    /// Per the brief: exclude failed-empty assistant messages; cancelled
    /// partial output requires explicit choice (not automatically
    /// included) — modeled here as *not* eligible by default so a caller
    /// must deliberately opt a cancelled message back in if ever desired.
    var isEligibleForContext: Bool {
        // .tool messages are never replayed as ordinary context on a
        // later turn — the one-shot round trip that needs the actual
        // structured tool_calls/tool-result exchange is built directly
        // by ChatCoordinator for that immediate follow-up request, not
        // reconstructed from persisted transcript history. Per the
        // brief's context-eligibility rules generalized to Stage 7: a
        // tool record is an audit-trail entry for the human, not
        // conversational content to feed back to the model later.
        guard role != .tool else { return false }
        switch status {
        case .completed:
            return true
        case .streaming, .cancelled, .interrupted, .toolDenied, .awaitingApproval:
            return false
        case .failed:
            return !content.isEmpty
        }
    }
}
