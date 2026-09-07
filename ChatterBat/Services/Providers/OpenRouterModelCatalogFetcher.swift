import Foundation

/// Fetches OpenRouter's text-model catalog via `GET /models`.
///
/// OpenRouter's `output_modalities` query parameter defaults to `text`
/// when omitted ("Default (text models only)" —
/// https://openrouter.ai/docs/guides/overview/models, retrieved during
/// Stage 2 implementation), so no explicit parameter is required to
/// exclude image/audio/embedding-only models. Pricing (`pricing.prompt`
/// / `pricing.completion`) is reported as a *string* in USD per single
/// token (e.g. `"0.00003"`); this fetcher multiplies by 1,000,000 to
/// normalize into `ModelPricing`'s USD-per-million-tokens convention.
struct OpenRouterModelCatalogFetcher: ModelCatalogFetching {
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

    func fetchModels(apiKey: String) async -> ModelCatalogFetchOutcome {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
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
                return .unrecognizedResponse("OpenRouter returned an unexpected response body.")
            }
            let models = entries.compactMap(decodeEntry)
            return .success(models)
        case 401, 403:
            return .invalidCredential
        default:
            return .unrecognizedResponse("OpenRouter returned HTTP \(response.statusCode).")
        }
    }

    private func decodeEntry(_ entry: [String: Any]) -> ModelInfo? {
        guard let id = entry["id"] as? String else { return nil }

        let name = entry["name"] as? String ?? id
        let contextLength = ModelCatalogDecoding.int(entry["context_length"])
        let topProvider = entry["top_provider"] as? [String: Any]
        let maxOutputTokens = ModelCatalogDecoding.int(topProvider?["max_completion_tokens"])

        let pricing = entry["pricing"] as? [String: Any] ?? [:]
        let promptPerToken = ModelCatalogDecoding.decimal(pricing["prompt"])
        let completionPerToken = ModelCatalogDecoding.decimal(pricing["completion"])
        let million = Decimal(1_000_000)

        let supportedParameters = entry["supported_parameters"] as? [String] ?? []
        let supportsTools = supportedParameters.contains("tools")
            ? CapabilitySupport.supported
            : (entry["supported_parameters"] != nil ? .unsupported : .unknown)
        let supportsReasoning = supportedParameters.contains("reasoning")
            ? CapabilitySupport.supported
            : (entry["supported_parameters"] != nil ? .unsupported : .unknown)

        let architecture = entry["architecture"] as? [String: Any]
        let inputModalities = architecture?["input_modalities"] as? [String] ?? []
        let supportsVision: CapabilitySupport = architecture == nil
            ? .unknown
            : (inputModalities.contains("image") ? .supported : .unsupported)

        return ModelInfo(
            identity: ModelIdentity(service: .openRouter, modelID: id),
            displayName: name,
            contextLength: contextLength,
            maxOutputTokens: maxOutputTokens,
            pricing: ModelPricing(
                inputPerMillionTokensUSD: promptPerToken.map { $0 * million },
                outputPerMillionTokensUSD: completionPerToken.map { $0 * million }
            ),
            supportsTools: supportsTools,
            supportsReasoning: supportsReasoning,
            supportsVision: supportsVision,
            privacyDescription: nil // OpenRouter has no per-model privacy label like Venice's.
        )
    }
}
