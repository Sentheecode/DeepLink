import Foundation
import Security

// MARK: - Credential Store Protocol

public func isAllowedDeepSeekDomain(_ domain: String) -> Bool {
    domain == "platform.deepseek.com" || domain.hasSuffix(".platform.deepseek.com")
}

public enum ProviderID: String, Codable, Sendable {
    case deepseek
    case hermesKey
    case brokerKey
}

public protocol CredentialStore: Sendable {
    func saveToken(_ token: String, for provider: ProviderID) throws
    func getToken(for provider: ProviderID) throws -> String?
    func deleteToken(for provider: ProviderID) throws
    func hasToken(for provider: ProviderID) -> Bool
}

// MARK: - Keychain Implementation

public final class KeychainCredentialStore: CredentialStore {
    private let service = "com.deepseek.balance.credentials"

    public init() {}

    public func saveToken(_ token: String, for provider: ProviderID) throws {
        try deleteToken(for: provider)

        guard let data = token.data(using: .utf8) else { throw KeychainError.encodeFailed }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
        removeLegacyToken()
    }

    public func getToken(for provider: ProviderID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodeFailed
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.readFailed(status)
        }
    }

    public func deleteToken(for provider: ProviderID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    public func hasToken(for provider: ProviderID) -> Bool {
        (try? getToken(for: provider)) != nil
    }

    public func migrateLegacyTokenIfNeeded(for provider: ProviderID) throws {
        guard !hasToken(for: provider),
              let token = UserDefaults(suiteName: appGroupID)?.string(forKey: userTokenKey),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            removeLegacyToken()
            return
        }

        try saveToken(token, for: provider)
    }

    private func removeLegacyToken() {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: userTokenKey)
    }
}

// MARK: - Errors

public enum KeychainError: LocalizedError {
    case encodeFailed
    case decodeFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodeFailed: return "凭证编码失败"
        case .decodeFailed: return "凭证解码失败"
        case .saveFailed(let s): return "凭证保存失败 (\(s))"
        case .readFailed(let s): return "凭证读取失败 (\(s))"
        case .deleteFailed(let s): return "凭证删除失败 (\(s))"
        }
    }
}
