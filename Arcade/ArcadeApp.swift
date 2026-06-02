import SwiftUI

@main
struct ArcadeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 680)
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
                // The dashboard remains the host view; countdown/recording are
                // presented via floating overlay windows managed by WindowManager.
                DashboardView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.phase)
    }
}
