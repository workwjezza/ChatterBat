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

    var activeConversationID: UUID? {
        switch self {
        case .idle: return nil
        case .connecting(let id), .streaming(let id): return id
        }
    }
}
