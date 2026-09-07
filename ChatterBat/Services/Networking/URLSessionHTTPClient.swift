import Foundation

/// `HTTPClient` backed by `URLSession`.
///
/// Uses an ephemeral session configuration (no disk cache, no persisted
/// cookies) since chat/account traffic is sensitive, per the brief's
/// requirement not to write raw requests/responses to debug files or
/// caches. A `RedirectBlockingDelegate` refuses cross-host redirects so an
/// `Authorization` header can never be forwarded to a host other than the
/// one the request was pinned to.
final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let delegate: RedirectBlockingDelegate

    /// - Parameter allowedHost: the exact host this client is pinned to
    ///   (e.g. `"api.venice.ai"`). Any redirect to a different host is
    ///   refused rather than followed.
    init(allowedHost: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let delegate = RedirectBlockingDelegate(allowedHost: allowedHost)
        self.delegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NonHTTPResponseError()
        }
        return (data, httpResponse)
    }
}

/// Refuses to follow any redirect that targets a host other than
/// `allowedHost`. Returning `nil` from this delegate method tells
/// `URLSession` not to follow the redirect; the original response is
/// delivered to the caller instead.
private final class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate, Sendable {
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
