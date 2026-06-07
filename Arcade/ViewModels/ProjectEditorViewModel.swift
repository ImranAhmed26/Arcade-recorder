import Foundation
import AVKit
import AVFoundation
import Combine

/// Recording state for a narration clip session inside the editor.
enum NarrationState: Equatable {
    case idle
    case recording
    case finishing
}

/// Drives the project editor across all phases:
///   A - base playback
///   B - narration clip recording + synced circular overlay
///   C - timeline editing (place/reorder/trim/delete) — wired in Phase C
///   D - base trimming — wired in Phase D
///   E - export — wired in Phase E
@MainActor
final class ProjectEditorViewModel: ObservableObject {
    @Published var project: Project
    @Published var narrationState: NarrationState = .idle
    @Published var errorMessage: String?

    /// Live playhead position (seconds), updated ~10 Hz during playback.
    @Published var playhead: Double = 0

    let player: AVPlayer
    let camera = CameraRecorder()

    private var timeObserver: Any?
    private var currentNarrationID: UUID?

    init(project: Project) {
        self.project = project
        if let url = StorageManager.shared.projectURL(project, fileName: project.baseFileName) {
            player = AVPlayer(url: url)
        } else {
            player = AVPlayer()
        }
        startPlayheadObserver()
    }

    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
    }

    // MARK: - Playhead

    private func startPlayheadObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.playhead = time.seconds.isFinite ? time.seconds : 0
        }
    }

    // MARK: - Clips active at playhead

    /// Clips whose window contains the current playhead (for the preview overlay).
    var activeClips: [NarrationClip] {
        project.clips.filter { playhead >= $0.timelineStart && playhead < $0.timelineEnd }
    }

    // MARK: - Narration recording

    func startNarration(config: RecordingConfig) {
        guard narrationState == .idle else { return }
        player.pause()

        // Configure the camera + mic using the app's recording config.
        camera.configure(cameraID: config.cameraID,
                         micID: config.microphoneID,
                         captureMic: config.captureMicrophone)
        camera.startSession()

        let clipID = UUID()
        currentNarrationID = clipID

        guard let folder = try? StorageManager.shared.projectFolder(project.id) else {
            errorMessage = "Could not access project folder."
            return
        }
        let fileName = "clip-\(clipID.uuidString).mp4"
        let clipURL = folder.appendingPathComponent(fileName)

        camera.startRecording(url: clipURL,
                               frameRate: 30,
                               videoBitrate: 8_000_000,
                               audioBitrate: 160_000)
        narrationState = .recording
    }

    func stopNarration() {
        guard narrationState == .recording, let clipID = currentNarrationID else { return }
        narrationState = .finishing
        camera.stopSession()

        Task {
            let saved = await camera.finishRecording()
            guard saved else {
                narrationState = .idle
                currentNarrationID = nil
                return
            }

            let fileName = "clip-\(clipID.uuidString).mp4"
            // Duration via AVAsset; fall back to elapsed time if asset not ready.
            var clipDuration: Double = 5
            if let folder = try? StorageManager.shared.projectFolder(project.id) {
                let url = folder.appendingPathComponent(fileName)
                let asset = AVURLAsset(url: url)
                if let dur = try? await asset.load(.duration) {
                    clipDuration = dur.seconds.isFinite ? dur.seconds : 5
                }
            }

            let start = max(0, playhead - clipDuration)
            let clip = NarrationClip(
                id: clipID,
                fileName: fileName,
                timelineStart: start,
                duration: clipDuration,
                pip: WebcamPlacement(x: 0.02, y: 0.74, diameter: 0.18))   // bottom-left default

            project.clips.append(clip)
            StorageManager.shared.writeProject(project)
            narrationState = .idle
            currentNarrationID = nil
        }
    }

    func cancelNarration() {
        guard narrationState == .recording else { return }
        camera.stopSession()
        camera.cancelRecording()
        narrationState = .idle
        currentNarrationID = nil
    }

    // MARK: - Clip management (Phase B basis; extended in C/D)

    func deleteClip(_ clip: NarrationClip) {
        // Remove the file.
        if let folder = try? StorageManager.shared.projectFolder(project.id) {
            let url = folder.appendingPathComponent(clip.fileName)
            try? FileManager.default.removeItem(at: url)
        }
        project.clips.removeAll { $0.id == clip.id }
        StorageManager.shared.writeProject(project)
    }

    func save() {
        StorageManager.shared.writeProject(project)
    }
}
