import Foundation

/// One decoded event from a chat completion SSE stream, after JSON
/// parsing but before any UI-facing interpretation.
///
/// This is intentionally a small, provider-agnostic shape. Both Venice
/// and OpenRouter emit OpenAI-compatible
/// `{"choices":[{"delta":{"content":...},"finish_reason":...}], "usage":...}`
/// chunks, so one decoder is shared — see `docs/DECISIONS.md` for why
/// this differs from the deliberately-NOT-shared model catalog decoders.
enum ChatStreamEvent: Equatable, Sendable {
    /// A content delta to append to the in-progress message.
    case contentDelta(String)
    /// The stream reported a normal finish reason (e.g. "stop",
    /// "length"). Does not itself end parsing — a usage-only accounting
    /// frame may still follow, per the brief.
    case finished(reason: String)
    /// A usage/accounting frame. May arrive alongside a `finished` chunk
    /// or as its own trailing chunk with an empty `choices` array.
    case usage(ChatUsage)
    /// A mid-stream error delivered inside an HTTP 200 response (Venice
    /// and OpenRouter both use OpenAI-compatible framing for this: a
    /// top-level `error` field alongside `choices[0].finish_reason ==
    /// "error"`). This must be treated as a failure, not a successful
    /// completion, even if it's the first and only event.
    case streamError(String)
    /// A chunk that decoded successfully but carried nothing actionable
    /// (e.g. an empty delta with no finish reason) — safe to ignore.
    case ignorable
}

/// Decodes one SSE `data:` payload string into a `ChatStreamEvent`.
///
/// Returns `nil` for `"[DONE]"` (the sentinel both providers send at the
/// very end of a stream) and for payloads that aren't valid JSON —
/// callers must not crash on either case; an invalid payload is treated
/// as "no event this frame," not a fatal error, per the brief's
/// requirement not to let a malformed frame crash the stream loop.
///
/// Cost decoding (Stage 6): a top-level `cost.usd` (Venice) or a
/// `usage.cost` number (OpenRouter, documented as "cost in credits") is
/// read alongside token usage, into `ChatUsage.costUSD`/`costCredits`
/// respectively — see `ChatUsage`'s doc comment for why these are
/// never merged into one field.
enum ChatStreamDecoder {
    static func decode(_ payload: String) -> ChatStreamEvent? {
        if payload == "[DONE]" {
            return nil
        }
        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let errorObject = json["error"] as? [String: Any] {
            let message = errorObject["message"] as? String ?? "The provider reported a stream error."
            return .streamError(message)
        }

        let choices = json["choices"] as? [[String: Any]] ?? []
        let firstChoice = choices.first

        // Content is checked before finish_reason: a chunk could in
        // principle carry trailing content alongside a finish reason, and
        // dropping that text would silently lose part of the response.
        if let delta = firstChoice?["delta"] as? [String: Any],
           let content = delta["content"] as? String,
           !content.isEmpty {
            return .contentDelta(content)
        }

        if let firstChoice, let finishReason = firstChoice["finish_reason"] as? String {
            return .finished(reason: finishReason)
        }

        if let usageObject = json["usage"] as? [String: Any] {
            // Venice: a top-level `cost: {usd, diem}` object, documented
            // sibling of `usage` on the non-streaming response; treated
            // the same way if present on a streaming frame. OpenRouter:
            // `usage.cost`, documented as "Cost in credits" — never
            // assumed to equal USD (see ChatUsage's doc comment).
            let veniceCostObject = json["cost"] as? [String: Any]
            let costUSD = ModelCatalogDecoding.decimal(veniceCostObject?["usd"])
            let costCredits = ModelCatalogDecoding.decimal(usageObject["cost"])
            return .usage(
                ChatUsage(
                    promptTokens: ModelCatalogDecoding.int(usageObject["prompt_tokens"]),
                    completionTokens: ModelCatalogDecoding.int(usageObject["completion_tokens"]),
                    totalTokens: ModelCatalogDecoding.int(usageObject["total_tokens"]),
                    costUSD: costUSD,
                    costCredits: costCredits
                )
            )
        }

        return .ignorable
    }
}
