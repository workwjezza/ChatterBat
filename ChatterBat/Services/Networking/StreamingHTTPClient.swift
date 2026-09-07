import Foundation

/// Transport abstraction for a chunked (streaming) HTTP response.
///
/// Distinct from `HTTPClient`, which buffers the whole body — chat
/// completions need incremental bytes as they arrive so the SSE parser
/// can start producing events before the response finishes. Production
/// code uses `URLSessionStreamingHTTPClient`; tests inject
/// `FakeStreamingHTTPClient` with scripted byte chunks and never touch
/// the network.
protocol StreamingHTTPClient: Sendable {
    /// Starts `request` and returns the initial `HTTPURLResponse` headers
    /// plus an async byte stream of the body. The response is available
    /// before the body finishes, so callers can check the status code
    /// (e.g. reject a non-200 before parsing SSE) without buffering the
    /// whole body first.
    ///
    /// Cancelling the `Task` that is iterating `bytes` cancels the
    /// underlying network task, per the brief's requirement that Stop
    /// actually cancels the connection.
    func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>)
}
