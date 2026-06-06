import SwiftUI

/// Simple start page: recording mode, essential controls, and a big Start button.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var dashboard: DashboardViewModel
    var goToRecordings: () -> Void

    private var devices: DeviceManager { appState.devices }
    private var canRecord: Bool {
        appState.hasScreenPermission && appState.phase == .dashboard && appState.config.displayID != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                heroCard
                if !dashboard.recordings.isEmpty {
                    recentStrip
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to record")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Capture your screen with webcam and audio.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Recording mode
                Picker("", selection: $appState.config.includeCamera) {
                    Text("Screen + Camera").tag(true)
                    Text("Screen only").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Divider()

                // Essential controls
                VStack(spacing: Theme.Space.md) {
                    if devices.displays.count > 1 {
                        SettingRow("Display", systemImage: "display") {
                            Picker("", selection: $appState.config.displayID) {
                                ForEach(devices.displays) { d in
                                    Text(d.name).tag(CGDirectDisplayID?.some(d.id))
                                }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }

                    // Always present (keeps the card height constant so the
                    // Recent section below doesn't jump when toggling modes);
                    // disabled in "Screen only" mode.
                    SettingRow("Camera", systemImage: "video") {
                        Picker("", selection: $appState.config.cameraID) {
                            Text("Off").tag(String?.none)
                            ForEach(devices.cameras) { c in
                                Text(c.name).tag(String?.some(c.id))
                            }
                        }
                        .labelsHidden().fixedSize()
                    }
                    .disabled(!appState.config.includeCamera)
                    .opacity(appState.config.includeCamera ? 1 : 0.45)

                    SettingRow("Microphone", systemImage: "mic") {
                        Picker("", selection: $appState.config.microphoneID) {
                            Text("Off").tag(String?.none)
                            ForEach(devices.microphones) { m in
                                Text(m.name).tag(String?.some(m.id))
                            }
                        }
                        .labelsHidden().fixedSize()
                    }

                    SettingRow("System audio", systemImage: "speaker.wave.2") {
                        Toggle("", isOn: $appState.config.captureSystemAudio)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                // Start
                Button {
                    appState.startSession()
                } label: {
                    Label("Start Recording", systemImage: "record.circle.fill")
                }
                .buttonStyle(RecordButtonStyle())
                .disabled(!canRecord)

                if !appState.hasScreenPermission {
                    Text("Grant Screen Recording permission to start.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Recent

    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                SectionLabel("Recent")
                Spacer()
                Button("See all", action: goToRecordings)
                    .buttonStyle(.link)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.md) {
                    ForEach(dashboard.recordings.prefix(4)) { rec in
                        RecordingCard(recording: rec, model: dashboard, compact: true)
                            .frame(width: 200)
                    }
                }
            }
        }
    }
}
