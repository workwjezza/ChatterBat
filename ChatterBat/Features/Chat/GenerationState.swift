import Foundation

/// State of one conversation's turn, including bounded FIFO admission.
enum GenerationState: Equatable, Sendable {
    case idle
    case queued(conversationID: UUID)
    case connecting(conversationID: UUID)
    case streaming(conversationID: UUID)
    case cancelling(conversationID: UUID)
    /// Stage 7: the model requested a read-only agent tool and
    /// generation is paused, waiting for the user to explicitly
    /// approve or deny it — see `ChatCoordinator.pendingToolApproval`.
    /// Holds a concurrency slot until approved, denied or cancelled.
    case awaitingToolApproval(conversationID: UUID)

    var activeConversationID: UUID? {
        switch self {
        case .idle: return nil
        case .queued(let id), .connecting(let id), .streaming(let id), .awaitingToolApproval(let id), .cancelling(let id): return id
        }
    }

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .queued: return "Queued"
        case .connecting: return "Starting / resolving tool"
        case .streaming: return "Generating"
        case .awaitingToolApproval: return "Waiting for approval"
        case .cancelling: return "Stopping"
        }
    }
}
