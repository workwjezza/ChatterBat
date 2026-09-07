import Foundation
import Security

/// `CredentialStore` backed by the macOS Keychain.
///
/// Each service's key is stored as a generic password item scoped by
/// `service` (a fixed app-specific string) and `account` (the `AIService`
/// raw value), so Venice and OpenRouter keys never collide and are
/// independently addable/removable. Access is not synced to iCloud and is
/// restricted to `.whenUnlockedThisDeviceOnly`, which is appropriate for a
/// local-only credential with no cross-device sync feature.
struct KeychainCredentialStore: CredentialStore {
    /// The fixed Keychain "service" (item namespace) for all ChatterBat
    /// credentials, distinct per bundle so multiple installs/schemes don't
    /// collide.
    private let keychainService: String

    init(keychainService: String = "com.chatterbat.app.apikeys") {
        self.keychainService = keychainService
    }

    func saveKey(_ key: String, for service: AIService) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CredentialStoreError.emptyKey }
        let data = Data(trimmed.utf8)

        var query = baseQuery(for: service)
        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.unexpectedStatus(updateStatus)
        }
    }

    func loadKey(for service: AIService) throws -> String? {
        var query = baseQuery(for: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
                throw CredentialStoreError.unexpectedStatus(errSecDecode)
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    func deleteKey(for service: AIService) throws {
        let query = baseQuery(for: service)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for service: AIService) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.rawValue
        ]
    }
}
