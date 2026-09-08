import Foundation

/// Global generation state.
///
/// Per the brief: "Support one active generation globally in the MVP;
/// this is simpler and should be communicated in the UI." Only one
/// conversation can be actively generating at a time; `ChatCoordinator`
/// rejects a new send while this is anything but `.idle`.
enum GenerationState: Equatable, Sendable {
    case idle
    case connecting(conversationID: UUID)
    case streaming(conversationID: UUID)
    /// Stage 7: the model requested a read-only agent tool and
    /// generation is paused, waiting for the user to explicitly
    /// approve or deny it — see `ChatCoordinator.pendingToolApproval`.
    /// Counts as "active" for the single-global-generation-slot rule
    /// (a new send elsewhere is still rejected while this is pending),
    /// consistent with the brief's "no automatic retries/no silent
    /// scope expansion" — the turn genuinely isn't finished yet.
    case awaitingToolApproval(conversationID: UUID)

    var activeConversationID: UUID? {
        switch self {
        case .idle: return nil
        case .connecting(let id), .streaming(let id), .awaitingToolApproval(let id): return id
        }
    }
}
