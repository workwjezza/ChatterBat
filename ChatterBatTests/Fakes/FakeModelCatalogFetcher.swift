import Foundation
@testable import ChatterBat

/// Scripted `ModelCatalogFetching` double. Never performs real network
/// requests.
final class FakeModelCatalogFetcher: ModelCatalogFetching, @unchecked Sendable {
    let service: AIService
    var outcomeToReturn: ModelCatalogFetchOutcome
    private(set) var fetchCount = 0

    init(service: AIService, outcomeToReturn: ModelCatalogFetchOutcome) {
        self.service = service
        self.outcomeToReturn = outcomeToReturn
    }

    func fetchModels(apiKey: String) async -> ModelCatalogFetchOutcome {
        fetchCount += 1
        return outcomeToReturn
    }
}
