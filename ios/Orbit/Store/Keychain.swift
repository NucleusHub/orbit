import Foundation
import Security

/// Thin keychain wrapper. Items are this-device-only and never synced to iCloud Keychain.
enum Keychain {
    private static let service = "com.nucleushome.orbit"

    enum Slot: String {
        case nucleusSession = "nucleus-id.session"
        case nucleusServer = "nucleus-id.server"
        /// Orbit passwords of Face ID-locked items, so Face ID can stand in for typing them.
        case itemPasswords = "orbit.item-passwords"
    }

    static func set(_ data: Data, for slot: Slot) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: slot.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        // After first unlock, so a sync can still refresh tokens in the background.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ slot: Slot) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: slot.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ slot: Slot) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: slot.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Wipes every item this app ever stored.
    static func deleteEverything() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
