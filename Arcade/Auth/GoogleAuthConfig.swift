import Foundation

/// Google OAuth configuration.
///
/// SETUP (one-time):
/// 1. Google Cloud Console → APIs & Services → Credentials → Create Credentials
///    → OAuth client ID → Application type: **iOS** (iOS-type clients use a
///    custom redirect scheme and require NO client secret — ideal for a native
///    macOS app with ASWebAuthenticationSession + PKCE).
/// 2. Copy the client ID (looks like `1234567890-abcdef.apps.googleusercontent.com`)
///    into `clientID` below.
///
/// The redirect URI / callback scheme is the *reversed* client ID and is derived
/// automatically — nothing else to configure. No client secret is stored anywhere.
enum GoogleAuthConfig {
    /// Paste your Google OAuth **iOS** client ID here.
    static let clientID = "YOUR_CLIENT_ID.apps.googleusercontent.com"

    /// Reversed-client-ID scheme used as the OAuth redirect + ASWebAuthenticationSession callback.
    static var redirectScheme: String {
        let suffix = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(suffix)"
    }

    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    /// Endpoints.
    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    static let scopes = "openid email profile"

    /// False until a real client ID is filled in.
    static var isConfigured: Bool { !clientID.hasPrefix("YOUR_CLIENT_ID") }
}
