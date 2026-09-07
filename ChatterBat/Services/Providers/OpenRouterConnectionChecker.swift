import Foundation

/// Verifies an OpenRouter API key via `GET /api/v1/key`.
///
/// This endpoint is documented as the way to check credit/rate-limit
/// status for the *calling* key — it authenticates the key without running
/// inference, unlike the public `/models` catalog. See
/// https://openrouter.ai/docs/api-reference/limits (retrieved during
/// Stage 1 implementation).
struct OpenRouterConnectionChecker: ConnectionChecking {
    let service: AIService = .openRouter
    private let httpClient: HTTPClient
    private let baseURL: URL

    init(
        httpClient: HTTPClient,
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    func checkConnection(apiKey: String) async -> ConnectionCheckOutcome {
        var request = URLRequest(url: baseURL.appendingPathComponent("key"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.send(request)
        } catch {
            return .transportFailure(error.localizedDescription)
        }

        switch response.statusCode {
        case 200:
            guard let decoded = try? JSONDecoder().decode(OpenRouterKeyResponse.self, from: data) else {
                return .unrecognizedResponse("OpenRouter returned an unexpected response body.")
            }
            return .valid(summary: decoded.data.summary)
        case 401, 403:
            return .invalidCredential
        default:
            return .unrecognizedResponse("OpenRouter returned HTTP \(response.statusCode).")
        }
    }
}

/// Decodes only the fields ChatterBat currently displays. Unknown fields
/// are ignored by `Decodable` by default; all fields here are optional
/// except `label`, since the brief requires tolerating unknown/missing
/// optional metadata rather than failing the whole decode.
private struct OpenRouterKeyResponse: Decodable {
    struct KeyInfo: Decodable {
        let label: String?
        let limit: Double?
        let limitRemaining: Double?
        let usage: Double?
        let isFreeTier: Bool?

        enum CodingKeys: String, CodingKey {
            case label
            case limit
            case limitRemaining = "limit_remaining"
            case usage
            case isFreeTier = "is_free_tier"
        }

        /// A short, non-sensitive human-readable summary suitable for
        /// display in Settings. Built only from fields intended for this
        /// purpose — never the raw decoded response.
        var summary: String {
            if let limitRemaining {
                return "Connected · \(formattedCredits(limitRemaining)) credits remaining"
            }
            if let usage {
                return "Connected · \(formattedCredits(usage)) credits used"
            }
            return "Connected"
        }

        private func formattedCredits(_ value: Double) -> String {
            String(format: "$%.2f", value)
        }
    }

    let data: KeyInfo
}
