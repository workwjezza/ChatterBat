import Foundation

/// Provider-reported token usage for one completion.
///
/// Per the brief: "Provider-reported usage is authoritative when
/// supplied. Missing usage is unknown, not zero." All fields are
/// optional for exactly that reason — a `nil` field must never be
/// displayed as `0`.
///
/// Cost is deliberately kept in two distinct, never-conflated fields
/// rather than one generic "cost" number:
/// - Venice's non-streaming response documents a top-level `cost.usd`
///   sibling to `usage` — an actual USD amount.
/// - OpenRouter's `usage.cost` field is documented as "Cost in
///   credits," not asserted anywhere in OpenRouter's docs to equal USD
///   1:1 (verified during Stage 6 research: no OpenRouter
///   documentation page states a credit/USD exchange rate). Treating
///   it as USD would misrepresent actual spend, so it is stored and
///   displayed as "credits," explicitly united, never merged with
///   `costUSD`.
struct ChatUsage: Hashable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    /// Venice-reported cost in US dollars for this completion, or
    /// `nil` if the provider didn't report it (e.g. mid-stream chunks
    /// before the final usage frame). Always `nil` for OpenRouter.
    var costUSD: Decimal? = nil
    /// OpenRouter-reported cost in OpenRouter credits for this
    /// completion, or `nil` if not reported. Always `nil` for Venice.
    var costCredits: Decimal? = nil

    /// Usage frames are snapshots, not increments. Merge missing fields
    /// without double-counting repeated totals or losing a cost-only frame.
    func merging(_ newer: ChatUsage) -> ChatUsage {
        ChatUsage(
            promptTokens: newer.promptTokens ?? promptTokens,
            completionTokens: newer.completionTokens ?? completionTokens,
            totalTokens: newer.totalTokens ?? totalTokens,
            costUSD: newer.costUSD ?? costUSD,
            costCredits: newer.costCredits ?? costCredits
        )
    }
}
