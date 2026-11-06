import Foundation

/// Where a server's sign-in lives, from its OAuth metadata (RFC 8414).
struct NucleusEndpoints: Codable, Hashable {
    var authorization: URL
    var token: URL
    var revocation: URL
    var userinfo: URL
    var codeRequired = false

    /// The paths nucleus-web serves, for what the metadata leaves out and for sessions older than discovery.
    static func derived(from origin: URL) -> NucleusEndpoints {
        NucleusEndpoints(authorization: origin.appending(path: "authorize"),
                         token: origin.appending(path: "api/v1/oauth/token"),
                         revocation: origin.appending(path: "api/v1/oauth/revoke"),
                         userinfo: origin.appending(path: "api/v1/oauth/userinfo"))
    }
}

/// Checks a server before signing in to it: is it a Nucleus ID server, and is this its code.
enum NucleusDiscovery {
    static func discover(_ server: NucleusServer, session: URLSession = NucleusID.session) async throws -> NucleusEndpoints {
        var request = URLRequest(url: server.discoveryURL, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await load(request, session)
        switch response.statusCode {
        case 200: break
        case 429: throw ServerProblem.tooManyTries
        case 500...599: throw ServerProblem.unreachable
        default: throw ServerProblem.notNucleus
        }

        let o = NucleusID.object(data)
        // An endpoint on another origin would send the code and PKCE verifier there (OAuth mix-up).
        func url(_ key: String) throws -> URL? {
            guard let text = o[key] as? String else { return nil }
            guard let u = URL(string: text), sameOrigin(u, server.origin) else { throw ServerProblem.notNucleus }
            return u
        }
        if let issuer = o["issuer"] as? String {
            func trimmed(_ s: String) -> String { s.hasSuffix("/") ? String(s.dropLast()) : s }
            guard trimmed(issuer) == trimmed(server.origin.absoluteString) else { throw ServerProblem.notNucleus }
        }
        guard let authorization = try url("authorization_endpoint"), let token = try url("token_endpoint"),
              (o["code_challenge_methods_supported"] as? [String])?.contains("S256") == true
        else { throw ServerProblem.notNucleus }
        let fallback = NucleusEndpoints.derived(from: server.origin)
        return NucleusEndpoints(authorization: authorization, token: token,
                                revocation: try url("revocation_endpoint") ?? fallback.revocation,
                                userinfo: try url("userinfo_endpoint") ?? fallback.userinfo,
                                codeRequired: o["server_code_required"] as? Bool ?? false)
    }

    /// Same scheme, host and effective port; an explicit default port equals none.
    static func sameOrigin(_ url: URL, _ origin: URL) -> Bool {
        func key(_ u: URL) -> [String]? {
            guard let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = u.host()?.lowercased(), !host.isEmpty else { return nil }
            return [scheme, host, String(u.port ?? (scheme == "https" ? 443 : 80))]
        }
        guard let a = key(url), let b = key(origin) else { return false }
        return a == b
    }

    /// 204 is accepted, 403 rejected; a malformed code is never sent.
    static func check(code: String, on server: NucleusServer, session: URLSession = NucleusID.session) async throws {
        guard NucleusServer.isCode(code) else { throw ServerProblem.badCode }
        var request = URLRequest(url: server.origin.appending(path: "api/v1/auth/server-code"), timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])
        let (_, response) = try await load(request, session)
        switch response.statusCode {
        case 204: return
        case 403: throw ServerProblem.codeRejected
        case 404: throw ServerProblem.notNucleus
        case 429: throw ServerProblem.tooManyTries
        default: throw ServerProblem.unreachable
        }
    }

    static func problem(for error: URLError) -> ServerProblem {
        switch error.code {
        case .appTransportSecurityRequiresSecureConnection: .needsHTTPS
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed: .untrusted
        default: .unreachable
        }
    }

    private static func load(_ request: URLRequest, _ session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ServerProblem.unreachable }
            return (data, http)
        } catch let error as URLError {
            throw problem(for: error)
        }
    }
}
