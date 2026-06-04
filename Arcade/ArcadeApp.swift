import SwiftUI

@main
struct ArcadeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(Theme.primary)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { appState.applyAppearance() }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 700)
    }
}

/// Routes between top-level phases driven by `AppState.phase`.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .signIn:
                SignInView()
            case .dashboard, .countdown, .recording:
                // Sidebar host; countdown/recording use floating overlay windows.
                MainWindowView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.phase)
    }
}
