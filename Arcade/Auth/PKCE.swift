import Foundation
import CryptoKit

/// PKCE (Proof Key for Code Exchange) helpers for the OAuth 2.0 authorization
/// code flow on a public client (no client secret).
enum PKCE {
    /// A high-entropy random code verifier (RFC 7636: 43–128 URL-safe chars).
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    /// S256 challenge = base64url(SHA256(verifier)).
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
