import Foundation

/// The authenticated user + OAuth tokens. Backend-agnostic: a future server can
/// consume `idToken`/`accessToken` without changing the rest of the app.
struct UserSession: Codable, Equatable {
    var userID: String            // Google `sub` (stable account id), or "guest"
    var email: String?
    var fullName: String?
    var avatarURL: URL?

    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Date

    var isGuest: Bool = false

    /// Best label for the sidebar footer.
    var displayName: String {
        fullName ?? email ?? (isGuest ? "Guest" : "Account")
    }

    var isExpired: Bool { Date() >= expiresAt }

    /// A local-only session used when Google isn't configured / for dev.
    static func guest() -> UserSession {
        UserSession(userID: "guest",
                    email: nil,
                    fullName: "Guest",
                    avatarURL: nil,
                    accessToken: "",
                    refreshToken: nil,
                    idToken: nil,
                    expiresAt: .distantFuture,
                    isGuest: true)
    }
}
