import XCTest
@testable import ChatterBat

@MainActor
final class ModelPickerFilterTests: XCTestCase {
    private func model(_ id: String, service: AIService = .venice,
                       tools: CapabilitySupport = .unknown,
                       reasoning: CapabilitySupport = .unknown,
                       vision: CapabilitySupport = .unknown) -> ModelInfo {
        ModelInfo(identity: ModelIdentity(service: service, modelID: id), displayName: id,
                  contextLength: 32_000, maxOutputTokens: nil,
                  pricing: ModelPricing(inputPerMillionTokensUSD: 1, outputPerMillionTokensUSD: 1),
                  supportsTools: tools, supportsReasoning: reasoning, supportsVision: vision,
                  privacyDescription: service == .venice ? "private" : nil)
    }

    private func fixture(_ models: [ModelInfo]) async throws -> (ModelPickerViewModel, [FakeModelCatalogFetcher]) {
        let credentials = InMemoryCredentialStore()
        var fetchers: [AIService: ModelCatalogFetching] = [:]
        var fakes: [FakeModelCatalogFetcher] = []
        for service in AIService.allCases {
            try credentials.saveKey("fixture", for: service)
            let fake = FakeModelCatalogFetcher(service: service, outcomeToReturn: .success(models.filter { $0.service == service }))
            fetchers[service] = fake
            fakes.append(fake)
        }
        let picker = ModelPickerViewModel(credentialStore: credentials, fetchers: fetchers,
                                         preferencesStore: InMemoryModelPreferencesStore())
        await picker.loadAllConfiguredCatalogs()
        return (picker, fakes)
    }

    func testEachCapabilityOnlyMatchesReportedSupport() async throws {
        let supported = model("yes", tools: .supported, reasoning: .supported, vision: .supported)
        let unknown = model("unknown")
        let unsupported = model("no", tools: .unsupported, reasoning: .unsupported, vision: .unsupported)
        let (picker, _) = try await fixture([supported, unknown, unsupported])
        for capability in ModelPickerCapability.allCases {
            picker.capabilityFilters = [capability]
            XCTAssertEqual(picker.filteredModels, [supported])
        }
        picker.capabilityFilters = []
        XCTAssertEqual(picker.filteredModels.count, 3)
    }

    func testMultipleCapabilitiesIntersect() async throws {
        let both = model("both", tools: .supported, reasoning: .supported)
        let (picker, _) = try await fixture([both, model("tools", tools: .supported), model("reasoning", reasoning: .supported)])
        picker.setCapability(.tools, enabled: true)
        picker.setCapability(.reasoning, enabled: true)
        XCTAssertEqual(picker.filteredModels, [both])
        picker.setCapability(.tools, enabled: false)
        XCTAssertEqual(picker.filteredModels.count, 2)
    }

    func testProviderSearchFavoritesAndCapabilitiesCombine() async throws {
        let target = model("Target", tools: .supported)
        let otherProvider = model("Target", service: .openRouter, tools: .supported)
        let (picker, _) = try await fixture([target, otherProvider, model("Other", tools: .supported)])
        picker.toggleFavorite(target.identity)
        picker.serviceFilter = .venice
        picker.searchText = "  TARGET \n"
        picker.showFavoritesOnly = true
        picker.capabilityFilters = [.tools]
        XCTAssertEqual(picker.filteredModels, [target])
        XCTAssertEqual(picker.filteredModels(for: .venice), [target])
        XCTAssertTrue(picker.filteredModels(for: .openRouter).isEmpty)
    }

    func testRecentSectionObeysEveryFilterAndKeepsOrder() async throws {
        let a = model("a", tools: .supported, reasoning: .supported)
        let b = model("b", tools: .supported, reasoning: .supported)
        let c = model("c", service: .openRouter, tools: .supported, reasoning: .supported)
        let unknown = model("unknown")
        let (picker, _) = try await fixture([a, b, c, unknown])
        for model in [a, b, c, unknown] { picker.recordSelection(model.identity) }
        picker.capabilityFilters = [.tools]
        picker.taskPreset = .coding
        picker.serviceFilter = .venice
        XCTAssertEqual(picker.filteredRecentModels, [b, a])
        picker.toggleFavorite(a.identity)
        picker.showFavoritesOnly = true
        XCTAssertEqual(picker.filteredRecentModels, [a])
        picker.searchText = "no match"
        XCTAssertTrue(picker.filteredRecentModels.isEmpty)
        XCTAssertEqual(picker.recentModels.count, 4, "Display filtering must not delete recent history.")
    }

    func testCodingIsOnlyReasoningHeuristicAndDoesNotClearExplicitFilters() async throws {
        let reasoning = model("plain name", reasoning: .supported)
        let namedCoder = model("best coding model")
        let (picker, _) = try await fixture([reasoning, namedCoder])
        picker.taskPreset = .coding
        XCTAssertEqual(picker.filteredModels, [reasoning], "Do not infer capability from a model name.")
        picker.capabilityFilters = [.vision]
        XCTAssertTrue(picker.filteredModels.isEmpty)
        picker.taskPreset = .all
        XCTAssertEqual(picker.capabilityFilters, [.vision])
        XCTAssertTrue(ModelPickerTaskPreset.coding.explanation.contains("not proven coding quality"))
    }

    func testGuidancePresetsDoNotInventQualityFilters() async throws {
        let models = [model("unknown"), model("no", reasoning: .unsupported), model("yes", reasoning: .supported)]
        let (picker, _) = try await fixture(models)
        for preset in [ModelPickerTaskPreset.ideating, .historicalReferences] {
            picker.taskPreset = preset
            XCTAssertEqual(picker.filteredModels, models)
            XCTAssertTrue(preset.suggestedCapabilities.isEmpty)
            XCTAssertTrue(preset.explanation.contains("Guidance only"))
        }
    }

    func testUnavailableWorkflowsNeverClaimMatchesEvenForToolsAndVision() async throws {
        let capable = model("capable", tools: .supported, reasoning: .supported, vision: .supported)
        let (picker, _) = try await fixture([capable])
        picker.recordSelection(capable.identity)
        for preset in [ModelPickerTaskPreset.webBrowsing, .imageEditing] {
            picker.taskPreset = preset
            XCTAssertFalse(preset.isAvailable)
            XCTAssertTrue(picker.filteredModels.isEmpty)
            XCTAssertTrue(picker.filteredRecentModels.isEmpty)
            XCTAssertTrue(preset.title.contains("not available yet"))
        }
    }

    func testResetOnlyResetsPickerState() async throws {
        let chosen = model("chosen", tools: .supported)
        let (picker, fetchers) = try await fixture([chosen])
        picker.toggleFavorite(chosen.identity)
        picker.recordSelection(chosen.identity)
        let originalCatalog = picker.catalogStates
        picker.searchText = "x"
        picker.serviceFilter = .openRouter
        picker.showFavoritesOnly = true
        picker.capabilityFilters = [.vision]
        picker.taskPreset = .coding
        XCTAssertTrue(picker.hasActiveFilters)
        picker.resetFilters()
        XCTAssertFalse(picker.hasActiveFilters)
        XCTAssertEqual(picker.filteredModels, [chosen])
        XCTAssertEqual(picker.bookmarkedIdentities, [chosen.identity])
        XCTAssertEqual(picker.recentModels, [chosen])
        XCTAssertEqual(picker.catalogStates, originalCatalog)
        XCTAssertTrue(fetchers.allSatisfy { $0.fetchCount == 1 })
    }

    func testFiltersDoNotAffectAutoPoolOrBookmarks() async throws {
        let chosen = model("anchor", reasoning: .supported)
        let (picker, fetchers) = try await fixture([chosen])
        picker.toggleFavorite(chosen.identity)
        let policy = try XCTUnwrap(SavedAutoPolicy(model: chosen, settings: AdvancedChatSettings()))
        picker.taskPreset = .imageEditing
        picker.serviceFilter = .openRouter
        picker.capabilityFilters = [.vision]
        picker.searchText = "absent"
        XCTAssertTrue(picker.filteredModels.isEmpty)
        XCTAssertEqual(picker.bookmarkedIdentities, [chosen.identity])
        let decision = picker.autoDecision(prompt: "Hello", recent: "", requiredContext: 5000,
                                           policy: policy, requiresTools: false, settings: AdvancedChatSettings())
        XCTAssertEqual(decision.model, chosen)
        XCTAssertTrue(fetchers.allSatisfy { $0.fetchCount == 1 })
    }

    func testCapabilityDetailsDistinguishUnknownAndUnsupported() async throws {
        let chosen = model("mixed", tools: .supported, reasoning: .unsupported)
        let (picker, _) = try await fixture([chosen])
        XCTAssertEqual(picker.capabilitySummary(for: chosen),
                       "Tool calling: Reported supported; Reasoning: Reported unsupported; Image understanding: Unknown")
    }

    func testCachedResultsStillFilterWithoutMakingFreshnessClaims() async throws {
        let chosen = model("chosen", tools: .supported)
        let (picker, fetchers) = try await fixture([chosen])
        fetchers.first?.outcomeToReturn = .transportFailure("offline")
        await picker.refresh(.venice)
        picker.capabilityFilters = [.tools]
        XCTAssertEqual(picker.filteredModels, [chosen])
        XCTAssertNil(picker.currentModel(chosen.identity))
        XCTAssertFalse(picker.isGoodValue(chosen))
    }
}