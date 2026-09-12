import XCTest
@testable import ChatterBat

final class ModelValuePolicyTests: XCTestCase {
    private func model(_ id: String, price: Int = 1, service: AIService = .venice,
                       reasoning: CapabilitySupport = .unsupported,
                       tools: CapabilitySupport = .unsupported,
                       context: Int? = 32_000, privacy: String? = "private") -> ModelInfo {
        ModelInfo(identity: ModelIdentity(service: service, modelID: id), displayName: id,
                  contextLength: context, maxOutputTokens: nil,
                  pricing: price < 0 ? .unknown : ModelPricing(inputPerMillionTokensUSD: Decimal(price), outputPerMillionTokensUSD: Decimal(price)),
                  supportsTools: tools, supportsReasoning: reasoning, supportsVision: .unsupported,
                  privacyDescription: privacy)
    }

    private func route(_ models: [ModelInfo], anchor: ModelInfo, prompt: String = "Hello",
                       recent: String = "", tools: Bool = false, context: Int = 5000,
                       favorites: Set<ModelIdentity>? = nil,
                       settings: AdvancedChatSettings = AdvancedChatSettings()) -> AutoModelDecision {
        AutoModelRouter.select(prompt: prompt, recentUserContext: recent, requiredContext: context,
                               anchor: anchor, models: models,
                               favorites: favorites ?? Set(models.map(\.identity)),
                               requiresTools: tools, settings: settings)
    }

    func testScoreUsesBothPricesAndUnknownIsNotFree() {
        XCTAssertEqual(ModelValuePolicy.score(model("a", price: 2)), 8)
        XCTAssertNil(ModelValuePolicy.score(model("unknown", price: -1)))
        XCTAssertEqual(ModelValuePolicy.score(model("free", price: 0)), 0)
    }

    func testHighlightIsSparseAndRequiresComparablePeersAndSpread() {
        let models = (1...12).map { model("m\($0)", price: $0) }
        XCTAssertEqual(models.filter { ModelValuePolicy.isGoodValue($0, among: models) }.count, 3)
        XCTAssertFalse(ModelValuePolicy.isGoodValue(models[0], among: Array(models.prefix(3))))
        let ties = (1...5).map { model("m\($0)") }
        XCTAssertFalse(ModelValuePolicy.isGoodValue(ties[0], among: ties))
        let other = model("other", price: 20, service: .openRouter)
        XCTAssertFalse(ModelValuePolicy.isGoodValue(models[0], among: Array(models.prefix(3)) + [other]))
    }

    func testGeneralChatChoosesCheapestTrustedModelNotUnknownOrUnstarred() {
        let anchor = model("anchor", price: 10)
        let trusted = model("trusted", price: 2)
        let models = [anchor, trusted, model("unstarred", price: 0), model("unknown", price: -1)]
        XCTAssertEqual(route(models, anchor: anchor, favorites: [trusted.identity]).model, trusted)
        XCTAssertEqual(route(models, anchor: anchor, favorites: []).model, anchor)
    }

    func testReasoningAndFollowupRequireSupportedReasoning() {
        let anchor = model("anchor", price: 10, reasoning: .supported)
        let reasoning = model("reasoner", price: 3, reasoning: .supported)
        let models = [anchor, reasoning, model("cheap"), model("unknown", reasoning: .unknown)]
        XCTAssertEqual(route(models, anchor: anchor, prompt: "Debug this Swift code").model, reasoning)
        XCTAssertEqual(route(models, anchor: anchor, prompt: "Continue", recent: "Prove this theorem").model, reasoning)
        XCTAssertEqual(route(models, anchor: anchor, settings: AdvancedChatSettings(reasoningEffort: .high)).model, reasoning)
        XCTAssertFalse(AutoModelRouter.needsReasoning("I visited a mathematical museum"))
    }

    func testDoesNotCrossServicePrivacyOrPriceCeiling() {
        let anchor = model("anchor", price: 2, reasoning: .supported)
        let models = [model("other-service", price: 0, service: .openRouter, reasoning: .supported),
                      model("other-privacy", price: 0, reasoning: .supported, privacy: "anonymized"),
                      model("expensive", price: 3, reasoning: .supported), anchor]
        XCTAssertEqual(route(models, anchor: anchor, prompt: "Analyze").model, anchor)
    }

    func testToolsAndContextAreHardFiltersAndFailureDoesNotSilentlyFallback() {
        let anchor = model("anchor", price: 5)
        let toolModel = model("tools", price: 3, tools: .supported)
        let models = [anchor, toolModel, model("small", tools: .supported, context: 1000),
                      model("unknown-context", tools: .supported, context: nil)]
        XCTAssertEqual(route(models, anchor: anchor, tools: true).model, toolModel)
        XCTAssertNil(route(models, anchor: anchor, tools: true, context: 100_000).model)
        XCTAssertNil(route([anchor], anchor: anchor, prompt: "Debug code").model)
        XCTAssertNil(route(models, anchor: model("unknown", price: -1)).model)
    }

    func testTieBreakIsDeterministic() {
        let a = model("a"), b = model("b")
        XCTAssertEqual(route([b, a], anchor: b).model, a)
        XCTAssertEqual(route([a, b], anchor: b).model, a)
    }

    func testAutoDoesNotDelegateToOpenRouterServerRouters() {
        let anchor = model("vendor/model", price: 2, service: .openRouter, privacy: nil)
        let router = model("openrouter/auto", price: 0, service: .openRouter, privacy: nil)
        XCTAssertEqual(route([anchor, router], anchor: anchor).model, anchor)
    }

    func testOutputPriceCannotExceedCeilingEvenWithCheaperWeightedScore() {
        let anchor = model("anchor", price: 2)
        let candidate = ModelInfo(identity: ModelIdentity(service: .venice, modelID: "candidate"),
                                  displayName: "candidate", contextLength: 32_000, maxOutputTokens: nil,
                                  pricing: ModelPricing(inputPerMillionTokensUSD: 0, outputPerMillionTokensUSD: 3),
                                  supportsTools: .unsupported, supportsReasoning: .unsupported,
                                  supportsVision: .unsupported, privacyDescription: "private")
        XCTAssertEqual(route([candidate, anchor], anchor: anchor).model, anchor)
    }
}