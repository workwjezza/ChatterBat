import XCTest

final class ProbeProtocolTests: XCTestCase {
    func testPingRoundTripsExactNonce() throws {
        let nonce = UUID()
        let request = try JSONEncoder().encode(ProbePing(version: 1, nonce: nonce))
        XCTAssertTrue(ProbeCodec.validate(ProbeCodec.respond(to: request), nonce: nonce))
        XCTAssertFalse(ProbeCodec.validate(ProbeCodec.respond(to: request), nonce: UUID()))
    }

    func testUnsupportedVersionFailsClosed() throws {
        let nonce = UUID()
        let data = ProbeCodec.respond(to: try JSONEncoder().encode(ProbePing(version: 2, nonce: nonce)))
        XCTAssertFalse(ProbeCodec.validate(data, nonce: nonce))
        XCTAssertEqual(try JSONDecoder().decode(ProbePong.self, from: data).status, "unsupported_version")
    }

    func testMalformedAndOversizedPayloadsAreRejected() throws {
        for input in [Data(), Data("{}".utf8), Data("not-json".utf8)] {
            let reply = ProbeCodec.respond(to: input)
            XCTAssertEqual(try JSONDecoder().decode(ProbePong.self, from: reply).status, "malformed")
        }
        let reply = ProbeCodec.respond(to: Data(count: ProbeCodec.maximumBytes + 1))
        XCTAssertEqual(try JSONDecoder().decode(ProbePong.self, from: reply).status, "too_large")
        XCTAssertLessThan(reply.count, ProbeCodec.maximumBytes)
    }

    func testReplySizeAndVersionAreChecked() throws {
        let nonce = UUID()
        XCTAssertFalse(ProbeCodec.validate(Data(count: ProbeCodec.maximumBytes + 1), nonce: nonce))
        XCTAssertFalse(ProbeCodec.validate(Data(), nonce: nonce))
        let future = try JSONEncoder().encode(ProbePong(version: 2, nonce: nonce, status: "pong"))
        XCTAssertFalse(ProbeCodec.validate(future, nonce: nonce))
    }

    func testSigningRequirementsParseAndPinBothIdentityAndTeam() throws {
        let requirement = try XCTUnwrap(ProbeIdentity.requirement(identifier: ProbeIdentity.service))
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains(ProbeIdentity.service))
        XCTAssertTrue(requirement.contains(ProbeIdentity.team))
        XCTAssertNotEqual(requirement, ProbeIdentity.requirement(identifier: ProbeIdentity.client))
    }

    func testRequirementInjectionAndMissingIdentityRejected() {
        for identifier in ["", "\" or true", "x\\y", String(repeating: "x", count: 129)] {
            XCTAssertNil(ProbeIdentity.requirement(identifier: identifier))
        }
        XCTAssertNil(ProbeIdentity.requirement(identifier: "valid", team: ""))
        XCTAssertNil(ProbeIdentity.requirement(identifier: "valid", team: "A\" or true"))
    }

    func testHostAllowlistPinsOnlyStandaloneAppAndCLI() throws {
        let requirement = try XCTUnwrap(ProbeIdentity.hostClientRequirement())
        XCTAssertTrue(requirement.contains(ProbeIdentity.standaloneClient))
        XCTAssertTrue(requirement.contains(ProbeIdentity.cli))
        XCTAssertFalse(requirement.contains(".rejected"))
        XCTAssertTrue(requirement.contains(" or "))
        XCTAssertEqual(requirement.components(separatedBy: "anchor apple generic").count - 1, 2)
        XCTAssertEqual(requirement.components(separatedBy: ProbeIdentity.team).count - 1, 2)
    }

    func testMachServiceUsesDocumentedGroupPrefixAndDistinctIdentity() {
        XCTAssertTrue(ProbeIdentity.group.hasPrefix(ProbeIdentity.team + "."))
        XCTAssertTrue(ProbeIdentity.machService.hasPrefix(ProbeIdentity.group + "."))
        XCTAssertLessThan(ProbeIdentity.machService.utf8.count, 128)
        XCTAssertNotEqual(ProbeIdentity.host, ProbeIdentity.service)
        XCTAssertNotEqual(ProbeIdentity.standaloneClient, ProbeIdentity.client)
    }
}