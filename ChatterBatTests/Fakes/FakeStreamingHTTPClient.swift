import Foundation
@testable import ChatterBat

/// Scripted `StreamingHTTPClient` double. Feeds pre-scripted byte chunks
/// through an `AsyncThrowingStream`, simulating arbitrary network
/// fragmentation without any real socket.
final class FakeStreamingHTTPClient: StreamingHTTPClient, @unchecked Sendable {
    private let statusCode: Int
    private let chunks: [Data]
    private let failWithError: Error?
    private(set) var lastRequest: URLRequest?
    /// Set by the test after construction if it needs to observe
    /// cancellation of the byte stream (e.g. Stop button tests).
    private(set) var wasCancelled = false

    init(statusCode: Int, chunks: [Data], failWithError: Error? = nil) {
        self.statusCode = statusCode
        self.chunks = chunks
        self.failWithError = failWithError
    }

    func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        let chunks = self.chunks
        let failWithError = self.failWithError
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                for chunk in chunks {
                    if Task.isCancelled { break }
                    continuation.yield(chunk)
                    // Yield control so a consumer's cancellation has a
                    // chance to take effect between chunks, matching how
                    // a real network stream would allow cooperative
                    // cancellation between reads.
                    await Task.yield()
                }
                if let failWithError, !Task.isCancelled {
                    continuation.finish(throwing: failWithError)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.markCancelled()
            }
        }
        return (response, stream)
    }

    private func markCancelled() {
        wasCancelled = true
    }
}
