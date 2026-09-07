import Foundation

/// A chat message's role, matching the OpenAI-compatible convention both
/// Venice and OpenRouter use.
enum ChatRole: String, Hashable, Sendable {
    case system
    case user
    case assistant
}

/// A message ready to send in a request body: just role + text content.
///
/// Distinct from `TranscriptMessage` (the richer, UI-facing, in-progress
/// message with status/attribution/usage). This is the minimal shape a
/// provider request needs.
struct OutgoingChatMessage: Hashable, Sendable {
    let role: ChatRole
    let content: String
}
