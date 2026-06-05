import Foundation
import AuthenticationServices
import AppKit

enum AuthError: LocalizedError {
    case notConfigured
    case cancelled
    case cannotStart
    case badCallback
    case stateMismatch
    case tokenExchangeFailed(String)
    case noProfile

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google sign-in isn't configured yet. Add your OAuth client ID in GoogleAuthConfig.swift."
        case .cancelled:
            return "Sign-in was cancelled."
        case .cannotStart:
            return "Could not start the sign-in session."
        case .badCallback:
            return "The sign-in response was malformed."
        case .stateMismatch:
            return "Sign-in failed a security check (state mismatch)."
        case .tokenExchangeFailed(let m):
            return "Could not complete sign-in: \(m)"
        case .noProfile:
            return "Signed in, but no profile information was returned."
        }
    }
}

/// Runs the Google OAuth 2.0 + PKCE authorization-code flow through a native,
/// Safari-backed `ASWebAuthenticationSession` (NOT a WebView), exchanges the
/// code for tokens, and parses the id_token for profile info.
@MainActor
final class GoogleAuthProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var webSession: ASWebAuthenticationSession?

    // MARK: - Interactive sign-in

    func authenticate() async throws -> UserSession {
        guard GoogleAuthConfig.isConfigured else { throw AuthError.notConfigured }

        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = UUID().uuidString

        var comps = URLComponents(url: GoogleAuthConfig.authEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: GoogleAuthConfig.clientID),
            .init(name: "redirect_uri", value: GoogleAuthConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: GoogleAuthConfig.scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),   // request a refresh token
            .init(name: "prompt", value: "select_account"),
        ]
        let authURL = comps.url!

        let callback = try await runWebSession(url: authURL,
                                               scheme: GoogleAuthConfig.redirectScheme)

        // Parse the redirect.
        guard let cb = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw AuthError.badCallback
        }
        let items = cb.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw err == "access_denied" ? AuthError.cancelled : AuthError.tokenExchangeFailed(err)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw AuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.badCallback
        }

        return try await exchangeCode(code, verifier: verifier)
    }

    private func runWebSession(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            if !session.start() {
                continuation.resume(throwing: AuthError.cannotStart)
            }
        }
    }

    // MARK: - Token exchange / refresh

    private func exchangeCode(_ code: String, verifier: String) async throws -> UserSession {
        let token = try await postToken([
            "client_id": GoogleAuthConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleAuthConfig.redirectURI,
        ])
        guard let idToken = token.id_token else { throw AuthError.noProfile }
        let claims = Self.decodeIDToken(idToken)
        return UserSession(
            userID: claims["sub"] as? String ?? UUID().uuidString,
            email: claims["email"] as? String,
            fullName: claims["name"] as? String,
            avatarURL: (claims["picture"] as? String).flatMap(URL.init(string:)),
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            idToken: idToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600)))
    }

    /// Refresh an expired access token using the stored refresh token. Profile
    /// fields are carried over from the existing session.
    func refresh(_ session: UserSession) async throws -> UserSession {
        guard let refreshToken = session.refreshToken else { throw AuthError.tokenExchangeFailed("no refresh token") }
        let token = try await postToken([
            "client_id": GoogleAuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        var updated = session
        updated.accessToken = token.access_token
        updated.idToken = token.id_token ?? session.idToken
        updated.expiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600))
        if let newRefresh = token.refresh_token { updated.refreshToken = newRefresh }
        return updated
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int?
        let refresh_token: String?
        let id_token: String?
    }

    private func postToken(_ fields: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: GoogleAuthConfig.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw AuthError.tokenExchangeFailed(body)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.tokenExchangeFailed("malformed token response")
        }
    }

    // MARK: - JWT (id_token) parsing — claims only, no signature verification
    // (transport is TLS to Google's token endpoint; a backend would verify the JWT).

    static func decodeIDToken(_ jwt: String) -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

private extension CharacterSet {
    /// Allowed characters for x-www-form-urlencoded values.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
