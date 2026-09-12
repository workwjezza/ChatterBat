import Foundation

/// Transparent price heuristics, not intelligence benchmarks. No model IDs,
/// external classifier, or inference calls. Unknown prices never mean free.
enum ModelValuePolicy {
    /// A fixed 3:1 input/output mix for comparing listed token rates only.
    static func score(_ model: ModelInfo) -> Decimal? {
        guard let input = model.pricing.inputPerMillionTokensUSD,
              let output = model.pricing.outputPerMillionTokensUSD,
              !input.isNaN, !output.isNaN, input >= 0, output >= 0 else { return nil }
        return input * 3 + output
    }

    /// Highlight only the cheapest quarter (at most 3) of a comparable
    /// group with at least four entries and an actual price spread.
    static func isGoodValue(_ model: ModelInfo, among models: [ModelInfo]) -> Bool {
        guard score(model) != nil else { return false }
        let peers = models.filter {
            $0.service == model.service && $0.privacyDescription == model.privacyDescription
                && $0.supportsTools == model.supportsTools
                && $0.supportsReasoning == model.supportsReasoning
                && $0.supportsVision == model.supportsVision
                && contextBand($0) == contextBand(model) && score($0) != nil
        }.sorted(by: cheaper)
        guard peers.count >= 4, let first = peers.first, let last = peers.last,
              score(first) != score(last) else { return false }
        return peers.prefix(min(3, peers.count / 4)).contains { $0.identity == model.identity }
    }

    static func cheaper(_ lhs: ModelInfo, _ rhs: ModelInfo) -> Bool {
        let left = score(lhs) ?? Decimal.greatestFiniteMagnitude
        let right = score(rhs) ?? Decimal.greatestFiniteMagnitude
        return left == right ? lhs.id < rhs.id : left < right
    }

    private static func contextBand(_ model: ModelInfo) -> Int {
        guard let context = model.contextLength, context > 0 else { return -1 }
        if context < 32_000 { return 0 }
        if context < 128_000 { return 1 }
        return 2
    }
}

struct AutoModelDecision: Equatable {
    let model: ModelInfo?
    let explanation: String
}

enum AutoModelRouter {
    /// English task hints intentionally prefer false positives over claiming
    /// semantic understanding. Recent user context keeps short follow-ups
    /// attached to their task. Explicit reasoning settings also require support.
    static func needsReasoning(_ text: String) -> Bool {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        return !words.isDisjoint(with: [
            "code", "coding", "debug", "debugging", "refactor", "swift", "python",
            "javascript", "algorithm", "prove", "proof", "math", "mathematics",
            "analyze", "analyse", "architecture", "reasoning", "calculate"
        ]) || text.contains("```")
    }

    static func select(
        prompt: String, recentUserContext: String, requiredContext: Int,
        anchor: ModelInfo, models: [ModelInfo], favorites: Set<ModelIdentity>,
        requiresTools: Bool, settings: AdvancedChatSettings
    ) -> AutoModelDecision {
        guard ModelValuePolicy.score(anchor) != nil else {
            return AutoModelDecision(model: nil, explanation: "Auto needs a selected model with known pricing. Choose one in the model picker.")
        }
        let reasoning = needsReasoning(prompt + "\n" + recentUserContext)
            || settings.reasoningEffort != nil || settings.venice.disableThinking
            || settings.venice.stripThinkingResponse
        let candidates = models.filter { model in
            guard model.service == anchor.service,
                  !model.modelID.hasPrefix("openrouter/"),
                  model.privacyDescription == anchor.privacyDescription,
                  model.identity == anchor.identity || favorites.contains(model.identity),
                  ModelValuePolicy.score(model) != nil,
                  let context = model.contextLength, context >= requiredContext,
                  !requiresTools || model.supportsTools == .supported,
                  !reasoning || model.supportsReasoning == .supported,
                  let input = model.pricing.inputPerMillionTokensUSD,
                  let output = model.pricing.outputPerMillionTokensUSD,
                  let maxInput = anchor.pricing.inputPerMillionTokensUSD,
                  let maxOutput = anchor.pricing.outputPerMillionTokensUSD
            else { return false }
            return input <= maxInput && output <= maxOutput
        }.sorted(by: ModelValuePolicy.cheaper)
        guard let chosen = candidates.first else {
            return AutoModelDecision(model: nil, explanation: "No Auto candidate fits the context, capabilities and selected price ceiling. Star a suitable model, choose another ceiling, or turn Auto off.")
        }
        let task = reasoning ? "reasoning/code" : "general chat"
        return AutoModelDecision(model: chosen, explanation: "Local \(task) rule · lowest 3:1 listed-price score in your eligible pool. No routing AI call.")
    }
}