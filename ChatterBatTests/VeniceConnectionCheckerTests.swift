import XCTest
@testable import ChatterBat

final class VeniceConnectionCheckerTests: XCTestCase {
    func testValidKeyDecodesSummaryFromBalancesAndTier() async {
        let body = Data("""
        {"data":{"accessPermitted":true,"apiTier":"paid","balances":{"USD":50.23,"DIEM":100.02},"keyExpiration":null,"nextEpochBegins":"2025-05-07T00:00:00.000Z","rateLimits":[]}}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let checker = VeniceConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "venice-test-key")

        XCTAssertEqual(outcome, .valid(summary: "Connected · $50.23 USD · paid tier"))
    }

    func testValidKeyWithMissingOptionalFieldsStillReportsConnected() async {
        let body = Data("""
        {"data":{}}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let checker = VeniceConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "venice-test-key")

        XCTAssertEqual(outcome, .valid(summary: "Connected"))
    }

    func test401MapsToInvalidCredential() async {
        let http = FakeHTTPClient(scripted: .success(status: 401, body: Data()))
        let checker = VeniceConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "bad-key")

        XCTAssertEqual(outcome, .invalidCredential)
    }

    func testTransportFailureMapsToTransportFailure() async {
        let http = FakeHTTPClient(scripted: .failure(FakeTransportError()))
        let checker = VeniceConnectionChecker(httpClient: http)

        let outcome = await checker.checkConnection(apiKey: "any-key")

        guard case .transportFailure = outcome else {
            return XCTFail("Expected transportFailure, got \(outcome)")
        }
    }

    func testRequestIsBuiltWithBearerAuthAndCorrectPath() async {
        let body = Data("""
        {"data":{}}
        """.utf8)
        let http = FakeHTTPClient(scripted: .success(status: 200, body: body))
        let checker = VeniceConnectionChecker(httpClient: http)

        _ = await checker.checkConnection(apiKey: "my-secret-key")

        let request = http.lastRequest
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.url?.absoluteString, "https://api.venice.ai/api/v1/api_keys/rate_limits")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-key")
    }
}
