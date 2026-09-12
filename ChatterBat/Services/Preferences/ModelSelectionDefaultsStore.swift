import Foundation

protocol ModelSelectionDefaultsStore: Sendable {
    func load() -> ModelSelectionDefaults
    func save(_ selection: ModelSelectionDefaults)
}

/// Only non-secret selection policy. No keys, prompts, or transcripts.
final class UserDefaultsModelSelectionDefaultsStore: ModelSelectionDefaultsStore, @unchecked Sendable {
    static let storageKey = "com.chatterbat.app.modelSelectionDefaults.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> ModelSelectionDefaults {
        guard let data = defaults.data(forKey: Self.storageKey),
              let value = try? JSONDecoder().decode(ModelSelectionDefaults.self, from: data),
              value.isValid else { return ModelSelectionDefaults() }
        return value
    }

    func save(_ selection: ModelSelectionDefaults) {
        guard selection.isValid, let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}