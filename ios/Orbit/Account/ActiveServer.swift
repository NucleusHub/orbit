import Foundation
import os

/// The server this app signs in to and what discovery found; in the Keychain because it holds the code.
struct ServerConfig: Codable, Equatable {
    var server: NucleusServer
    var endpoints: NucleusEndpoints

    /// Every session saved before servers could be picked is on nucleus-home.dev.
    static let legacy: ServerConfig = {
        let server = NucleusServer(host: "nucleus-home.dev")
        return ServerConfig(server: server, endpoints: .derived(from: server.origin))
    }()

    static func resolve(saved: Data?, hasSession: Bool) -> ServerConfig? {
        // Undecodable saved data never falls back to nucleus-home.dev: tokens could go to the wrong server.
        if let saved { return try? JSONDecoder().decode(ServerConfig.self, from: saved) }
        return hasSession ? legacy : nil
    }
}

/// Read from anywhere (sync, cross-app, sign-in); changed only by `NucleusID.use(_:)`.
enum ActiveServer {
    private static let current = OSAllocatedUnfairLock<ServerConfig?>(initialState: {
        let saved = Keychain.get(.nucleusServer)
        let config = ServerConfig.resolve(saved: saved, hasSession: Keychain.get(.nucleusSession) != nil)
        if config == nil, saved != nil {
            Keychain.delete(.nucleusServer)
            Keychain.delete(.nucleusSession)
        }
        if let config, Keychain.get(.nucleusServer) == nil, let data = try? JSONEncoder().encode(config) {
            Keychain.set(data, for: .nucleusServer)
        }
        return config
    }())

    static var config: ServerConfig? { current.withLock { $0 } }

    /// Puts back an earlier state, including none; for tests.
    static func restore(_ config: ServerConfig?) { current.withLock { $0 = config } }

    static func use(_ config: ServerConfig) {
        if let data = try? JSONEncoder().encode(config) { Keychain.set(data, for: .nucleusServer) }
        current.withLock { $0 = config }
    }
}
