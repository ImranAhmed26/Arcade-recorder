import SwiftUI

/// Login screen. Primary path is Google sign-in via a native, Safari-backed
/// secure session (ASWebAuthenticationSession). A local "Continue without an
/// account" fallback keeps the app usable before Google is configured.
struct SignInView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        ZStack {
            Theme.windowBackground.ignoresSafeArea()

            VStack(spacing: Theme.Space.xl) {
                VStack(spacing: Theme.Space.sm) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.primary)
                    Text("Arcade")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Record your screen, beautifully.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: Theme.Space.md) {
                    Button {
                        Task { await auth.signInWithGoogle() }
                    } label: {
                        HStack(spacing: Theme.Space.sm) {
                            if auth.isAuthenticating {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "globe")
                            }
                            Text(auth.isAuthenticating ? "Signing in…" : "Continue with Google")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(auth.isAuthenticating)

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !auth.isConfigured {
                        Text("Google sign-in isn’t configured yet — add your OAuth client ID in GoogleAuthConfig.swift.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Continue without an account") {
                        auth.continueAsGuest()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .frame(width: 320)
                .cardSurface(padding: Theme.Space.xl)
            }
            .padding(40)
        }
    }
}
