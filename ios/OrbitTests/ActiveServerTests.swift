import XCTest
@testable import Orbit

final class ActiveServerTests: XCTestCase {
    private let nas = NucleusServer(scheme: "http", host: "nas", port: 8080)

    func testSavedConfigWins() throws {
        let saved = ServerConfig(server: nas, endpoints: .derived(from: nas.origin))
        XCTAssertEqual(ServerConfig.resolve(saved: try JSONEncoder().encode(saved), hasSession: true), saved)
    }

    func testOldSessionIsOnNucleusHome() {
        let c = ServerConfig.resolve(saved: nil, hasSession: true)
        XCTAssertEqual(c?.server.origin.absoluteString, "https://nucleus-home.dev")
        XCTAssertEqual(c?.endpoints.token.absoluteString, "https://nucleus-home.dev/api/v1/oauth/token")
        XCTAssertNil(c?.server.code)
    }

    func testNothingSavedAndSignedOutMeansNoServer() {
        XCTAssertNil(ServerConfig.resolve(saved: nil, hasSession: false))
        XCTAssertNil(ServerConfig.resolve(saved: Data("junk".utf8), hasSession: false))
    }

    func testUndecodableSavedConfigNeverFallsBackToNucleusHome() {
        XCTAssertNil(ServerConfig.resolve(saved: Data("garbage".utf8), hasSession: true))
    }

    func testNucleusIDFollowsTheActiveServer() {
        let previous = ActiveServer.config
        let previousItem = Keychain.get(.nucleusServer)
        defer {
            ActiveServer.restore(previous)
            if let previousItem { Keychain.set(previousItem, for: .nucleusServer) } else { Keychain.delete(.nucleusServer) }
        }
        ActiveServer.use(ServerConfig(server: nas, endpoints: .derived(from: nas.origin)))
        XCTAssertEqual(NucleusID.origin.absoluteString, "http://nas:8080")
        XCTAssertEqual(NucleusID.manageAccountURL(tab: "apps").absoluteString, "http://nas:8080?account=manage&tab=apps")
        XCTAssertEqual(NucleusID.deleteAccountURL.absoluteString, "http://nas:8080/account/delete")
    }

    @MainActor
    func testStoredSessionIsIgnoredWithoutAServer() {
        let previous = ActiveServer.config
        let previousSession = Keychain.get(.nucleusSession)
        defer {
            ActiveServer.restore(previous)
            if let previousSession { Keychain.set(previousSession, for: .nucleusSession) } else { Keychain.delete(.nucleusSession) }
        }
        NucleusSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600),
                       user: .init(sub: "s", handle: "h", name: "n", email: nil)).save()

        ActiveServer.restore(nil)
        XCTAssertFalse(NucleusID().isSignedIn)

        ActiveServer.restore(ServerConfig(server: nas, endpoints: .derived(from: nas.origin)))
        XCTAssertTrue(NucleusID().isSignedIn)
    }

    func testAuthorizeURLCarriesCodeOnlyInTheFragment() {
        let endpoint = URL(string: "https://id.example/authorize")!
        let items = [URLQueryItem(name: "client_id", value: "orbit")]
        let code = "nucleus" + "a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6" + "home"

        let plain = NucleusID.authorizeURL(endpoint, items: items, code: nil)
        XCTAssertEqual(plain.absoluteString, "https://id.example/authorize?client_id=orbit")

        let gated = NucleusID.authorizeURL(endpoint, items: items, code: code)
        XCTAssertEqual(gated.query(), "client_id=orbit")
        XCTAssertEqual(gated.fragment(), "server_code=\(code)")
    }
}
