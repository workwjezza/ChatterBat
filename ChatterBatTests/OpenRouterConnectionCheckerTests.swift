import XCTest
@testable import ChatterBat

final class OpenRouterConnectionCheckerTests: XCTestCase {
    func testValidKeyDecodesSummaryFromLimitRemaining() async {
        let body = Data("""
        {"data":{"label":"test","limit":100,"limit_remaining":42.5,"usage":57.5,"is_free_tier":false}}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let checker = OpenRouterConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "sk-or-test")

        XCTAssertEqual(outcome, .valid(summary: "Connected · $42.50 credits remaining"))
    }

    func testValidKeyWithNullLimitRemainingFallsBackToUsage() async {
        let body = Data("""
        {"data":{"label":"test","limit":null,"limit_remaining":null,"usage":12.0}}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let checker = OpenRouterConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "sk-or-test")

        XCTAssertEqual(outcome, .valid(summary: "Connected · $12.00 credits used"))
    }

    func test401MapsToInvalidCredential() async {
        let http = FakeHTTPClient(scripted: .success(status: 401, body: Data()))
        let checker = OpenRouterConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "bad-key")

        XCTAssertEqual(outcome, .invalidCredential)
    }

    func test403MapsToInvalidCredential() async {
        let http = FakeHTTPClient(scripted: .success(status: 403, body: Data()))
        let checker = OpenRouterConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "bad-key")

        XCTAssertEqual(outcome, .invalidCredential)
    }

    func testUnexpectedStatusMapsToUnrecognizedResponse() async {
        let http = FakeHTTPClient(scripted: .success(status: 500, body: Data()))
        let checker = OpenRouterConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "any-key")

        guard case .unrecognizedResponse = outcome else {
            return XCTFail("Expected unrecognizedResponse, got \(outcome)")
        }
    }

    func testMalformedBodyOn200MapsToUnrecognizedResponse() async {
        let http = FakeHTTPClient(scripted: .success(status: 200, body: Data("not json".utf8)))
        let checker = OpenRouterConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "any-key")

        guard case .unrecognizedResponse = outcome else {
            return XCTFail("Expected unrecognizedResponse, got \(outcome)")
        }
    }

    func testTransportFailureMapsToTransportFailure() async {
        let http = FakeHTTPClient(scripted: .failure(FakeTransportError()))
        let checker = OpenRouterConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "any-key")

        guard case .transportFailure = outcome else {
            return XCTFail("Expected transportFailure, got \(outcome)")
        }
    }

    func testRequestIsBuiltWithBearerAuthAndCorrectPath() async {
        let body = Data("""
        {"data":{"label":"test"}}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let checker = OpenRouterConnectionChecker(httpClient: http)

        _ = await checker.checkConnection(apiKey: "my-secret-key")

        let request = http.lastRequest
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.url?.absoluteString, "https://openrouter.ai/api/v1/key")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-key")
    }
}
