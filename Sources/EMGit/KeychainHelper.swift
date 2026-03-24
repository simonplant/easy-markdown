import Foundation
import Security
import EMCore

/// Manages Keychain storage for GitHub OAuth tokens per [A-064].
/// Tokens are stored in the Keychain (not UserDefaults) as they are credentials.
public struct KeychainHelper: Sendable {
    private let service: String

    /// Creates a KeychainHelper scoped to the given service identifier.
    public init(service: String = "com.easymarkdown.github") {
        self.service = service
    }

    /// Saves a token string to the Keychain under the given account key.
    /// Overwrites any existing value for the same account.
    public func save(token: String, account: String) throws {
        guard let data = token.data(using: .utf8) else { return }

        // Delete any existing item first to avoid errSecDuplicateItem.
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw EMError.git(.keychainAccessFailed(
                underlying: KeychainError.unhandledError(status: status)
            ))
        }
    }

    /// Reads a token string from the Keychain for the given account key.
    /// Returns nil if no token is stored.
    public func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return token
    }

    /// Deletes the token for the given account key from the Keychain.
    @discardableResult
    public func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Internal Keychain error for wrapping Security framework status codes.
enum KeychainError: Error {
    case unhandledError(status: OSStatus)
}
