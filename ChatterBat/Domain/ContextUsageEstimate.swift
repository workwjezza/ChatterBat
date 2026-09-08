import Foundation

/// A rough, honestly-labeled estimate of how much of a model's context
/// window the *next* request would use.
///
/// This is deliberately not a token count. ChatterBat has no access to
/// any provider's actual tokenizer, and the brief is explicit that
/// unknown/estimated values must never be presented as if they were
/// provider-authoritative. `estimatedTokens` here uses a widely-cited,
/// clearly-documented rough heuristic (~4 characters per token for
/// English text) purely to give a ballpark sense of scale — never
/// displayed without an "estimated" qualifier, and never used to make
/// an automatic decision (e.g. auto-truncating history) on the user's
/// behalf.
struct ContextUsageEstimate: Equatable, Sendable {
    let messageCount: Int
    let characterCount: Int
    let estimatedTokens: Int
    /// `nil` when the selected model's context length isn't known —
    /// per the brief, unknown must never be displayed as 0% or 100%.
    let percentOfContextWindow: Double?

    private static let charactersPerEstimatedToken = 4

    static func estimate(for messages: [OutgoingChatMessage], contextLength: Int?) -> ContextUsageEstimate {
        let characterCount = messages.reduce(0) { $0 + $1.content.count }
        let estimatedTokens = characterCount / charactersPerEstimatedToken
        let percent: Double? = {
            guard let contextLength, contextLength > 0 else { return nil }
            return (Double(estimatedTokens) / Double(contextLength)) * 100
        }()
        return ContextUsageEstimate(
            messageCount: messages.count,
            characterCount: characterCount,
            estimatedTokens: estimatedTokens,
            percentOfContextWindow: percent
        )
    }
}
