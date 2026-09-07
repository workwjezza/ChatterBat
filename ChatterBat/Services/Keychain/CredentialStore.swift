import Foundation

/// Errors surfaced by a `CredentialStore` implementation.
enum CredentialStoreError: Error, Equatable, Sendable {
    /// The caller attempted to save an empty (or whitespace-only) key.
    case emptyKey
    /// The underlying store reported an unexpected failure. `status` is the
    /// raw `OSStatus` for Keychain-backed implementations, or a synthetic
    /// negative value for non-Keychain implementations used in tests.
    case unexpectedStatus(OSStatus)
}

/// Abstraction over secure storage of provider API keys.
///
/// Per the brief: API keys are stored only in Keychain (or, for tests, an
/// isolated in-memory double) — never in UserDefaults, SwiftData, logs, or
/// source. This protocol lets `AccountSettingsViewModel` and provider
/// verification code depend on an interface rather than the Security
/// framework directly, so tests never touch the real Keychain.
protocol CredentialStore: Sendable {
    /// Stores `key` for `service`, replacing any existing value.
    /// Throws `CredentialStoreError.emptyKey` if `key` is empty or
    /// whitespace-only after trimming.
    func saveKey(_ key: String, for service: AIService) throws

    /// Returns the stored key for `service`, or `nil` if none exists.
    func loadKey(for service: AIService) throws -> String?

    /// Removes any stored key for `service`. Not an error if none exists.
    func deleteKey(for service: AIService) throws
}
