import Foundation

/// Verifies a Venice API key via `GET /api_keys/rate_limits`.
///
/// Documented as returning "details about user balances and rate limits"
/// for the calling key, authenticating via Bearer token and responding
/// 401 on bad auth — it does not run inference. See
/// https://docs.venice.ai/api-reference/endpoint/api_keys/rate_limits
/// (retrieved during Stage 1 implementation).
struct VeniceConnectionChecker: ConnectionChecking {
    let service: AIService = .venice
    private let httpClient: HTTPClient
    private let baseURL: URL

    init(
        httpClient: HTTPClient,
        baseURL: URL = URL(string: "https://api.venice.ai/api/v1")!
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    func checkConnection(apiKey: String) async -> ConnectionCheckOutcome {
        var request = URLRequest(url: baseURL.appendingPathComponent("api_keys/rate_limits"))
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
            guard let decoded = try? JSONDecoder().decode(VeniceRateLimitsResponse.self, from: data) else {
                return .unrecognizedResponse("Venice returned an unexpected response body.")
            }
            return .valid(summary: decoded.data.summary)
        case 401, 403:
            return .invalidCredential
        default:
            return .unrecognizedResponse("Venice returned HTTP \(response.statusCode).")
        }
    }
}

/// Decodes only the fields ChatterBat currently displays. `apiTier` and the
/// balance fields are all optional so an unexpected/evolving shape doesn't
/// fail the whole decode — an honest "Connected" with no detail is still
/// correct in that case.
private struct VeniceRateLimitsResponse: Decodable {
    struct Balances: Decodable {
        let usd: Double?
        let diem: Double?

        enum CodingKeys: String, CodingKey {
            case usd = "USD"
            case diem = "DIEM"
        }
    }

    struct RateLimitData: Decodable {
        let apiTier: KeyOrString?
        let balances: Balances?

        enum CodingKeys: String, CodingKey {
            case apiTier
            case balances
        }

        /// A short, non-sensitive human-readable summary suitable for
        /// display in Settings.
        var summary: String {
            var parts: [String] = ["Connected"]
            if let usd = balances?.usd {
                parts.append(String(format: "$%.2f USD", usd))
            }
            if let tier = apiTier?.stringValue, !tier.isEmpty {
                parts.append("\(tier) tier")
            }
            return parts.joined(separator: " · ")
        }
    }

    let data: RateLimitData
}

/// `apiTier` in Venice's documented schema has appeared as either a plain
/// string or a small object depending on API version; decoding leniently
/// here avoids the whole connection check failing over a field ChatterBat
/// only uses for an optional display hint.
private enum KeyOrString: Decodable {
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .other
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .other: return nil
        }
    }
}
