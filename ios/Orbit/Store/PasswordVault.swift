import Foundation

/// Orbit passwords of Face ID-locked items on this device. The server needs the password itself, so after
/// it's typed once, passing Face ID fills it in.
protocol PasswordVault: AnyObject {
    func password(for itemID: String) -> String?
    func save(_ password: String, for itemID: String)
    func remove(_ itemID: String)
    func removeAll()
}

/// In the keychain, this device only (never iCloud Keychain); signing out wipes it.
final class KeychainVault: PasswordVault {
    private var map: [String: String] {
        get { Keychain.get(.itemPasswords).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:] }
        set {
            if newValue.isEmpty { Keychain.delete(.itemPasswords) } else if let data = try? JSONEncoder().encode(newValue) { Keychain.set(data, for: .itemPasswords) }
        }
    }

    func password(for itemID: String) -> String? { map[itemID] }
    func save(_ password: String, for itemID: String) { map[itemID] = password }
    func remove(_ itemID: String) { map[itemID] = nil }
    func removeAll() { map = [:] }
}

final class MemoryVault: PasswordVault {
    private var map: [String: String] = [:]
    func password(for itemID: String) -> String? { map[itemID] }
    func save(_ password: String, for itemID: String) { map[itemID] = password }
    func remove(_ itemID: String) { map[itemID] = nil }
    func removeAll() { map = [:] }
}
