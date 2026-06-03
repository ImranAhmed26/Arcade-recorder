import SwiftUI

/// Static sign-in. UI only — no authentication. "Continue" advances to the app.
struct SignInView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""

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
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        appState.signIn(email: email)
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
                .frame(width: 300)
                .cardSurface(padding: Theme.Space.xl)
            }
            .padding(40)
        }
    }
}
