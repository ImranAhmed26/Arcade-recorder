import Foundation
import Combine

/// Seam for a future backend. The default does nothing, so the app is fully
/// functional locally; later, a server can adopt this to exchange/validate the
/// Google id_token and return its own session — no other code needs to change.
protocol SessionSyncing {
    /// Called after a successful Google sign-in. May enrich/replace the session.
    func register(_ session: UserSession) async throws -> UserSession
    /// Called on sign-out.
    func invalidate(_ session: UserSession) async
}

struct NoopSessionBackend: SessionSyncing {
    func register(_ session: UserSession) async throws -> UserSession { session }
    func invalidate(_ session: UserSession) async {}
}

/// Owns authentication state. Persists the session in the Keychain and restores
/// it on launch. UI observes `currentUser` (nil = signed out).
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var currentUser: UserSession?
    @Published var isAuthenticating = false
    @Published var errorMessage: String?

    private let provider = GoogleAuthProvider()
    private let account = "session"

    /// Swap in a real backend later without touching call sites.
    var backend: SessionSyncing = NoopSessionBackend()

    var isConfigured: Bool { GoogleAuthConfig.isConfigured }

    // MARK: - Restore on launch

    func restore() {
        guard let saved = KeychainStore.loadCodable(UserSession.self, account: account) else { return }
        currentUser = saved
        // Refresh a stale Google token in the background; keep the user signed in meanwhile.
        Task { await refreshIfNeeded() }
    }

    private func refreshIfNeeded() async {
        guard let s = currentUser, !s.isGuest, s.isExpired, s.refreshToken != nil else { return }
        if let refreshed = try? await provider.refresh(s) {
            persist(refreshed)
            currentUser = refreshed
        }
    }

    // MARK: - Sign in

    func signInWithGoogle() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            var session = try await provider.authenticate()
            session = (try? await backend.register(session)) ?? session
            persist(session)
            currentUser = session
        } catch AuthError.cancelled {
            // Silent — user dismissed the sheet.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Local-only session so the app is usable before Google is configured / for dev.
    func continueAsGuest() {
        let guest = UserSession.guest()
        persist(guest)
        currentUser = guest
    }

    // MARK: - Sign out

    func signOut() {
        let outgoing = currentUser
        KeychainStore.delete(account: account)
        currentUser = nil
        if let outgoing { Task { await backend.invalidate(outgoing) } }
    }

    // MARK: - Persistence

    private func persist(_ session: UserSession) {
        KeychainStore.saveCodable(session, account: account)
    }
}
