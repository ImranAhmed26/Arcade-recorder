import SwiftUI
import UniformTypeIdentifiers

/// Recording configuration hub: display / camera / mic selection, audio toggles,
/// quality + fps, and the persistent save directory picker.
struct ConfigPanel: View {
    @ObservedObject var devices: DeviceManager
    @Binding var config: RecordingConfig
    let disabled: Bool

    @State private var saveDirPath: String = StorageManager.shared.saveDirectory?.path ?? "Not set"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Screen") {
                Picker("Display", selection: $config.displayID) {
                    Text("None").tag(CGDirectDisplayID?.none)
                    ForEach(devices.displays) { d in
                        Text(d.name).tag(CGDirectDisplayID?.some(d.id))
                    }
                }
            }

            section("Camera") {
                Picker("Webcam", selection: $config.cameraID) {
                    Text("Off").tag(String?.none)
                    ForEach(devices.cameras) { c in
                        Text(c.name).tag(String?.some(c.id))
                    }
                }
            }

            section("Audio") {
                Picker("Microphone", selection: $config.microphoneID) {
                    Text("None").tag(String?.none)
                    ForEach(devices.microphones) { m in
                        Text(m.name).tag(String?.some(m.id))
                    }
                }
                Toggle("Capture microphone", isOn: $config.captureMicrophone)
                Toggle("Capture system / internal audio", isOn: $config.captureSystemAudio)
            }

            section("Quality") {
                Picker("Resolution", selection: $config.quality) {
                    ForEach(VideoQuality.allCases) { q in Text(q.rawValue).tag(q) }
                }
                Picker("Frame rate", selection: $config.frameRate) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
            }

            section("Save Location") {
                HStack {
                    Text(saveDirPath)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                }
                HStack {
                    Button("Choose…") { chooseDirectory() }
                    Button("Open in Finder") { StorageManager.shared.revealSaveDirectory() }
                }
            }
        }
        .padding()
        .disabled(disabled)
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
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
            config.saveDirectory = url
            saveDirPath = url.path
        }
    }
}
