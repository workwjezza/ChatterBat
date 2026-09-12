import XCTest
@testable import ChatterBat

@MainActor
final class ModelSelectionDefaultsTests: XCTestCase {
    private func model(_ id: String = "anchor", service: AIService = .venice,
                       price: Decimal = 2, privacy: String? = "private") -> ModelInfo {
        ModelInfo(identity: ModelIdentity(service: service, modelID: id), displayName: id,
                  contextLength: 32_000, maxOutputTokens: nil,
                  pricing: ModelPricing(inputPerMillionTokensUSD: price, outputPerMillionTokensUSD: price),
                  supportsTools: .supported, supportsReasoning: .supported, supportsVision: .unsupported,
                  privacyDescription: privacy)
    }

    private func fixture(_ models: [ModelInfo]) async throws -> (ModelPickerViewModel, FakeModelCatalogFetcher) {
        let credentials = InMemoryCredentialStore()
        let service = models.first?.service ?? .venice
        try credentials.saveKey("fixture", for: service)
        let fetcher = FakeModelCatalogFetcher(service: service, outcomeToReturn: .success(models))
        let catalog = ModelPickerViewModel(credentialStore: credentials, fetchers: [service: fetcher],
                                           preferencesStore: InMemoryModelPreferencesStore())
        await catalog.refresh(service)
        for model in models { catalog.toggleFavorite(model.identity) }
        return (catalog, fetcher)
    }

    private func withStore(_ body: (UserDefaultsModelSelectionDefaultsStore, UserDefaults) throws -> Void) rethrows {
        let suite = "com.chatterbat.tests.selection.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(UserDefaultsModelSelectionDefaultsStore(defaults: defaults), defaults)
    }

    func testSavedPinAndSeparateAutoPolicyRoundTrip() throws {
        try withStore { store, defaults in
            let policy = try XCTUnwrap(SavedAutoPolicy(model: model(), settings: AdvancedChatSettings()))
            let value = ModelSelectionDefaults(pinnedModel: model("other", service: .openRouter).identity, autoPolicy: policy)
            store.save(value)
            let reloaded = UserDefaultsModelSelectionDefaultsStore(defaults: defaults).load()
            XCTAssertEqual(value, reloaded)
            XCTAssertNotEqual(reloaded.pinnedModel, reloaded.autoPolicy?.anchor)
        }
    }

    func testCorruptAndFutureVersionsFailClosedToUnconfiguredAuto() throws {
        try withStore { store, defaults in
            defaults.set(Data("broken".utf8), forKey: UserDefaultsModelSelectionDefaultsStore.storageKey)
            XCTAssertEqual(store.load(), ModelSelectionDefaults())
            var future = ModelSelectionDefaults(pinnedModel: model().identity)
            future.schemaVersion = 99
            defaults.set(try JSONEncoder().encode(future), forKey: UserDefaultsModelSelectionDefaultsStore.storageKey)
            XCTAssertEqual(store.load(), ModelSelectionDefaults())
        }
    }

    func testPinClickAgainRestoresSeparatePolicyAndFavoritesStayStarred() async throws {
        let anchor = model()
        let pin = model("pin", price: 20)
        let (catalog, fetcher) = try await fixture([anchor, pin])
        let app = AppViewModel()
        app.attachSelectionCatalog(catalog)
        app.selectCurrentModel(anchor, isBusy: false)
        app.saveAutoPolicyFromCurrentModel(isBusy: false)
        let savedPolicy = app.modelDefaults.autoPolicy
        app.togglePinnedDefault(pin.identity, isBusy: false)
        XCTAssertEqual(app.selectedModel, pin)
        XCTAssertFalse(app.autoModeEnabled)
        XCTAssertEqual(app.modelDefaults.autoPolicy, savedPolicy)
        app.togglePinnedDefault(pin.identity, isBusy: false)
        XCTAssertTrue(app.autoModeEnabled)
        XCTAssertNil(app.modelDefaults.pinnedModel)
        XCTAssertEqual(app.selectedModel, anchor)
        XCTAssertEqual(app.modelDefaults.autoPolicy, savedPolicy)
        XCTAssertTrue(catalog.isFavorite(pin.identity))
        XCTAssertEqual(fetcher.fetchCount, 1, "Selection actions must not fetch or infer.")
    }

    func testUnpinWithoutPolicyRequiresSetup() async throws {
        let chosen = model()
        let (catalog, _) = try await fixture([chosen])
        let app = AppViewModel()
        app.attachSelectionCatalog(catalog)
        app.togglePinnedDefault(chosen.identity, isBusy: false)
        app.togglePinnedDefault(chosen.identity, isBusy: false)
        XCTAssertTrue(app.autoModeEnabled)
        XCTAssertNil(app.selectedModel)
        XCTAssertNil(app.modelDefaults.autoPolicy)
        XCTAssertTrue(app.selectionNotice?.contains("setup") == true)
    }

    func testManualPickerSelectionDoesNotOverwriteDefaultAndNewChatRestoresPin() async throws {
        let pin = model()
        let manual = model("manual")
        let (catalog, _) = try await fixture([pin, manual])
        let app = AppViewModel()
        app.attachSelectionCatalog(catalog)
        app.togglePinnedDefault(pin.identity, isBusy: false)
        app.selectCurrentModel(manual, isBusy: false)
        app.resolveSavedSelection()
        XCTAssertEqual(app.selectedModel, manual)
        XCTAssertEqual(app.modelDefaults.pinnedModel, pin.identity)
        app.startNewConversation()
        XCTAssertEqual(app.selectedModel, pin)
    }

    func testBusyMutationsAreNoops() async throws {
        let chosen = model()
        let (catalog, _) = try await fixture([chosen])
        let app = AppViewModel()
        app.attachSelectionCatalog(catalog)
        app.togglePinnedDefault(chosen.identity, isBusy: false)
        let before = app.modelDefaults
        app.togglePinnedDefault(chosen.identity, isBusy: true)
        app.useAutoDefault(isBusy: true)
        app.saveAutoPolicyFromCurrentModel(isBusy: true)
        app.selectCurrentModel(model("other"), isBusy: true)
        app.setCurrentAutoEnabled(true, isBusy: true)
        XCTAssertEqual(app.modelDefaults, before)
        XCTAssertEqual(app.selectedModel, chosen)
        XCTAssertFalse(app.autoModeEnabled)
    }

    func testUnavailablePinPersistsAndCanBeUnpinned() async throws {
        let chosen = model()
        let (catalog, fetcher) = try await fixture([chosen])
        let app = AppViewModel()
        app.attachSelectionCatalog(catalog)
        app.togglePinnedDefault(chosen.identity, isBusy: false)
        fetcher.outcomeToReturn = .success([])
        await catalog.refresh(.venice)
        app.resolveSavedSelection()
        XCTAssertNil(app.selectedModel)
        XCTAssertEqual(app.modelDefaults.pinnedModel, chosen.identity)
        XCTAssertTrue(app.selectionNotice?.contains("unavailable") == true)
        XCTAssertEqual(catalog.bookmarkedIdentities, [chosen.identity])
        app.togglePinnedDefault(chosen.identity, isBusy: false)
        XCTAssertNil(app.modelDefaults.pinnedModel)
    }

    func testUnstarringDoesNotChangePin() async throws {
        let chosen = model()
        let (catalog, _) = try await fixture([chosen])
        let app = AppViewModel()
        app.attachSelectionCatalog(catalog)
        app.togglePinnedDefault(chosen.identity, isBusy: false)
        catalog.toggleFavorite(chosen.identity)
        XCTAssertEqual(app.modelDefaults.pinnedModel, chosen.identity)
        app.togglePinnedDefault(chosen.identity, isBusy: false)
        XCTAssertNil(app.modelDefaults.pinnedModel)
    }

    func testSavedRatesCannotGrowOnCatalogRefresh() async throws {
        let original = model(price: 2)
        let (catalog, fetcher) = try await fixture([original])
        let policy = try XCTUnwrap(SavedAutoPolicy(model: original, settings: AdvancedChatSettings()))
        fetcher.outcomeToReturn = .success([model(price: 20)])
        await catalog.refresh(.venice)
        let decision = catalog.autoDecision(prompt: "Hi", recent: "", requiredContext: 5000,
                                            policy: policy, requiresTools: false, settings: AdvancedChatSettings())
        XCTAssertNil(decision.model)
        XCTAssertEqual(policy.maxInputUSDPerMillion, 2)
        XCTAssertEqual(fetcher.fetchCount, 2)
    }

    func testPrivacyChangeAndOfflineCatalogBlockSavedAuto() async throws {
        let original = model()
        let (catalog, fetcher) = try await fixture([original])
        let policy = try XCTUnwrap(SavedAutoPolicy(model: original, settings: AdvancedChatSettings()))
        fetcher.outcomeToReturn = .success([model(privacy: "anonymized")])
        await catalog.refresh(.venice)
        XCTAssertNil(catalog.autoDecision(prompt: "Hi", recent: "", requiredContext: 5000,
                                          policy: policy, requiresTools: false, settings: AdvancedChatSettings()).model)
        fetcher.outcomeToReturn = .transportFailure("offline")
        await catalog.refresh(.venice)
        XCTAssertNil(catalog.currentModel(original.identity))
        XCTAssertNotNil(catalog.displayModel(original.identity))
    }

    func testAutoUsesFreshCandidatesWithinSavedPolicy() async throws {
        let original = model(price: 5)
        let cheap = model("cheap", price: 1)
        let (catalog, _) = try await fixture([original, cheap])
        let policy = try XCTUnwrap(SavedAutoPolicy(model: original, settings: AdvancedChatSettings()))
        let decision = catalog.autoDecision(prompt: "Debug code", recent: "", requiredContext: 5000,
                                            policy: policy, requiresTools: true, settings: AdvancedChatSettings())
        XCTAssertEqual(decision.model, cheap)
        catalog.searchText = "no match"
        catalog.serviceFilter = .openRouter
        XCTAssertEqual(catalog.bookmarkedIdentities.count, 2)
    }

    func testRelaunchRestoresPinAndDoesNotResolveFromDiskMetadata() async throws {
        let chosen = model()
        let (catalog, _) = try await fixture([chosen])
        withStore { store, defaults in
            let first = AppViewModel(selectionDefaultsStore: store)
            first.attachSelectionCatalog(catalog)
            first.togglePinnedDefault(chosen.identity, isBusy: false)
            let second = AppViewModel(selectionDefaultsStore: UserDefaultsModelSelectionDefaultsStore(defaults: defaults))
            XCTAssertEqual(second.modelDefaults.pinnedModel, chosen.identity)
            XCTAssertNil(second.selectedModel)
            second.attachSelectionCatalog(catalog)
            XCTAssertEqual(second.selectedModel, chosen)
        }
    }

    func testSavedOpenRouterPrivacyAppliedOnlyDuringAuto() async throws {
        let chosen = model(service: .openRouter, privacy: nil)
        let (catalog, _) = try await fixture([chosen])
        let app = AppViewModel()
        app.attachSelectionCatalog(catalog)
        app.selectCurrentModel(chosen, isBusy: false)
        app.advancedChatSettings.openRouterRouting.dataCollection = .deny
        app.advancedChatSettings.openRouterRouting.zdr = true
        app.advancedChatSettings.openRouterRouting.allowFallbacks = false
        app.saveAutoPolicyFromCurrentModel(isBusy: false)
        app.advancedChatSettings = AdvancedChatSettings()
        XCTAssertEqual(app.effectiveChatSettings.openRouterRouting.dataCollection, .deny)
        XCTAssertTrue(app.effectiveChatSettings.openRouterRouting.zdr)
        XCTAssertFalse(app.effectiveChatSettings.openRouterRouting.allowFallbacks)
        app.setCurrentAutoEnabled(false, isBusy: false)
        XCTAssertEqual(app.effectiveChatSettings.openRouterRouting.dataCollection, .allow)
    }

    func testSavedPolicyNeverWeakensStricterCurrentPrivacy() throws {
        let policy = try XCTUnwrap(SavedAutoPolicy(model: model(service: .openRouter, privacy: nil), settings: AdvancedChatSettings()))
        var strict = AdvancedChatSettings()
        strict.openRouterRouting.dataCollection = .deny
        strict.openRouterRouting.zdr = true
        strict.openRouterRouting.allowFallbacks = false
        XCTAssertEqual(policy.applyingPrivacy(to: strict), strict)
    }

    func testAutoPolicyRelaunchAndNewChatRestoreWithoutManualPin() async throws {
        let chosen = model()
        let (catalog, _) = try await fixture([chosen])
        withStore { store, defaults in
            let first = AppViewModel(selectionDefaultsStore: store)
            first.attachSelectionCatalog(catalog)
            first.selectCurrentModel(chosen, isBusy: false)
            first.saveAutoPolicyFromCurrentModel(isBusy: false)
            let relaunched = AppViewModel(selectionDefaultsStore: UserDefaultsModelSelectionDefaultsStore(defaults: defaults))
            relaunched.attachSelectionCatalog(catalog)
            XCTAssertTrue(relaunched.autoModeEnabled)
            XCTAssertEqual(relaunched.selectedModel, chosen)
            XCTAssertEqual(relaunched.modelDefaults.autoPolicy, first.modelDefaults.autoPolicy)
            relaunched.setCurrentAutoEnabled(false, isBusy: false)
            relaunched.startNewConversation()
            XCTAssertTrue(relaunched.autoModeEnabled)
            XCTAssertEqual(relaunched.selectedModel, chosen)
        }
    }

    func testUnknownPriceCannotCreatePolicy() {
        let unknown = ModelInfo(identity: model().identity, displayName: "unknown", contextLength: nil,
                                maxOutputTokens: nil, pricing: .unknown, supportsTools: .unknown,
                                supportsReasoning: .unknown, supportsVision: .unknown, privacyDescription: nil)
        XCTAssertNil(SavedAutoPolicy(model: unknown, settings: AdvancedChatSettings()))
        XCTAssertNil(SavedAutoPolicy(model: model(price: -1), settings: AdvancedChatSettings()))
        XCTAssertNil(SavedAutoPolicy(model: model("openrouter/auto", service: .openRouter), settings: AdvancedChatSettings()))
    }

    func testExplicitAutoToggleRecoversAfterOfflineRefresh() async throws {
        let chosen = model()
        let (catalog, fetcher) = try await fixture([chosen])
        let app = AppViewModel()
        app.attachSelectionCatalog(catalog)
        app.selectCurrentModel(chosen, isBusy: false)
        app.saveAutoPolicyFromCurrentModel(isBusy: false)
        fetcher.outcomeToReturn = .transportFailure("offline")
        await catalog.refresh(.venice)
        app.setCurrentAutoEnabled(true, isBusy: false)
        XCTAssertNil(app.selectedModel)
        fetcher.outcomeToReturn = .success([chosen])
        await catalog.refresh(.venice)
        app.resolveSavedSelection()
        XCTAssertEqual(app.selectedModel, chosen)
        XCTAssertTrue(app.autoModeEnabled)
    }
}