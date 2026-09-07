import Foundation

/// Fetches Venice's text-model catalog via `GET /models?type=text`.
///
/// `type=text` is Venice's documented filter for restricting results to
/// text/chat models, excluding image/audio/video/embedding models — see
/// https://docs.venice.ai/api-reference/endpoint/models/list (retrieved
/// during Stage 2 implementation). Pricing is reported by Venice already
/// in USD per 1,000,000 tokens ("Prices per 1M tokens unless noted" —
/// https://docs.venice.ai/overview/pricing), so no unit conversion is
/// needed here.
struct VeniceModelCatalogFetcher: ModelCatalogFetching {
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

    func fetchModels(apiKey: String) async -> ModelCatalogFetchOutcome {
        var components = URLComponents(url: baseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "type", value: "text")]

        var request = URLRequest(url: components.url!)
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
            guard let entries = ModelCatalogDecoding.topLevelDataArray(from: data) else {
                return .unrecognizedResponse("Venice returned an unexpected response body.")
            }
            let models = entries.compactMap(decodeEntry)
            return .success(models)
        case 401, 403:
            return .invalidCredential
        default:
            return .unrecognizedResponse("Venice returned HTTP \(response.statusCode).")
        }
    }

    /// Decodes one raw catalog entry into a `ModelInfo`, or returns `nil`
    /// if the entry is missing the minimum fields needed to identify and
    /// display a model (currently just `id`). Per the brief, one
    /// malformed entry must not discard the rest of the catalog.
    private func decodeEntry(_ entry: [String: Any]) -> ModelInfo? {
        guard let id = entry["id"] as? String else { return nil }
        let spec = entry["model_spec"] as? [String: Any] ?? [:]
        let capabilities = spec["capabilities"] as? [String: Any] ?? [:]
        let pricing = spec["pricing"] as? [String: Any] ?? [:]

        let name = spec["name"] as? String ?? id
        let contextLength = ModelCatalogDecoding.int(spec["availableContextTokens"])
        let privacy = spec["privacy"] as? String

        let inputUSD = ModelCatalogDecoding.decimal((pricing["input"] as? [String: Any])?["usd"])
        let outputUSD = ModelCatalogDecoding.decimal((pricing["output"] as? [String: Any])?["usd"])

        return ModelInfo(
            identity: ModelIdentity(service: .venice, modelID: id),
            displayName: name,
            contextLength: contextLength,
            maxOutputTokens: nil, // Not present in Venice's documented model_spec schema as of this stage.
            pricing: ModelPricing(
                inputPerMillionTokensUSD: inputUSD,
                outputPerMillionTokensUSD: outputUSD
            ),
            supportsTools: CapabilitySupport.from(capabilities["supportsFunctionCalling"] as? Bool),
            supportsReasoning: CapabilitySupport.from(capabilities["supportsReasoning"] as? Bool),
            supportsVision: CapabilitySupport.from(capabilities["supportsVision"] as? Bool),
            privacyDescription: privacy
        )
    }
}
