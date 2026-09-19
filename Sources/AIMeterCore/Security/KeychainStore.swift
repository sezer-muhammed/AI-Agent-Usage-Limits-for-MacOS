import Foundation
import Security

/// The only place a provider secret is allowed to live.
///
/// Never UserDefaults, never SQLite, never the widget's App Group container,
/// never a log line.
public actor KeychainStore {
    public enum CredentialKey: String, Sendable, CaseIterable {
        case openRouterAPIKey = "openrouter-api-key"
    }

    public enum KeychainError: Error, Sendable {
        case unexpectedStatus(OSStatus)
        case dataCorrupted
    }

    private let service: String

    public init(service: String = "com.sezer-muhammed.aimeter.credentials") {
        self.service = service
    }

    public func setSecret(_ value: String, for key: CredentialKey) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.dataCorrupted }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }

    public func secret(for key: CredentialKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataCorrupted
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func deleteSecret(for key: CredentialKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Settings shows this instead of ever revealing a stored key again.
    public nonisolated static func redacted(_ secret: String) -> String {
        let suffix = secret.suffix(4)
        return suffix.isEmpty ? "••••" : "••••\(suffix)"
    }
}
