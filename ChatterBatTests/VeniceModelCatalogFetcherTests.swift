import XCTest
@testable import ChatterBat

final class VeniceModelCatalogFetcherTests: XCTestCase {
    func testDecodesFullEntryFromDocumentedExampleShape() async {
        // This mirrors the exact example object published at
        // https://docs.venice.ai/api-reference/endpoint/models/list
        // (retrieved during Stage 2 implementation), so this test fails if
        // ChatterBat's field names ever drift from that documented shape.
        let body = Data("""
        {"data":[{"created":1727966436,"id":"llama-3.2-3b","model_spec":{"availableContextTokens":131072,"capabilities":{"optimizedForCode":false,"supportsFunctionCalling":true,"supportsReasoning":false,"supportsVision":false,"supportsWebSearch":true},"description":"Compact","name":"Llama 3.2 3B","offline":false,"privacy":"private","pricing":{"input":{"usd":0.15,"diem":0.15},"output":{"usd":0.6,"diem":0.6}},"traits":["fastest"]},"object":"model","owned_by":"venice.ai","type":"text"}],"object":"list","type":"text"}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let fetcher = VeniceModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "test-key")

        guard case .success(let models) = outcome, let model = models.first else {
            return XCTFail("Expected a decoded model, got \(outcome)")
        }
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(model.identity, ModelIdentity(service: .venice, modelID: "llama-3.2-3b"))
        XCTAssertEqual(model.displayName, "Llama 3.2 3B")
        XCTAssertEqual(model.contextLength, 131_072)
        XCTAssertEqual(model.pricing.inputPerMillionTokensUSD, 0.15)
        XCTAssertEqual(model.pricing.outputPerMillionTokensUSD, 0.6)
        XCTAssertEqual(model.supportsTools, .supported)
        XCTAssertEqual(model.supportsReasoning, .unsupported)
        XCTAssertEqual(model.supportsVision, .unsupported)
        XCTAssertEqual(model.privacyDescription, "private")
    }

    func testEntryMissingIdIsSkippedWithoutDiscardingOthers() async {
        let body = Data("""
        {"data":[{"model_spec":{}},{"id":"valid-model","model_spec":{}}]}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let fetcher = VeniceModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "test-key")

        guard case .success(let models) = outcome else {
            return XCTFail("Expected success, got \(outcome)")
        }
        XCTAssertEqual(models.map(\.modelID), ["valid-model"])
    }

    func testMissingCapabilitiesAndPricingMapToUnknownNotUnsupportedOrZero() async {
        let body = Data("""
        {"data":[{"id":"bare-model"}]}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let fetcher = VeniceModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "test-key")

        guard case .success(let models) = outcome, let model = models.first else {
            return XCTFail("Expected a decoded model, got \(outcome)")
        }
        XCTAssertEqual(model.supportsTools, .unknown)
        XCTAssertEqual(model.supportsReasoning, .unknown)
        XCTAssertEqual(model.supportsVision, .unknown)
        XCTAssertNil(model.pricing.inputPerMillionTokensUSD)
        XCTAssertNil(model.pricing.outputPerMillionTokensUSD)
        XCTAssertNil(model.contextLength)
        XCTAssertNil(model.privacyDescription)
    }

    func test401MapsToInvalidCredential() async {
        let http = FakeHTTPClient(scripted: .success(status: 401, body: Data()))
        let fetcher = VeniceModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "bad-key")

        guard case .invalidCredential = outcome else {
            return XCTFail("Expected invalidCredential, got \(outcome)")
        }
    }

    func testRequestUsesTypeTextQueryParameterAndBearerAuth() async {
        let http = FakeHTTPClient(scripted: .success(status: 200, body: Data("{\"data\":[]}".utf8)))
        let fetcher = VeniceModelCatalogFetcher(httpClient: http)

        _ = await fetcher.fetchModels(apiKey: "my-secret-key")

        let request = http.lastRequest
        XCTAssertEqual(request?.url?.absoluteString, "https://api.venice.ai/api/v1/models?type=text")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-key")
    }

    func testTransportFailureMapsToTransportFailure() async {
        let http = FakeHTTPClient(scripted: .failure(FakeTransportError()))
        let fetcher = VeniceModelCatalogFetcher(httpClient: http)

        let outcome = await fetcher.fetchModels(apiKey: "any-key")

        guard case .transportFailure = outcome else {
            return XCTFail("Expected transportFailure, got \(outcome)")
        }
    }
}
