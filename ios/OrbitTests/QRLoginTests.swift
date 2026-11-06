import XCTest
@testable import Orbit

final class QRLoginTests: XCTestCase {
    private let origin = URL(string: "http://nas:8080")!
    private let send: QRLogin.Send = { request in
        let (data, response) = try await StubProtocol.session().data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    override func tearDown() { StubProtocol.handler = nil }

    /// URLProtocol gets the body as a stream.
    private static func body(_ request: URLRequest) -> [String: Any] {
        guard let stream = request.httpBodyStream else { return NucleusID.object(request.httpBody ?? Data()) }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }
            data.append(buffer, count: n)
        }
        return NucleusID.object(data)
    }

    private static func json(_ o: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: o) }

    private func problem(_ body: () async throws -> Void) async -> QRLogin.Problem? {
        do { try await body(); return nil } catch { return error as? QRLogin.Problem }
    }

    // MARK: Approving a website's sign-in

    func testScanReturnsWhatToShow() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://nas:8080/api/v1/auth/qr/req1/scan")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertTrue(Self.body(request).isEmpty)
            return (200, Self.json(["device": "Safari on macOS", "createdAt": "2026-10-12T20:10:47.123Z"]))
        }
        let prompt = try await QRLogin.scan("req1", on: origin, send: send)
        XCTAssertEqual(prompt.id, "req1")
        XCTAssertEqual(prompt.device, "Safari on macOS")
        XCTAssertEqual(prompt.createdAt.timeIntervalSince1970, 1_791_835_847.123, accuracy: 0.001)
    }

    func testScanOfAGoneOrTakenRequest() async {
        for (status, expected) in [(404, QRLogin.Problem.expired), (409, .taken), (429, .tooManyTries), (500, .failed)] {
            StubProtocol.handler = { _ in (status, Data()) }
            let p = await problem { _ = try await QRLogin.scan("req1", on: self.origin, send: self.send) }
            XCTAssertEqual(p, expected, "status \(status)")
        }
    }

    func testApproveAndDeny() async throws {
        for answer in [true, false] {
            StubProtocol.handler = { request in
                XCTAssertEqual(request.url?.absoluteString, "http://nas:8080/api/v1/auth/qr/req1/approve")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(Self.body(request)["approve"] as? Bool, answer)
                return (204, Data())
            }
            try await QRLogin.approve("req1", answer, on: origin, send: send)
        }
        StubProtocol.handler = { _ in (404, Data()) }
        let p = await problem { try await QRLogin.approve("req1", true, on: self.origin, send: self.send) }
        XCTAssertEqual(p, .expired)
    }

    // MARK: Claiming a website's request for this app

    func testClaimThenPollUntilSignedIn() async throws {
        var polls = 0
        StubProtocol.handler = { request in
            let body = Self.body(request)
            switch request.url?.absoluteString {
            case "http://nas:8080/api/v1/auth/qr/req1/claim":
                XCTAssertEqual(body["client_id"] as? String, "orbit")
                XCTAssertEqual(body["redirect_uri"] as? String, "com.nucleushome.orbit:/oauth")
                XCTAssertEqual(body["scope"] as? String, "data profile")
                XCTAssertEqual(body["code_challenge"] as? String, "challenge")
                XCTAssertEqual(body["code_challenge_method"] as? String, "S256")
                XCTAssertEqual(body["device"] as? String, "iPhone 16")
                return (200, Self.json(["secret": "s3cret", "expiresAt": "2026-10-12T20:12:47.000Z"]))
            case "http://nas:8080/api/v1/auth/qr/req1/poll":
                XCTAssertEqual(body["secret"] as? String, "s3cret")
                polls += 1
                switch polls {
                case 1: return (200, Self.json(["status": "scanned"]))
                case 2: return (429, Data())
                case 3: return (200, Self.json(["status": "pending"]))
                default: return (200, Self.json(["status": "signed-in", "code": "auth-code", "redirect_uri": "com.nucleushome.orbit:/oauth"]))
                }
            default:
                XCTFail("unexpected \(request.url?.absoluteString ?? "")")
                return (500, Data())
            }
        }
        let code = try await QRLogin.approval(of: "req1", on: origin, scope: "data profile", challenge: "challenge",
                                              device: "iPhone 16", interval: .zero, send: send)
        XCTAssertEqual(code, "auth-code")
        XCTAssertEqual(polls, 4)
    }

    private func approvalProblem(claim: Int = 200, poll: [String: Any]) async -> QRLogin.Problem? {
        StubProtocol.handler = { request in
            request.url!.lastPathComponent == "claim" ? (claim, Self.json(["secret": "s3cret"])) : (200, Self.json(poll))
        }
        return await problem {
            _ = try await QRLogin.approval(of: "req1", on: self.origin, scope: "data", challenge: "c", device: "d",
                                           interval: .zero, send: self.send)
        }
    }

    func testDeniedExpiredAndTaken() async {
        let denied = await approvalProblem(poll: ["status": "denied"])
        XCTAssertEqual(denied, .denied)
        let expired = await approvalProblem(poll: ["status": "expired"])
        XCTAssertEqual(expired, .expired)
        let taken = await approvalProblem(claim: 409, poll: [:])
        XCTAssertEqual(taken, .taken)
        let noCode = await approvalProblem(poll: ["status": "signed-in"])
        XCTAssertEqual(noCode, .failed)
    }

    func testPollingStopsWhenCancelled() async {
        StubProtocol.handler = { request in
            (200, Self.json(request.url!.lastPathComponent == "claim" ? ["secret": "s3cret"] : ["status": "pending"]))
        }
        let task = Task {
            try await QRLogin.approval(of: "req1", on: origin, scope: "data", challenge: "c", device: "d",
                                       interval: .seconds(60), send: send)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError || error as? QRLogin.Problem == .unreachable, "\(error)")
        }
    }

    func testOffline() async {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let p = await problem { _ = try await QRLogin.scan("req1", on: self.origin, send: self.send) }
        XCTAssertEqual(p, .unreachable)
    }
}
