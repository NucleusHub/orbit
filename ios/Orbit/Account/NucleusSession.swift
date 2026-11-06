import Foundation

/// A signed-in Nucleus ID session, kept in the keychain.
struct NucleusSession: Codable, Equatable {
    struct User: Codable, Equatable {
        var sub: String
        var handle: String
        var name: String
        var email: String?
    }

    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var user: User
    /// What the account granted, from the token response; nil in sessions saved before it was kept.
    var scopes: [String]?

    static func load() -> NucleusSession? {
        Keychain.get(.nucleusSession).flatMap { try? JSONDecoder().decode(NucleusSession.self, from: $0) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { Keychain.set(data, for: .nucleusSession) }
    }

    static func clear() { Keychain.delete(.nucleusSession) }
}
