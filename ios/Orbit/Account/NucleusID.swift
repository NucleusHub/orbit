import AuthenticationServices
import CryptoKit
import Foundation
import NucleusUI
import Observation
import UIKit

/// Signing in with a Nucleus ID account: OAuth 2 authorization code with PKCE, as the public `orbit` client.
@MainActor
@Observable
final class NucleusID: NSObject {
    /// The app's own pages (privacy policy), whichever server the account is on.
    nonisolated static let officialSite = URL(string: "https://nucleus-home.dev")!
    /// The account's server; only used while signed in, so the fallback is never reached in practice.
    nonisolated static var origin: URL { ActiveServer.config?.server.origin ?? officialSite }
    private nonisolated static var endpoints: NucleusEndpoints { ActiveServer.config?.endpoints ?? .derived(from: origin) }
    nonisolated static let clientID = "orbit"
    nonisolated static let redirectURI = "com.nucleushome.orbit:/oauth"
    nonisolated static let callbackScheme = "com.nucleushome.orbit"
    nonisolated static let scope = "profile data"
    nonisolated static var privacyURL: URL { officialSite.appending(path: "privacy/orbit") }
    nonisolated static var deleteAccountURL: URL { origin.appending(path: "account/delete") }

    /// The website's account dialog (signing in there first if needed), optionally on a tab:
    /// profile, password, appearance or apps.
    nonisolated static func manageAccountURL(tab: String? = nil) -> URL {
        var c = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "account", value: "manage")] + (tab.map { [URLQueryItem(name: "tab", value: $0)] } ?? [])
        return c.url!
    }

    enum AuthError: Equatable {
        case expired, offline, keptUnsynced
        case failed(String)
    }

    private(set) var session: NucleusSession?
    private(set) var signingIn = false
    var error: AuthError?

    var isSignedIn: Bool { session != nil }
    var user: NucleusSession.User? { session?.user }

    /// Picks the server to sign in to. Only while signed out, so a session never outlives its server.
    func use(_ config: ServerConfig) {
        guard !isSignedIn else { return }
        ActiveServer.use(config)
    }

    @ObservationIgnored var onSignedIn: (() async -> Void)?
    /// Returns false when `clean` couldn't be honored: unsynced changes stayed on the device.
    @ObservationIgnored var onSignedOut: ((_ clean: Bool) async -> Bool)?
    /// The account ended the session (refresh token revoked); nothing can be synced any more.
    @ObservationIgnored var onExpired: (() -> Void)?
    @ObservationIgnored private var refreshing: Task<NucleusSession, Error>?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?

    private static let refreshMargin: TimeInterval = 60

    override init() {
        // A session without a usable server would talk to the fallback origin; reading the server first also runs its cleanup.
        session = ActiveServer.config == nil ? nil : NucleusSession.load()
        super.init()
    }

    /// Checks a stored session still works, refreshing it if the access token has lapsed.
    func validate() async {
        guard session != nil else { return }
        do {
            let (data, response) = try await authorized(URLRequest(url: Self.endpoints.userinfo))
            if response.statusCode == 200, let user = Self.user(from: data), var s = session {
                s.user = user
                session = s
                s.save()
                Self.applyAppearance(from: data)
            }
        } catch {}
    }

    // MARK: Signing in and out

    func signIn() async {
        guard !signingIn else { return }
        signingIn = true
        error = nil
        defer { signingIn = false }

        do {
            guard let tokens = try await authorize(scope: Self.signInScope) else { return }
            await finishSignIn(tokens)
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            return
        } catch {
            self.error = Self.classify(error)
        }
    }

    /// Signs in with a code a website approved (QR sign-in); `verifier` is the PKCE pair of the claimed challenge.
    func signIn(code: String, verifier: String) async {
        guard !signingIn else { return }
        signingIn = true
        error = nil
        defer { signingIn = false }

        do {
            await finishSignIn(try await redeem(code: code, verifier: verifier))
        } catch {
            self.error = Self.classify(error)
        }
    }

    static var signInScope: String { scope }

    private func finishSignIn(_ tokens: NucleusSession) async {
        tokens.save()
        session = tokens
        await onSignedIn?()
    }

    /// The browser sign-in and code exchange; nil when the person declined.
    private func authorize(scope: String) async throws -> NucleusSession? {
        let verifier = Self.randomToken(48)
        let state = Self.randomToken(16)
        let url = Self.authorizeURL(Self.endpoints.authorization, items: [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: Self.challenge(verifier)),
            .init(name: "code_challenge_method", value: "S256"),
        ], code: ActiveServer.config?.server.code)

        let callback = try await authenticate(url: url)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            if err == "access_denied" { return nil }
            throw Failure.server(err)
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw Failure.server("invalid_state") }
        return try await redeem(code: code, verifier: verifier)
    }

    /// Exchanges an authorization code for tokens and reads who signed in.
    private func redeem(code: String, verifier: String) async throws -> NucleusSession {
        var tokens = try await tokenRequest([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": Self.redirectURI, "code_verifier": verifier,
        ])
        var request = URLRequest(url: Self.endpoints.userinfo)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await Self.session.data(for: request)
        tokens.user = Self.user(from: data) ?? .init(sub: "", handle: "", name: "", email: nil)
        Self.applyAppearance(from: data)
        return tokens
    }

    func signOut(clean: Bool) async {
        if await onSignedOut?(clean) == false { error = .keptUnsynced }
        if let refresh = session?.refreshToken {
            // Fire and forget: signing out works offline too.
            Task.detached { _ = try? await Self.post(Self.endpoints.revocation, ["client_id": Self.clientID, "token": refresh]) }
        }
        NucleusSession.clear()
        session = nil
        refreshing = nil
        NucleusTheme.shared.account = nil
    }

    /// Sets the account's theme, which apps start with; `applyToApps` makes every app take it over its own.
    func setAccountAccent(_ accent: NucleusAccent, applyToApps: Bool) async throws {
        var req = URLRequest(url: Self.origin.appending(path: "api/v1/oauth/appearance"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var appearance: [String: Any] = ["accent": accent.id]
        if let hex = accent.customHex { appearance = ["accent": "custom", "customAccent": hex] }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["appearance": appearance, "applyToApps": applyToApps])
        let (data, response) = try await authorized(req)
        guard response.statusCode == 200 else {
            let o = Self.object(data)
            throw Failure.server((o["error"] as? [String: Any])?["message"] as? String ?? o["message"] as? String ?? "HTTP \(response.statusCode)")
        }
        Self.applyAppearance(from: data)
    }

    /// The account's theme from userinfo; the app starts with it (`adoptAccountTheme`).
    private static func applyAppearance(from data: Data) {
        guard let value = object(data)["appearance"] else { return }
        NucleusTheme.shared.account = NucleusAccountTheme(json: value as? [String: Any])
        adoptAccountTheme()
    }

    /// Takes the account's accent unless one was picked here since it was last pushed to every app.
    static func adoptAccountTheme(defaults: UserDefaults = .standard) {
        let picked = defaults.object(forKey: "accentPickedAt") as? Date
        guard let accent = NucleusTheme.shared.account?.adoption(appPickedAt: picked), accent != NucleusTheme.shared.app else { return }
        NucleusTheme.shared.app = accent
    }

    private func expire() {
        onExpired?()
        NucleusSession.clear()
        session = nil
        NucleusTheme.shared.account = nil
        error = .expired
    }

    // MARK: Authorized requests

    /// A request with a fresh bearer token; on 401 the token is refreshed once and the request retried.
    func authorized(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await authorized(request, refreshOn401: { _ in true })
    }

    /// `refreshOn401` lets an app keep its own 401s (a wrong folder password) from rotating the token.
    func authorized(_ request: URLRequest, refreshOn401: (Data) -> Bool) async throws -> (Data, HTTPURLResponse) {
        var req = request
        req.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        var (data, response) = try await Self.send(req)
        if response.statusCode == 401, refreshOn401(data) {
            req.setValue("Bearer \(try await refresh().accessToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await Self.send(req)
        }
        return (data, response)
    }

    /// For requests the app can't route through `authorized`: AVPlayer streams and image loads.
    func bearerToken() async throws -> String { try await accessToken() }

    /// A long video outlives its token; the player is rebuilt with a fresh one.
    func refreshNow() async throws { _ = try await refresh() }

    private func accessToken() async throws -> String {
        guard let s = session else { throw Failure.signedOut }
        if s.expiresAt.timeIntervalSinceNow > Self.refreshMargin { return s.accessToken }
        return try await refresh().accessToken
    }

    /// One refresh at a time: refresh tokens rotate, and reusing an old one revokes the whole grant.
    private func refresh() async throws -> NucleusSession {
        if let refreshing { return try await refreshing.value }
        guard let current = session else { throw Failure.signedOut }
        let task = Task { () throws -> NucleusSession in
            var next = try await self.tokenRequest(["grant_type": "refresh_token", "refresh_token": current.refreshToken])
            next.user = current.user
            return next
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let next = try await task.value
            // Signed out while this was in flight: don't put a session back.
            guard session != nil else { throw Failure.signedOut }
            next.save()
            session = next
            return next
        } catch Failure.server("invalid_grant") {
            expire()
            throw Failure.signedOut
        }
    }

    // MARK: Plumbing

    enum Failure: Error, Equatable {
        case signedOut
        case declined
        case server(String)
    }

    /// The consent page; the server code rides in the fragment, which never reaches the server's logs.
    nonisolated static func authorizeURL(_ endpoint: URL, items: [URLQueryItem], code: String?) -> URL {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []) + items
        if let code { c.fragment = "server_code=\(code)" }
        return c.url!
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> NucleusSession {
        var body = fields
        body["client_id"] = Self.clientID
        let (data, response) = try await Self.post(Self.endpoints.token, body)
        let json = Self.object(data)
        guard response.statusCode == 200, let access = json["access_token"] as? String else {
            throw Failure.server(json["error"] as? String ?? "HTTP \(response.statusCode)")
        }
        let expiresIn = json["expires_in"] as? Double ?? 3600
        return NucleusSession(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String ?? session?.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(expiresIn),
            user: session?.user ?? .init(sub: "", handle: "", name: "", email: nil),
            scopes: (json["scope"] as? String).map { $0.split(separator: " ").map(String.init) } ?? session?.scopes
        )
    }

    private nonisolated static func post(_ url: URL, _ fields: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, which a form body reads as a space.
        req.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        return try await send(req)
    }

    /// No URL cache or cookies: responses carry tokens and tasks, which shouldn't sit in Caches.
    nonisolated static let session = URLSession(configuration: .ephemeral)

    nonisolated static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    nonisolated static func object(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func user(from data: Data) -> NucleusSession.User? {
        let o = object(data)
        guard let sub = o["sub"] as? String else { return nil }
        let handle = o["preferred_username"] as? String ?? ""
        let name = (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? handle
        return .init(sub: sub, handle: handle, name: name, email: o["email"] as? String)
    }

    private static func classify(_ error: Error) -> AuthError {
        if error is URLError { return .offline }
        if case Failure.server(let reason) = error { return .failed(reason) }
        return .failed(error.localizedDescription)
    }

    static func randomToken(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { callback, error in
                if let callback { continuation.resume(returning: callback) } else { continuation.resume(throwing: error ?? URLError(.unknown)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            session.start()
        }
    }
}

extension NucleusID: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
