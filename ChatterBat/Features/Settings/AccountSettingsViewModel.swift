import Foundation
import Observation

/// Drives the Venice/OpenRouter account connection UI in Settings.
///
/// Owns no networking or Keychain code directly — it depends on
/// `CredentialStore` and `ConnectionChecking` abstractions so it can be
/// unit-tested with fakes (see `ChatterBatTests/AccountSettingsViewModelTests.swift`)
/// without touching the real Keychain or network.
@Observable
@MainActor
final class AccountSettingsViewModel {
    private(set) var connectionStates: [AIService: ConnectionState] = [
        .venice: .notConfigured,
        .openRouter: .notConfigured
    ]

    /// Transient, in-memory key-entry text per service. Cleared after a
    /// successful save; never persisted anywhere but Keychain.
    var draftKeys: [AIService: String] = [:]

    private let credentialStore: CredentialStore
    private let checkers: [AIService: ConnectionChecking]

    init(
        credentialStore: CredentialStore,
        checkers: [AIService: ConnectionChecking]
    ) {
        self.credentialStore = credentialStore
        self.checkers = checkers
    }

    func state(for service: AIService) -> ConnectionState {
        connectionStates[service] ?? .notConfigured
    }

    /// Loads persisted key presence for both services on launch/appear.
    /// Does not perform a network check automatically — verification is a
    /// separate, explicit user action (see `verifyConnection`), consistent
    /// with "no paid inference or network calls without explicit intent."
    func refreshStoredKeyPresence() {
        for service in AIService.allCases {
            let hasKey = (try? credentialStore.loadKey(for: service)).flatMap { $0 } != nil
            if !hasKey {
                connectionStates[service] = .notConfigured
            } else if case .notConfigured = connectionStates[service] ?? .notConfigured {
                // A key exists but hasn't been verified this session yet.
                // Reflect that honestly rather than claiming "connected."
                connectionStates[service] = .error("Saved, not yet verified.")
            }
        }
    }

    /// Saves the current draft key for `service` to Keychain, then
    /// immediately verifies it against the provider's non-billable status
    /// endpoint.
    func saveAndVerify(_ service: AIService) async {
        let draft = draftKeys[service] ?? ""
        do {
            try credentialStore.saveKey(draft, for: service)
        } catch CredentialStoreError.emptyKey {
            connectionStates[service] = .error("Enter an API key before saving.")
            return
        } catch {
            connectionStates[service] = .error("Could not save the key to Keychain.")
            return
        }
        draftKeys[service] = nil
        await verifyConnection(service)
    }

    /// Re-runs the non-billable connection check for a key already in
    /// Keychain.
    func verifyConnection(_ service: AIService) async {
        guard let checker = checkers[service] else { return }
        guard let key = (try? credentialStore.loadKey(for: service)) ?? nil else {
            connectionStates[service] = .notConfigured
            return
        }

        connectionStates[service] = .checking
        let outcome = await checker.checkConnection(apiKey: key)

        switch outcome {
        case .valid(let summary):
            connectionStates[service] = .connected(summary: summary)
        case .invalidCredential:
            connectionStates[service] = .invalidCredential
        case .transportFailure(let message):
            connectionStates[service] = .error("Network error: \(message)")
        case .unrecognizedResponse(let message):
            connectionStates[service] = .error(message)
        }
    }

    /// Removes the stored key for `service`. This only disables new
    /// requests through that account; it never touches conversation
    /// history (a separate, later-stage concern).
    func disconnect(_ service: AIService) {
        try? credentialStore.deleteKey(for: service)
        connectionStates[service] = .notConfigured
        draftKeys[service] = nil
    }
}
