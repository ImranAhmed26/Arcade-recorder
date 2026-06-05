import Foundation
import Security

/// Minimal generic-password Keychain wrapper. Stores arbitrary `Data` under a
/// service + account key. Used to persist the auth session securely.
enum KeychainStore {
    static let service = "com.binate.arcade.auth"

    @discardableResult
    static func save(_ data: Data, account: String) -> Bool {
        // Replace any existing item.
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Codable convenience

    static func saveCodable<T: Encodable>(_ value: T, account: String) {
        if let data = try? JSONEncoder().encode(value) { save(data, account: account) }
    }

    static func loadCodable<T: Decodable>(_ type: T.Type, account: String) -> T? {
        guard let data = load(account: account) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
