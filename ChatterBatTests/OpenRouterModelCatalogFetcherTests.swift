import XCTest
@testable import ChatterBat

final class OpenRouterModelCatalogFetcherTests: XCTestCase {
    func testDecodesEntryAndConvertsPerTokenPricingToPerMillion() async {
        // Mirrors the documented example shape at
        // https://openrouter.ai/docs/api-reference/models/get-models
        // (retrieved during Stage 2 implementation): pricing is a numeric
        // string in USD per single token.
        let body = Data("""
        {"data":[{"id":"openai/gpt-4","canonical_slug":"openai/gpt-4","name":"GPT-4","context_length":8192,"architecture":{"input_modalities":["text"],"output_modalities":["text"]},"pricing":{"prompt":"0.00003","completion":"0.00006"},"supported_parameters":["tools","temperature"],"top_provider":{"context_length":8192,"max_completion_tokens":4096,"is_moderated":true}}]}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let fetcher = OpenRouterModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "test-key")

        guard case .success(let models) = outcome, let model = models.first else {
            return XCTFail("Expected a decoded model, got \(outcome)")
        }
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(model.identity, ModelIdentity(service: .openRouter, modelID: "openai/gpt-4"))
        XCTAssertEqual(model.displayName, "GPT-4")
        XCTAssertEqual(model.contextLength, 8192)
        XCTAssertEqual(model.maxOutputTokens, 4096)
        XCTAssertEqual(model.pricing.inputPerMillionTokensUSD, 30)
        XCTAssertEqual(model.pricing.outputPerMillionTokensUSD, 60)
        XCTAssertEqual(model.supportsTools, .supported)
        XCTAssertEqual(model.supportsVision, .unsupported, "input_modalities lacks 'image'")
        XCTAssertNil(model.privacyDescription, "OpenRouter models never carry Venice-style privacy labels")
    }

    func testEntryMissingIdIsSkippedWithoutDiscardingOthers() async {
        let body = Data("""
        {"data":[{"name":"no id"},{"id":"valid/model"}]}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let fetcher = OpenRouterModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "test-key")

        guard case .success(let models) = outcome else {
            return XCTFail("Expected success, got \(outcome)")
        }
        XCTAssertEqual(models.map(\.modelID), ["valid/model"])
    }

    func testMissingArchitectureAndSupportedParametersMapToUnknown() async {
        let body = Data("""
        {"data":[{"id":"bare/model"}]}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let fetcher = OpenRouterModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "test-key")

        guard case .success(let models) = outcome, let model = models.first else {
            return XCTFail("Expected a decoded model, got \(outcome)")
        }
        XCTAssertEqual(model.supportsTools, .unknown)
        XCTAssertEqual(model.supportsReasoning, .unknown)
        XCTAssertEqual(model.supportsVision, .unknown)
        XCTAssertNil(model.pricing.inputPerMillionTokensUSD)
        XCTAssertNil(model.pricing.outputPerMillionTokensUSD)
    }

    func testVisionCapableModelReportsSupportedWhenImageInInputModalities() async {
        let body = Data("""
        {"data":[{"id":"openai/gpt-4o","architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}}]}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let fetcher = OpenRouterModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "test-key")

        guard case .success(let models) = outcome, let model = models.first else {
            return XCTFail("Expected a decoded model, got \(outcome)")
        }
        XCTAssertEqual(model.supportsVision, .supported)
    }

    func test401MapsToInvalidCredential() async {
        let http = FakeHTTPClient(scripted: .success(status: 401, body: Data()))
        let fetcher = OpenRouterModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "bad-key")

        guard case .invalidCredential = outcome else {
            return XCTFail("Expected invalidCredential, got \(outcome)")
        }
    }

    func testRequestUsesBearerAuthAndCorrectPath() async {
        let http = FakeHTTPClient(scripted: .success(status: 200, body: Data("{\"data\":[]}".utf8)))
        let fetcher = OpenRouterModelCatalogFetcher(httpClient: http)

        _ = await fetcher.fetchModels(apiKey: "my-secret-key")

        let request = http.lastRequest
        XCTAssertEqual(request?.url?.absoluteString, "https://openrouter.ai/api/v1/models")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-key")
    }

    func testTransportFailureMapsToTransportFailure() async {
        let http = FakeHTTPClient(scripted: .failure(FakeTransportError()))
        let fetcher = OpenRouterModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "any-key")

        guard case .transportFailure = outcome else {
            return XCTFail("Expected transportFailure, got \(outcome)")
        }
    }
}
