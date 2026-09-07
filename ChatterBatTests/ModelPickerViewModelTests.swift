import XCTest
@testable import ChatterBat

final class ModelPickerViewModelTests: XCTestCase {
    private func makeModel(
        service: AIService,
        id: String,
        name: String? = nil
    ) -> ModelInfo {
        ModelInfo(
            identity: ModelIdentity(service: service, modelID: id),
            displayName: name ?? id,
            contextLength: nil,
            maxOutputTokens: nil,
            pricing: .unknown,
            supportsTools: .unknown,
            supportsReasoning: .unknown,
            supportsVision: .unknown,
            privacyDescription: nil
        )
    }

    @MainActor
    func testServiceWithNoStoredKeyIsMarkedNotConfiguredWithoutFetching() async {
        let store = InMemoryCredentialStore()
        let veniceFetcher = FakeModelCatalogFetcher(service: .venice, outcomeToReturn: .success([]))
        let viewModel = ModelPickerViewModel(
            credentialStore: store,
            fetchers: [.venice: veniceFetcher],
            preferencesStore: InMemoryModelPreferencesStore()
        )

        await viewModel.loadAllConfiguredCatalogs()

        guard case .notConfigured = viewModel.catalogStates[.venice] else {
            return XCTFail("Expected notConfigured")
        }
        XCTAssertEqual(veniceFetcher.fetchCount, 0, "Must not fetch for a service with no stored key.")
    }

    @MainActor
    func testConfiguredServiceLoadsModelsIntoCatalogState() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("venice-key", for: .venice)
        let model = makeModel(service: .venice, id: "llama-3.2-3b")
        let veniceFetcher = FakeModelCatalogFetcher(service: .venice, outcomeToReturn: .success([model]))
        let viewModel = ModelPickerViewModel(
            credentialStore: store,
            fetchers: [.venice: veniceFetcher],
            preferencesStore: InMemoryModelPreferencesStore()
        )

        await viewModel.loadAllConfiguredCatalogs()

        guard case .loaded(let models, _) = viewModel.catalogStates[.venice] else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(models, [model])
    }

    @MainActor
    func testFailedRefreshKeepsPreviouslyLoadedModelsVisible() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("venice-key", for: .venice)
        let model = makeModel(service: .venice, id: "llama-3.2-3b")
        let fetcher = FakeModelCatalogFetcher(service: .venice, outcomeToReturn: .success([model]))
        let viewModel = ModelPickerViewModel(
            credentialStore: store,
            fetchers: [.venice: fetcher],
            preferencesStore: InMemoryModelPreferencesStore()
        )
        await viewModel.refresh(.venice)

        fetcher.outcomeToReturn = .transportFailure("offline")
        await viewModel.refresh(.venice)

        guard case .failed(_, let cachedModels, _) = viewModel.catalogStates[.venice] else {
            return XCTFail("Expected failed state")
        }
        XCTAssertEqual(cachedModels, [model], "A refresh failure must not blank out the last successful catalog.")
    }

    @MainActor
    func testFilteredModelsRespectsServiceFilterAndSearchText() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("venice-key", for: .venice)
        try store.saveKey("or-key", for: .openRouter)
        let veniceModel = makeModel(service: .venice, id: "llama-3.2-3b", name: "Llama 3.2 3B")
        let orModel = makeModel(service: .openRouter, id: "openai/gpt-4", name: "GPT-4")
        let viewModel = ModelPickerViewModel(
            credentialStore: store,
            fetchers: [
                .venice: FakeModelCatalogFetcher(service: .venice, outcomeToReturn: .success([veniceModel])),
                .openRouter: FakeModelCatalogFetcher(service: .openRouter, outcomeToReturn: .success([orModel]))
            ],
            preferencesStore: InMemoryModelPreferencesStore()
        )
        await viewModel.loadAllConfiguredCatalogs()

        viewModel.serviceFilter = .venice
        XCTAssertEqual(viewModel.filteredModels, [veniceModel])

        viewModel.serviceFilter = .all
        viewModel.searchText = "gpt"
        XCTAssertEqual(viewModel.filteredModels, [orModel])
    }

    @MainActor
    func testSameNamedModelsOnDifferentServicesRemainDistinct() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("venice-key", for: .venice)
        try store.saveKey("or-key", for: .openRouter)
        let veniceModel = makeModel(service: .venice, id: "same-name", name: "Same Name")
        let orModel = makeModel(service: .openRouter, id: "same-name", name: "Same Name")
        let viewModel = ModelPickerViewModel(
            credentialStore: store,
            fetchers: [
                .venice: FakeModelCatalogFetcher(service: .venice, outcomeToReturn: .success([veniceModel])),
                .openRouter: FakeModelCatalogFetcher(service: .openRouter, outcomeToReturn: .success([orModel]))
            ],
            preferencesStore: InMemoryModelPreferencesStore()
        )
        await viewModel.loadAllConfiguredCatalogs()

        XCTAssertEqual(viewModel.filteredModels.count, 2, "Same display name on different services must not merge.")
        XCTAssertNotEqual(viewModel.filteredModels[0].identity, viewModel.filteredModels[1].identity)
    }

    @MainActor
    func testToggleFavoriteAndFavoritesOnlyFilter() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("venice-key", for: .venice)
        let modelA = makeModel(service: .venice, id: "a")
        let modelB = makeModel(service: .venice, id: "b")
        let viewModel = ModelPickerViewModel(
            credentialStore: store,
            fetchers: [.venice: FakeModelCatalogFetcher(service: .venice, outcomeToReturn: .success([modelA, modelB]))],
            preferencesStore: InMemoryModelPreferencesStore()
        )
        await viewModel.loadAllConfiguredCatalogs()

        XCTAssertFalse(viewModel.isFavorite(modelA.identity))
        viewModel.toggleFavorite(modelA.identity)
        XCTAssertTrue(viewModel.isFavorite(modelA.identity))

        viewModel.showFavoritesOnly = true
        XCTAssertEqual(viewModel.filteredModels, [modelA])
    }

    @MainActor
    func testRecordSelectionPopulatesRecentModels() async throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("venice-key", for: .venice)
        let model = makeModel(service: .venice, id: "a")
        let viewModel = ModelPickerViewModel(
            credentialStore: store,
            fetchers: [.venice: FakeModelCatalogFetcher(service: .venice, outcomeToReturn: .success([model]))],
            preferencesStore: InMemoryModelPreferencesStore()
        )
        await viewModel.loadAllConfiguredCatalogs()

        XCTAssertTrue(viewModel.recentModels.isEmpty)
        viewModel.recordSelection(model.identity)
        XCTAssertEqual(viewModel.recentModels, [model])
    }
}
