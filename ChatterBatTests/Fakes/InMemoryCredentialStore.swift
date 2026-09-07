import Foundation
@testable import ChatterBat

/// In-memory `CredentialStore` double used by tests. Never touches the
/// real Keychain — this is what makes `AccountSettingsViewModelTests` safe
/// to run in CI without special entitlements or cleanup.
final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var storage: [AIService: String] = [:]

    func saveKey(_ key: String, for service: AIService) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CredentialStoreError.emptyKey }
        storage[service] = trimmed
    }

    func loadKey(for service: AIService) throws -> String? {
        storage[service]
    }

    func deleteKey(for service: AIService) throws {
        storage[service] = nil
    }
}
