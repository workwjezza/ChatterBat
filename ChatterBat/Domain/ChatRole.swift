import Foundation

/// A chat message's role, matching the OpenAI-compatible convention both
/// Venice and OpenRouter use.
///
/// `.tool` was added in Stage 7 for the permission-controlled agent
/// tools beta: it's used both as an `OutgoingChatMessage` role (a tool
/// result fed back to the provider) and as a `TranscriptMessage` role
/// (a permanent, visible audit-trail entry recording that a tool was
/// requested and what happened — see `TranscriptMessage.isEligibleForContext`,
/// which always excludes `.tool` messages from future-turn context).
enum ChatRole: String, Hashable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// One tool call the model requested, in the exact shape both Venice
/// and OpenRouter expect when it's echoed back inside an assistant
/// message on a follow-up request (`{"id", "type": "function",
/// "function": {"name", "arguments"}}`).
struct OutgoingToolCall: Hashable, Sendable {
    let id: String
    let name: String
    /// Raw JSON text, exactly as accumulated from the model's own
    /// streamed argument fragments — passed through verbatim, never
    /// re-serialized, so the provider sees back precisely what its own
    /// model produced.
    let argumentsJSON: String
}

/// A message ready to send in a request body: role + text content, plus
/// the two Stage 7 additions needed to complete a tool-calling round
/// trip: `toolCalls` (only meaningful on an `.assistant` message that
/// is replaying a prior tool request) and `toolCallID` (only meaningful
/// on a `.tool` message, identifying which call this is the result
/// of).
///
/// Distinct from `TranscriptMessage` (the richer, UI-facing, in-progress
/// message with status/attribution/usage). This is the minimal shape a
/// provider request needs. Both new fields default to empty/`nil` so
/// every pre-Stage-7 call site (`OutgoingChatMessage(role:content:)`)
/// keeps compiling and behaving identically.
struct OutgoingChatMessage: Hashable, Sendable {
    let role: ChatRole
    let content: String
    var toolCalls: [OutgoingToolCall] = []
    var toolCallID: String? = nil
}
