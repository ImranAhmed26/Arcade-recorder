import SwiftUI

/// Sidebar-driven host shown after sign-in. Owns the shared recordings model and
/// presents the countdown overlay + status banners above whichever section shows.
struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var dashboard = DashboardViewModel()
    @State private var section: SidebarSection = .home

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if !appState.hasScreenPermission { permissionBanner }
                if appState.isProcessing { processingBanner }

                Group {
                    switch section {
                    case .home:
                        HomeView(dashboard: dashboard, goToRecordings: { section = .recordings })
                    case .recordings:
                        RecordingsView(model: dashboard)
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.windowBackground)
            }
        }
        .overlay {
            if appState.phase == .countdown, let session = appState.session {
                CountdownView(session: session)
            }
        }
        .onAppear {
            appState.devices.refreshAll()
            seedDefaults()
            dashboard.refresh()
        }
        .task {
            await appState.checkScreenPermission()
        }
        .onChange(of: appState.recordingsRevision) { _, _ in
            dashboard.refresh()
        }
        .onChange(of: appState.config) { _, newValue in
            newValue.save()
        }
        .alert("Recording Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } })) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    // MARK: - Banners

    private var permissionBanner: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording permission needed")
                    .font(.subheadline.weight(.semibold))
                Text("Enable Arcade in System Settings, then quit and reopen the app.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .background(Color.orange.opacity(0.12))
    }

    private var processingBanner: some View {
        HStack(spacing: Theme.Space.sm) {
            ProgressView().controlSize(.small)
            Text("Finalizing recording")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Text("· merging webcam and screen in the background")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .background(Theme.primaryTint)
    }

    // MARK: - Defaults

    private func seedDefaults() {
        let devices = appState.devices
        if appState.config.saveDirectory == nil {
            appState.config.saveDirectory = StorageManager.shared.saveDirectory
        }
        if appState.config.displayID == nil {
            appState.config.displayID = devices.displays.first?.id
        }
        if appState.config.cameraID == nil {
            appState.config.cameraID = devices.cameras.first?.id
        }
        if appState.config.microphoneID == nil {
            appState.config.microphoneID = devices.microphones.first?.id
        }
    }
}
