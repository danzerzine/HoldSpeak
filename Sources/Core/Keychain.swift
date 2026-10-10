import Foundation
import Security

/// Generic-password items for this app's secrets.
public enum Keychain {
    private static let service = "com.timmal.push-to-talk"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func string(for account: String) -> String? {
        try? read(account)
    }

    /// The stored value, nil when there is none; throws the status when the Keychain
    /// can't answer (locked, access denied), so callers don't take that for "no key".
    public static func read(_ account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            pttLog("Keychain read failed: \(status)")
            throw KeychainError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func set(_ value: String, for account: String) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else {
            pttLog("Keychain update failed: \(status)")
            return false
        }
        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(add as CFDictionary, nil)
        if added != errSecSuccess { pttLog("Keychain add failed: \(added)") }
        return added == errSecSuccess
    }

    public static func delete(_ account: String) {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound { pttLog("Keychain delete failed: \(status)") }
    }
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}
