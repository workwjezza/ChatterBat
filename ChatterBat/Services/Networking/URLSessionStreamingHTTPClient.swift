import Foundation

/// `StreamingHTTPClient` backed by `URLSession.bytes(for:)`.
///
/// Uses the same ephemeral, redirect-blocking configuration as
/// `URLSessionHTTPClient` (no disk cache, no cookies, cross-host
/// redirects refused), since chat traffic is exactly the sensitive
/// traffic the brief calls out for this treatment.
final class URLSessionStreamingHTTPClient: StreamingHTTPClient {
    private let session: URLSession

    init(allowedHost: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let delegate = RedirectBlockingStreamDelegate(allowedHost: allowedHost)
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NonHTTPResponseError()
        }

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    // Chunk into reasonably-sized buffers rather than
                    // yielding one byte at a time; the SSE parser handles
                    // arbitrary fragmentation either way, so this is a
                    // throughput optimization only.
                    var buffer = [UInt8]()
                    buffer.reserveCapacity(4096)
                    for try await byte in asyncBytes {
                        buffer.append(byte)
                        if buffer.count >= 4096 {
                            continuation.yield(Data(buffer))
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(Data(buffer))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return (httpResponse, stream)
    }
}

/// Same redirect-blocking policy as `URLSessionHTTPClient`'s delegate,
/// duplicated rather than shared because `URLSessionTaskDelegate`
/// conformance is tied to the session's own delegate instance and the two
/// HTTP clients intentionally don't share a session.
private final class RedirectBlockingStreamDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let allowedHost: String

    init(allowedHost: String) {
        self.allowedHost = allowedHost
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if request.url?.host == allowedHost {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}
