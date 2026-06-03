import SwiftUI

/// Full recording configuration, grouped into cards.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var saveDirPath: String = StorageManager.shared.saveDirectory?.path ?? "Not set"

    private var devices: DeviceManager { appState.devices }
    private var config: Binding<RecordingConfig> { $appState.config }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text("Settings")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                Card("Appearance") {
                    SettingRow("Theme", systemImage: "circle.lefthalf.filled") {
                        Picker("", selection: $appState.themeMode) {
                            ForEach(ThemeMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                Card("Devices") {
                    SettingRow("Camera", systemImage: "video") {
                        Picker("", selection: config.cameraID) {
                            Text("Off").tag(String?.none)
                            ForEach(devices.cameras) { c in
                                Text(c.name).tag(String?.some(c.id))
                            }
                        }.labelsHidden().fixedSize()
                    }
                    SettingRow("Microphone", systemImage: "mic") {
                        Picker("", selection: config.microphoneID) {
                            Text("Off").tag(String?.none)
                            ForEach(devices.microphones) { m in
                                Text(m.name).tag(String?.some(m.id))
                            }
                        }.labelsHidden().fixedSize()
                    }
                    SettingRow("Display", systemImage: "display") {
                        Picker("", selection: config.displayID) {
                            Text("None").tag(CGDirectDisplayID?.none)
                            ForEach(devices.displays) { d in
                                Text(d.name).tag(CGDirectDisplayID?.some(d.id))
                            }
                        }.labelsHidden().fixedSize()
                    }
                }

                Card("Audio") {
                    SettingRow("Capture microphone", systemImage: "mic.fill") {
                        Toggle("", isOn: config.captureMicrophone).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow("Capture system / internal audio", systemImage: "speaker.wave.2.fill") {
                        Toggle("", isOn: config.captureSystemAudio).labelsHidden().toggleStyle(.switch)
                    }
                }

                Card("Video") {
                    SettingRow("Resolution", systemImage: "rectangle.on.rectangle") {
                        Picker("", selection: config.quality) {
                            ForEach(VideoQuality.allCases) { q in Text(q.rawValue).tag(q) }
                        }.labelsHidden().fixedSize()
                    }
                    SettingRow("Frame rate", systemImage: "speedometer") {
                        Picker("", selection: config.frameRate) {
                            Text("24 fps").tag(24)
                            Text("30 fps").tag(30)
                            Text("60 fps").tag(60)
                        }.labelsHidden().fixedSize()
                    }
                }

                Card("Countdown") {
                    SettingRow("Before recording", systemImage: "timer") {
                        Picker("", selection: config.countdownSeconds) {
                            Text("Off").tag(0)
                            Text("3 seconds").tag(3)
                            Text("5 seconds").tag(5)
                        }.labelsHidden().fixedSize()
                    }
                }

                Card("Save Location") {
                    Text(saveDirPath)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    HStack {
                        Button("Choose…") { chooseDirectory() }
                        Button("Open in Finder") { StorageManager.shared.revealSaveDirectory() }
                    }
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            StorageManager.shared.setSaveDirectory(url)
            appState.config.saveDirectory = url
            saveDirPath = url.path
        }
    }
}
