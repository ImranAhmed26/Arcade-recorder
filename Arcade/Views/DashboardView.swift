import SwiftUI

/// The central hub: configuration on the left, recent recordings on the right,
/// and a single primary "Start Recording" action.
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var dashboard = DashboardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Non-blocking status banners stacked at the top.
            if !appState.hasScreenPermission {
                permissionBanner
            }
            if appState.isProcessing {
                processingBanner
            }

            HSplitView {
                // Left: configuration hub
                VStack(spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        ConfigPanel(devices: appState.devices,
                                    config: $appState.config,
                                    disabled: appState.phase != .dashboard)
                    }
                    Divider()
                    startBar
                }
                .frame(minWidth: 360, idealWidth: 400, maxWidth: 460)

                // Right: recent recordings
                VStack(spacing: 0) {
                    HStack {
                        Text("Recent Recordings").font(.headline)
                        Spacer()
                        Button { dashboard.refresh() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                    }
                    .padding()
                    Divider()
                    // Processing placeholder — appears immediately when recording
                    // stops, before FFmpeg finishes and the real row shows up.
                    if let name = appState.processingRecordingName {
                        processingRow(name: name)
                        Divider()
                    }
                    RecordingsList(model: dashboard)
                }
                .frame(minWidth: 360)
            }
        }
        .overlay {
            if appState.phase == .countdown, let session = appState.session {
                CountdownView(session: session)
            }
        }
        // No blocking overlay. Processing is shown as a non-intrusive banner
        // so the user can browse the recordings list while merge runs.
        .onAppear {
            appState.devices.refreshAll()
            seedDefaults()
            dashboard.refresh()
        }
        .task {
            // Check screen-recording permission on every dashboard appear.
            // On first launch this call triggers the system permission dialog —
            // the user grants it in System Settings, quits and relaunches, and
            // then this call succeeds so the banner disappears and recording works.
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

    // MARK: - Permission banner

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording permission needed")
                    .font(.headline)
                Text("Arcade needs access to record your screen. Grant it in System Settings, then quit and reopen Arcade.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open System Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.12))
    }

    /// Inline placeholder row shown in the recordings list while FFmpeg merges.
    @ViewBuilder
    private func processingRow(name: String) -> some View {
        HStack(spacing: 12) {
            // Placeholder thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                ProgressView()
                    .controlSize(.small)
            }
            .frame(width: 96, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Processing — merging webcam and screen…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var processingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Finalizing recording")
                .font(.subheadline.weight(.medium))
            Text("·  Merging webcam and screen in the background…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Helpers

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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill").foregroundStyle(.red)
            Text("Arcade").font(.title2.bold())
            Spacer()
        }
        .padding()
    }

    private var startBar: some View {
        Button {
            appState.startSession()
        } label: {
            Label("Start Recording", systemImage: "record.circle")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(!appState.hasScreenPermission
                  || appState.phase != .dashboard
                  || appState.config.displayID == nil)
        .padding()
    }
}
