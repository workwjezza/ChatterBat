import Foundation
@testable import ChatterBat

/// Scripted `ConnectionChecking` double. Never performs real network
/// requests.
final class FakeConnectionChecker: ConnectionChecking, @unchecked Sendable {
    let service: AIService
    var outcomeToReturn: ConnectionCheckOutcome
    private(set) var receivedKeys: [String] = []

    init(service: AIService, outcomeToReturn: ConnectionCheckOutcome) {
        self.service = service
        self.outcomeToReturn = outcomeToReturn
    }

    func checkConnection(apiKey: String) async -> ConnectionCheckOutcome {
        receivedKeys.append(apiKey)
        return outcomeToReturn
    }
}
