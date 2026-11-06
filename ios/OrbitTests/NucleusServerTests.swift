import XCTest
@testable import Orbit

final class NucleusServerTests: XCTestCase {
    private let code = "nucleus" + "a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6" + "home"

    private func problem(_ body: () throws -> Any) -> ServerProblem? {
        do { _ = try body(); return nil } catch { return error as? ServerProblem }
    }

    // MARK: Address

    func testBareHostIsHTTPSOnDefaultPath() throws {
        let s = try NucleusServer.parse("  nas.tail1234.ts.net ")
        XCTAssertEqual(s.origin.absoluteString, "https://nas.tail1234.ts.net")
        XCTAssertEqual(s.discoveryURL.absoluteString, "https://nas.tail1234.ts.net/api/v1/oauth/metadata")
    }

    func testHostPortAndIP() throws {
        let s = try NucleusServer.parse("100.101.102.103:8080", scheme: "http")
        XCTAssertEqual(s.origin.absoluteString, "http://100.101.102.103:8080")
    }

    func testMagicDNSShortName() throws {
        XCTAssertEqual(try NucleusServer.parse("nas", scheme: "http").origin.absoluteString, "http://nas")
    }

    func testFullURLSchemeAndPortWinAndPathIsIgnored() throws {
        let s = try NucleusServer.parse("http://Example.com:81/authorize?x=1", scheme: "https", port: 9000)
        XCTAssertEqual(s.origin.absoluteString, "http://example.com:81")
        XCTAssertEqual(s.discoveryPath, NucleusServer.defaultDiscoveryPath)
    }

    func testPortFieldUsedWhenTextHasNone() throws {
        XCTAssertEqual(try NucleusServer.parse("nas", port: 8443).origin.absoluteString, "https://nas:8443")
    }

    func testCustomDiscoveryPathGetsLeadingSlash() throws {
        let s = try NucleusServer.parse("nas", discoveryPath: "well-known/nucleus")
        XCTAssertEqual(s.discoveryURL.absoluteString, "https://nas/well-known/nucleus")
    }

    func testBadAddresses() {
        for text in ["", "   ", "foo bar", "ftp://nas", "https://", "://nas"] {
            XCTAssertEqual(problem { try NucleusServer.parse(text) }, .badAddress, text)
        }
    }

    // MARK: Code

    func testCodeFormat() {
        XCTAssertTrue(NucleusServer.isCode(code))
        for bad in ["", "nucleushome", code.replacingOccurrences(of: "nucleus", with: "Nucleus"),
                    String(code.dropLast(4)) + "Home", "nucleus" + String(repeating: "a", count: 31) + "home",
                    "nucleus" + String(repeating: "a", count: 33) + "home", code.replacingOccurrences(of: "a1", with: "a-")] {
            XCTAssertFalse(NucleusServer.isCode(bad), bad)
        }
    }

    // MARK: Setup link and file

    func testSetupLink() throws {
        let url = URL(string: "com.nucleushome.orbit://server?scheme=http&host=nas&port=8080&path=/meta&code=\(code)%0A")!
        let s = try NucleusServer.setup(from: url)
        XCTAssertEqual(s.origin.absoluteString, "http://nas:8080")
        XCTAssertEqual(s.discoveryPath, "/meta")
        XCTAssertEqual(s.code, code)
    }

    func testSetupFile() throws {
        let json = #"{"host":"nas.tail1234.ts.net","port":443,"code":"\#(code)"}"#
        let s = try NucleusServer.setup(fromFile: Data(json.utf8))
        XCTAssertEqual(s.origin.absoluteString, "https://nas.tail1234.ts.net:443")
        XCTAssertEqual(s.discoveryPath, NucleusServer.defaultDiscoveryPath)
        XCTAssertEqual(s.code, code)
    }

    func testSetupWithBadCodeSaysOnlyThat() {
        let url = URL(string: "com.nucleushome.orbit://server?host=nas&code=nucleus123home")!
        XCTAssertEqual(problem { try NucleusServer.setup(from: url) }, .badCode)
    }

    func testBrokenSetups() {
        for link in ["com.nucleushome.orbit://server", "com.nucleushome.orbit://server?host=a/b",
                     "com.nucleushome.orbit://server?host=nas&port=99999", "com.nucleushome.orbit://server?host=nas&scheme=ftp"] {
            XCTAssertEqual(problem { try NucleusServer.setup(from: URL(string: link)!) }, .badSetup, link)
        }
        XCTAssertEqual(problem { try NucleusServer.setup(fromFile: Data("not json".utf8)) }, .badSetup)
    }

    func testScannedSetups() throws {
        let json = #"{"host":"nas","code":"\#(code)"}"#
        guard case .setup(let a) = try NucleusServer.scanned(json) else { return XCTFail("not a setup") }
        XCTAssertEqual(a.origin.absoluteString, "https://nas")
        XCTAssertEqual(a.code, code)
        // Another app's link works too.
        guard case .setup(let b) = try NucleusServer.scanned("com.nucleushome.notes://server?host=nas&code=\(code)") else { return XCTFail("not a setup") }
        XCTAssertEqual(b, a)
    }

    func testScannedCodeOnly() throws {
        XCTAssertEqual(try NucleusServer.scanned(" \(code)\n"), .code(code))
        XCTAssertEqual(problem { _ = try NucleusServer.scanned("nucleus123home") }, .badCode)
    }

    func testScannedWebLogin() throws {
        let json = #"{"login":"AbC_d-12345678901234567","kind":"web","scheme":"https","host":"id.example","port":8443}"#
        let scanned = try NucleusServer.scanned(json)
        XCTAssertEqual(scanned, .webLogin(id: "AbC_d-12345678901234567", server: NucleusServer(host: "id.example", port: 8443)))
    }

    func testScannedAppLoginCarriesTheCode() throws {
        let json = #"{"login":"req1","kind":"app","scheme":"http","host":"nas","code":"\#(code)"}"#
        guard case .appLogin(let id, let server) = try NucleusServer.scanned(json) else { return XCTFail("not an app login") }
        XCTAssertEqual(id, "req1")
        XCTAssertEqual(server.origin.absoluteString, "http://nas")
        XCTAssertEqual(server.code, code)
    }

    func testScannedBrokenLogins() {
        for json in [#"{"login":"req1","kind":"desktop","host":"nas"}"#, #"{"login":"req1","host":"nas"}"#,
                     #"{"login":"../oauth/token","kind":"web","host":"nas"}"#, #"{"login":"","kind":"web","host":"nas"}"#,
                     #"{"login":7,"kind":"web","host":"nas"}"#, #"{"login":"req1","kind":"web"}"#] {
            XCTAssertEqual(problem { _ = try NucleusServer.scanned(json) }, .badSetup, json)
        }
    }

    func testScannedJunk() {
        for text in ["https://example.com", "hello", "com.nucleushome.orbit://task/1", "{}"] {
            XCTAssertEqual(problem { _ = try NucleusServer.scanned(text) }, .badSetup, text)
        }
    }
}
