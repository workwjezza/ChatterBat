import Foundation
import Security

/// Isolated E3 probe only; no production tools or credentials linked here.
@objc protocol ProbeServiceProtocol {
    func ping(_ request: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}

enum ProbeIdentity {
    static let client = "com.chatterbat.ipcprobe"
    static let service = "com.chatterbat.ipcprobe.service"
    static let host = "com.chatterbat.ipcprobe.host"
    static let standaloneClient = "com.chatterbat.ipcprobe.standalone"
    static let cli = "com.chatterbat.ipcprobe.cli"
    static let group = "AM3FXP5BXT.com.chatterbat.ipcprobe"
    static let machService = group + ".ping"
    /// Mirrors this repository's development team, not client-supplied data.
    static let team = "AM3FXP5BXT"

    static func requirement(identifier: String, team: String = team) -> String? {
        // Never interpolate untrusted requirement-language expressions.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard !identifier.isEmpty, identifier.utf8.count <= 128,
              !team.isEmpty, team.utf8.count <= 32,
              identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              team.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else { return nil }
        let value = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(value as CFString, [], &parsed) == errSecSuccess else { return nil }
        return value
    }

    static func hostClientRequirement() -> String? {
        guard let app = requirement(identifier: standaloneClient),
              let cli = requirement(identifier: cli) else { return nil }
        let value = "(\(app)) or (\(cli))"
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(value as CFString, [], &parsed) == errSecSuccess else { return nil }
        return value
    }
}

struct ProbePing: Codable, Equatable, Sendable {
    let version: Int
    let nonce: UUID
}

struct ProbePong: Codable, Equatable, Sendable {
    let version: Int
    let nonce: UUID?
    let status: String
}

enum ProbeCodec {
    static let version = 1
    static let maximumBytes = 1024

    static func respond(to data: Data) -> Data {
        let response: ProbePong
        if data.count > maximumBytes {
            response = ProbePong(version: version, nonce: nil, status: "too_large")
        } else if let request = try? JSONDecoder().decode(ProbePing.self, from: data) {
            response = request.version == version
                ? ProbePong(version: version, nonce: request.nonce, status: "pong")
                : ProbePong(version: version, nonce: nil, status: "unsupported_version")
        } else {
            response = ProbePong(version: version, nonce: nil, status: "malformed")
        }
        // This fixed Codable payload contains no unsupported JSON values.
        // Fail closed to empty bytes if encoding unexpectedly fails.
        return (try? JSONEncoder().encode(response)) ?? Data()
    }

    static func validate(_ data: Data, nonce: UUID) -> Bool {
        guard data.count <= maximumBytes,
              let response = try? JSONDecoder().decode(ProbePong.self, from: data) else { return false }
        return response == ProbePong(version: version, nonce: nonce, status: "pong")
    }
}