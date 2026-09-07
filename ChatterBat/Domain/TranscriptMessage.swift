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

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        status: MessageStatus,
        attribution: ModelIdentity? = nil,
        usage: ChatUsage? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
        self.attribution = attribution
        self.usage = usage
    }

    /// Whether this message's content is eligible to be included as
    /// context in a future request to the same service.
    ///
    /// Per the brief: exclude failed-empty assistant messages; cancelled
    /// partial output requires explicit choice (not automatically
    /// included) — modeled here as *not* eligible by default so a caller
    /// must deliberately opt a cancelled message back in if ever desired.
    var isEligibleForContext: Bool {
        switch status {
        case .completed:
            return true
        case .streaming, .cancelled, .interrupted:
            return false
        case .failed:
            return !content.isEmpty
        }
    }
}
