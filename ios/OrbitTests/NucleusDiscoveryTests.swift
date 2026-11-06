import XCTest
@testable import Orbit

/// Answers every request from `handler`, so discovery runs without a server.
final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            // A request still in flight from a finished test arrives after tearDown cleared the handler.
            guard let handler = Self.handler else { throw URLError(.cancelled) }
            let (status, data) = try handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

final class NucleusDiscoveryTests: XCTestCase {
    private let server = NucleusServer(scheme: "http", host: "nas", port: 8080)
    private let code = "nucleus" + "a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6" + "home"

    override func tearDown() { StubProtocol.handler = nil }

    private func metadata(_ extra: [String: Any] = [:], drop: [String] = []) -> Data {
        var o: [String: Any] = [
            "authorization_endpoint": "http://nas:8080/authorize",
            "token_endpoint": "http://nas:8080/api/v1/oauth/token",
            "code_challenge_methods_supported": ["S256"],
        ]
        extra.forEach { o[$0.key] = $0.value }
        drop.forEach { o.removeValue(forKey: $0) }
        return try! JSONSerialization.data(withJSONObject: o)
    }

    private func problem(_ body: () async throws -> Void) async -> ServerProblem? {
        do { try await body(); return nil } catch { return error as? ServerProblem }
    }

    func testValidMetadataGivesEndpointsWithFallbacks() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://nas:8080/api/v1/oauth/metadata")
            XCTAssertEqual(request.timeoutInterval, 10)
            return (200, self.metadata())
        }
        let e = try await NucleusDiscovery.discover(server, session: StubProtocol.session())
        XCTAssertEqual(e.authorization.absoluteString, "http://nas:8080/authorize")
        XCTAssertEqual(e.revocation.absoluteString, "http://nas:8080/api/v1/oauth/revoke")
        XCTAssertEqual(e.userinfo.absoluteString, "http://nas:8080/api/v1/oauth/userinfo")
        XCTAssertFalse(e.codeRequired)
    }

    func testCodeRequired() async throws {
        StubProtocol.handler = { _ in (200, self.metadata(["server_code_required": true])) }
        let e = try await NucleusDiscovery.discover(server, session: StubProtocol.session())
        XCTAssertTrue(e.codeRequired)
    }

    func testNotANucleusServer() async {
        for data in [metadata(drop: ["token_endpoint"]), metadata(["code_challenge_methods_supported": ["plain"]]), Data("<html>".utf8)] {
            StubProtocol.handler = { _ in (200, data) }
            let p = await problem { _ = try await NucleusDiscovery.discover(self.server, session: StubProtocol.session()) }
            XCTAssertEqual(p, .notNucleus)
        }
        StubProtocol.handler = { _ in (404, Data()) }
        let p = await problem { _ = try await NucleusDiscovery.discover(self.server, session: StubProtocol.session()) }
        XCTAssertEqual(p, .notNucleus)
    }

    private func discoverProblem(_ data: Data, server: NucleusServer? = nil) async -> ServerProblem? {
        StubProtocol.handler = { _ in (200, data) }
        let s = server ?? self.server
        return await problem { _ = try await NucleusDiscovery.discover(s, session: StubProtocol.session()) }
    }

    func testEndpointOnAnotherHostIsRejected() async {
        let a = await discoverProblem(metadata(["authorization_endpoint": "https://nucleus-home.dev/authorize"]))
        XCTAssertEqual(a, .notNucleus)
        let t = await discoverProblem(metadata(["token_endpoint": "http://evil.example:8080/api/v1/oauth/token"]))
        XCTAssertEqual(t, .notNucleus)
        let r = await discoverProblem(metadata(["revocation_endpoint": "http://evil.example:8080/revoke"]))
        XCTAssertEqual(r, .notNucleus)
    }

    func testHTTPEndpointUnderHTTPSOriginIsRejected() async {
        let https = NucleusServer(host: "id.example")
        let p = await discoverProblem(metadata(["authorization_endpoint": "http://id.example/authorize",
                                                "token_endpoint": "https://id.example/token"]), server: https)
        XCTAssertEqual(p, .notNucleus)
    }

    func testNonHTTPAndRelativeEndpointsAreRejected() async {
        let js = await discoverProblem(metadata(["authorization_endpoint": "javascript:alert(1)"]))
        XCTAssertEqual(js, .notNucleus)
        let rel = await discoverProblem(metadata(["authorization_endpoint": "/authorize"]))
        XCTAssertEqual(rel, .notNucleus)
    }

    func testMismatchedIssuerIsRejected() async {
        let p = await discoverProblem(metadata(["issuer": "http://nas:9090"]))
        XCTAssertEqual(p, .notNucleus)
        let ok = await discoverProblem(metadata(["issuer": "http://nas:8080/"]))
        XCTAssertNil(ok)
    }

    func testExplicitDefaultPortIsTheSameOrigin() async throws {
        let https = NucleusServer(host: "ID.example")
        StubProtocol.handler = { _ in (200, self.metadata(["authorization_endpoint": "https://id.example:443/authorize",
                                                           "token_endpoint": "https://id.example/token"])) }
        let e = try await NucleusDiscovery.discover(https, session: StubProtocol.session())
        XCTAssertEqual(e.authorization.absoluteString, "https://id.example:443/authorize")
    }

    func testRateLimitAndServerErrors() async {
        for (status, expected) in [(429, ServerProblem.tooManyTries), (500, .unreachable), (503, .unreachable), (403, .notNucleus)] {
            StubProtocol.handler = { _ in (status, Data()) }
            let p = await problem { _ = try await NucleusDiscovery.discover(self.server, session: StubProtocol.session()) }
            XCTAssertEqual(p, expected, "status \(status)")
        }
    }

    func testCodeCheckRateLimit() async {
        StubProtocol.handler = { _ in (429, Data()) }
        let p = await problem { try await NucleusDiscovery.check(code: self.code, on: self.server, session: StubProtocol.session()) }
        XCTAssertEqual(p, .tooManyTries)
    }

    func testNetworkErrorsMapToMessages() async {
        StubProtocol.handler = { _ in throw URLError(.cannotFindHost) }
        let p = await problem { _ = try await NucleusDiscovery.discover(self.server, session: StubProtocol.session()) }
        XCTAssertEqual(p, .unreachable)
        XCTAssertEqual(NucleusDiscovery.problem(for: URLError(.timedOut)), .unreachable)
        XCTAssertEqual(NucleusDiscovery.problem(for: URLError(.serverCertificateUntrusted)), .untrusted)
        XCTAssertEqual(NucleusDiscovery.problem(for: URLError(.appTransportSecurityRequiresSecureConnection)), .needsHTTPS)
    }

    func testCodeCheck() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://nas:8080/api/v1/auth/server-code")
            XCTAssertEqual(request.httpMethod, "POST")
            return (204, Data())
        }
        try await NucleusDiscovery.check(code: code, on: server, session: StubProtocol.session())

        StubProtocol.handler = { _ in (403, Data(#"{"error":{"code":"server_code_rejected"}}"#.utf8)) }
        let rejected = await problem { try await NucleusDiscovery.check(code: self.code, on: self.server, session: StubProtocol.session()) }
        XCTAssertEqual(rejected, .codeRejected)
    }

    func testMalformedCodeNeverReachesTheServer() async {
        StubProtocol.handler = { _ in XCTFail("no request expected"); return (204, Data()) }
        let p = await problem { try await NucleusDiscovery.check(code: "nucleus123home", on: self.server, session: StubProtocol.session()) }
        XCTAssertEqual(p, .badCode)
    }
}
