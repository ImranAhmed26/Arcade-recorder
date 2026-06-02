import SwiftUI

/// Minimal floating control bar shown during countdown/recording.
struct ControlBarView: View {
    @ObservedObject var session: RecordingSessionViewModel

    var body: some View {
        HStack(spacing: 14) {
            // Timer / status
            HStack(spacing: 6) {
                Circle()
                    .fill(isRecording ? .red : .orange)
                    .frame(width: 9, height: 9)
                Text(statusText)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 92, alignment: .leading)

            Divider().frame(height: 22)

            controlButton(systemName: session.micEnabled ? "mic.fill" : "mic.slash.fill",
                          active: session.micEnabled) { session.toggleMic() }
            controlButton(systemName: session.webcamEnabled ? "video.fill" : "video.slash.fill",
                          active: session.webcamEnabled) { session.toggleWebcam() }

            controlButton(systemName: session.stage == .paused ? "play.fill" : "pause.fill",
                          active: true, disabled: !canPause) { session.togglePause() }

            Divider().frame(height: 22)

            // Stop
            Button { session.stop() } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Discard / retake
            Button { session.discard() } label: {
                Image(systemName: "trash.fill")
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .help("Discard")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }

    private var isRecording: Bool { session.stage == .recording }
    private var canPause: Bool {
        session.stage == .recording || session.stage == .paused
    }

    private var statusText: String {
        switch session.stage {
        case .countdown(let n): return "Starting \(n)"
        case .paused:           return "Paused"
        default:                return session.formattedElapsed
        }
    }

    @ViewBuilder
    private func controlButton(systemName: String,
                               active: Bool,
                               disabled: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(active ? .white : .white.opacity(0.4))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
