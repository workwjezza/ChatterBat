import Foundation

/// Normalized catalog pricing, always expressed in USD per 1,000,000
/// tokens regardless of how the source provider expresses it natively.
///
/// - Venice's `/models` response already reports `model_spec.pricing.input
///   /output.usd` in USD per 1,000,000 tokens ("Prices per 1M tokens unless
///   noted" — https://docs.venice.ai/overview/pricing, retrieved during
///   Stage 2 implementation), so Venice values pass through unchanged.
/// - OpenRouter's `/models` response reports `pricing.prompt`/`completion`
///   as a *string* in USD per single token (e.g. `"0.00003"`), so
///   OpenRouter values are multiplied by 1,000,000 before being stored
///   here.
///
/// `nil` means the provider did not report that price — the brief
/// requires this to display as "Unknown," never "Free" or "$0.00".
/// This type does not attempt to model caching, long-context tiers, or
/// time-of-day pricing overrides; see `docs/DECISIONS.md` for that scope
/// decision.
struct ModelPricing: Hashable, Sendable {
    let inputPerMillionTokensUSD: Decimal?
    let outputPerMillionTokensUSD: Decimal?

    static let unknown = ModelPricing(inputPerMillionTokensUSD: nil, outputPerMillionTokensUSD: nil)
}
