import SwiftUI
import AVKit
import AVFoundation

/// AppKit `AVPlayerView` wrapper. Used instead of SwiftUI's `VideoPlayer`, which
/// crashes during generic-metadata instantiation (_AVKit_SwiftUI) on this macOS.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}

// MARK: - Editor

/// Project editor host.
struct ProjectEditorView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: ProjectEditorViewModel

    init(project: Project) {
        _vm = StateObject(wrappedValue: ProjectEditorViewModel(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video canvas + circular narration overlays.
            videoCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Timeline (Phase C) + toolbar.
            VStack(spacing: 0) {
                Divider()
                TimelineView(
                    project: $vm.project,
                    playhead: $vm.playhead,
                    onSeek: { vm.seek(to: $0) },
                    onChanged: { vm.save() },
                    onDeleteClip: { vm.deleteClip($0) }
                )
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .background(Theme.windowBackground)
                Divider()
                toolbar
            }
        }
        .navigationTitle(vm.project.name)
        .onDisappear {
            vm.player.pause()
            vm.cancelNarration()
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    // MARK: - Video canvas

    /// The base player with synced circular webcam overlays for active clips.
    @ViewBuilder
    private var videoCanvas: some View {
        GeometryReader { geo in
            ZStack {
                PlayerView(player: vm.player)
                    .background(.black)

                // Live circular overlay while recording a new narration.
                if vm.narrationState == .recording {
                    liveNarrationOverlay(in: geo.size)
                }

                // Synced clip overlays — show any clip active at the current playhead.
                ForEach(vm.activeClips) { clip in
                    ClipOverlayView(clip: clip, projectID: vm.project.id, size: geo.size)
                }
            }
        }
    }

    /// Circular live camera preview shown while recording a narration clip.
    @ViewBuilder
    private func liveNarrationOverlay(in size: CGSize) -> some View {
        let d = size.width * 0.18
        let x = size.width * 0.02
        let y = size.height * 0.74 // bottom-left, same as default pip
        CameraPreview(session: vm.camera.session)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.55), lineWidth: 1.5))
            .frame(width: d, height: d)
            .position(x: x + d / 2, y: y + d / 2)
    }



    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.project.name).font(.headline)
                Text("\(Formatters.duration(vm.project.baseDuration)) base  ·  \(vm.project.clips.count) narration clip\(vm.project.clips.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()

            // Narration recording button.
            switch vm.narrationState {
            case .idle:
                Button {
                    vm.startNarration(config: appState.config)
                } label: {
                    Label("Record Narration", systemImage: "mic.badge.plus")
                }
                .buttonStyle(.borderedProminent).tint(Theme.record)
                .disabled(appState.config.cameraID == nil)
                .help(appState.config.cameraID == nil
                      ? "Select a camera in Settings to record narration"
                      : "Record a webcam + voice narration clip at the current playhead")

            case .recording:
                Button {
                    vm.stopNarration()
                } label: {
                    Label("Stop Narration", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Recording…").font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }

            case .finishing:
                ProgressView().controlSize(.small)
                Text("Saving…").font(.caption).foregroundStyle(Theme.textSecondary)
            }

            // Export placeholder (Phase E).
            Button { } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .disabled(true)
        }
        .padding(Theme.Space.lg)
        .background(Theme.windowBackground)
    }
}

// MARK: - Synced clip overlay

/// Renders a recorded narration clip as a circular PiP in the preview canvas
/// while the playhead is inside the clip's window.
struct ClipOverlayView: View {
    let clip: NarrationClip
    let projectID: UUID
    let size: CGSize

    @State private var player: AVPlayer?

    var body: some View {
        let d = clip.pip.diameter * size.width
        let px = clip.pip.x * size.width + d / 2
        // pip.y is top-left in display fractions (top-left origin); AppKit's
        // frame uses bottom-left, but SwiftUI .position() uses top-left too.
        let py = clip.pip.y * size.height + d / 2

        Group {
            if let player {
                ClipPlayerCanvas(player: player)
            } else {
                Circle().fill(.black.opacity(0.5))
                    .overlay(Image(systemName: "mic.fill")
                        .foregroundStyle(.white.opacity(0.7)))
            }
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.black.opacity(0.55), lineWidth: 1.5))
        .position(x: px, y: py)
        .task { await setupPlayer() }
        .onDisappear { player?.pause(); player = nil }
    }

    private func setupPlayer() async {
        guard let folder = try? StorageManager.shared.projectFolder(projectID) else { return }
        let url = folder.appendingPathComponent(clip.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let p = AVPlayer(url: url)
        // Seek to the trim in-point before handing it to the view.
        if clip.trimIn > 0 {
            await p.seek(to: CMTime(seconds: clip.trimIn, preferredTimescale: 600))
        }
        p.play()
        player = p
    }
}

/// NSViewRepresentable for a clip's circular AVPlayer (avoids the AVKit_SwiftUI crash).
struct ClipPlayerCanvas: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NSView {
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        let view = NSView()
        view.wantsLayer = true
        view.layer = layer
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView.layer as? AVPlayerLayer)?.player = player
    }
}
