import Foundation

/// Minimal HTTP transport abstraction.
///
/// Provider adapters depend on this protocol instead of `URLSession`
/// directly so tests can inject a fake transport (see
/// `ChatterBatTests/Fakes/FakeHTTPClient.swift`) and never touch the
/// network. Production code uses `URLSessionHTTPClient`.
protocol HTTPClient: Sendable {
    /// Performs `request` and returns the raw body plus the HTTP response.
    /// Throws for transport-level failures (no connectivity, timeout,
    /// TLS failure, etc.). Non-2xx HTTP statuses are *not* thrown here —
    /// callers inspect `HTTPURLResponse.statusCode` themselves, because a
    /// 401/402/429 is meaningful provider information, not a transport
    /// error.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Transport-level error for responses that aren't a valid HTTP response
/// (should not normally happen with URLSession + http(s) URLs).
struct NonHTTPResponseError: Error, Sendable {}
