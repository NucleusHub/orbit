import Foundation

/// Sign-in requests between devices (`/api/v1/auth/qr`): approving a website's, or claiming one a website made for this app.
enum QRLogin {
    typealias Send = (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// What the signed-in app shows before approving: the waiting device and when it asked.
    struct Prompt: Identifiable, Equatable {
        let id: String
        var device: String
        var createdAt: Date
    }

    enum Problem: Error, Equatable {
        case expired, taken, denied, tooManyTries, unreachable, failed
        case otherServer, alreadySignedIn, signInFirst, notSignIn

        var message: LocalizedStringResource {
            switch self {
            case .expired: "This code has expired. Show a new one and scan again."
            case .taken: "This code was already scanned. Show a new one and scan again."
            case .denied: "The sign-in was denied."
            case .tooManyTries: "Too many tries. Wait a minute and try again."
            case .unreachable: "Couldn't reach this server."
            case .failed: "Couldn't sign in. Try again."
            case .otherServer: "This code is for another server."
            case .alreadySignedIn: "You're already signed in."
            case .signInFirst: "Sign in to this app first, then scan again."
            case .notSignIn: "This isn't a Nucleus sign-in code."
            }
        }
    }

    /// The website is waiting for this app's approval (Bearer); binds the request to this account.
    static func scan(_ id: String, on origin: URL, send: Send) async throws -> Prompt {
        let (data, response) = try await post(origin, id, "scan", [:], send)
        try check(response)
        let o = NucleusID.object(data)
        guard response.statusCode == 200, let device = o["device"] as? String else { throw Problem.failed }
        return Prompt(id: id, device: device, createdAt: (o["createdAt"] as? String).flatMap(date) ?? Date())
    }

    static func approve(_ id: String, _ approve: Bool, on origin: URL, send: Send) async throws {
        let (_, response) = try await post(origin, id, "approve", ["approve": approve], send)
        try check(response)
        guard response.statusCode == 204 else { throw Problem.failed }
    }

    /// Claims a website's request for this app, then polls every `interval` until it's answered; returns the authorization code.
    static func approval(of id: String, on origin: URL, scope: String, challenge: String, device: String,
                         interval: Duration = .seconds(2), send: Send) async throws -> String {
        let (data, response) = try await post(origin, id, "claim", [
            "client_id": NucleusID.clientID, "redirect_uri": NucleusID.redirectURI, "scope": scope,
            "code_challenge": challenge, "code_challenge_method": "S256", "device": device,
        ], send)
        try check(response)
        guard response.statusCode == 200, let secret = NucleusID.object(data)["secret"] as? String else { throw Problem.failed }

        while true {
            try await Task.sleep(for: interval)
            let (data, response) = try await post(origin, id, "poll", ["secret": secret], send)
            // The poll limit is per IP and can be shared with other devices; just wait for the next round.
            if response.statusCode == 429 { continue }
            try check(response)
            let o = NucleusID.object(data)
            guard response.statusCode == 200 else { throw Problem.failed }
            switch o["status"] as? String {
            case "pending", "scanned": continue
            case "denied": throw Problem.denied
            case "expired": throw Problem.expired
            case "signed-in":
                guard let code = o["code"] as? String else { throw Problem.failed }
                return code
            default: throw Problem.failed
            }
        }
    }

    private static func post(_ origin: URL, _ id: String, _ action: String, _ body: [String: Any], _ send: Send) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: origin.appending(path: "api/v1/auth/qr/\(id)/\(action)"), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            return try await send(request)
        } catch is URLError {
            throw Problem.unreachable
        }
    }

    private static func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 404: throw Problem.expired
        case 409: throw Problem.taken
        case 429: throw Problem.tooManyTries
        default: return
        }
    }

    private static func date(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}
