import Foundation
@testable import ChatterBat

/// Scripted `HTTPClient` double for testing provider connection checkers'
/// request construction and response handling without any real network
/// activity.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    enum Scripted {
        case success(status: Int, body: Data)
        case failure(Error)
    }

    private var scripted: Scripted
    private(set) var lastRequest: URLRequest?

    init(scripted: Scripted) {
        self.scripted = scripted
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        switch scripted {
        case .success(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (body, response)
        case .failure(let error):
            throw error
        }
    }
}

struct FakeTransportError: Error, LocalizedError {
    var errorDescription: String? { "Simulated transport failure." }
}
