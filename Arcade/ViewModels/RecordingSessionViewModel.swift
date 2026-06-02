import Foundation
import Combine
import SwiftUI
import ScreenCaptureKit

/// Orchestrates a single recording session: countdown → record → stop.
/// Owns the capture engines and is the binding hub for the floating overlays
/// (webcam circle + control bar).
@MainActor
final class RecordingSessionViewModel: ObservableObject {
    enum Stage: Equatable {
        case countdown(Int)   // 3, 2, 1
        case recording
        case paused
        case finished
    }

    @Published var stage: Stage = .countdown(3)
    @Published var elapsed: TimeInterval = 0
    @Published var micEnabled = true
    @Published var webcamEnabled = true

    /// True for the brief "REC" flash at the end of the countdown.
    @Published var showRecFlash = false

    let camera = CameraRecorder()
    private let screen = ScreenRecorder()
    private let config: RecordingConfig
    private var timer: AnyCancellable?

    // Position tracking — sampled at 4 Hz during recording, pauses excluded.
    private var positionKeyframes: [WebcamPositionKeyframe] = []
    private var positionElapsed: TimeInterval = 0
    private var positionTimer: AnyCancellable?

    let recordingID = UUID()
    private var folder: URL?
    private let startedAt = Date()

    /// Called when the session ends (stop or discard). Bool = whether a file was saved.
    var onFinish: ((Bool) -> Void)?

    /// Called if capture fails to start, or if merging fails (recording still kept).
    var onError: ((String) -> Void)?

    /// Called once capture has stopped and post-processing (merge) begins.
    /// Receives the recording's placeholder display name so the UI can show it
    /// in the recordings list immediately while FFmpeg runs in background.
    var onProcessingStarted: ((String) -> Void)?

    /// Supplies the webcam circle's on-screen placement (captured before overlays close).
    var webcamPlacementProvider: (() -> WebcamPlacement?)?

    init(config: RecordingConfig) {
        self.config = config
        self.micEnabled = config.captureMicrophone
        self.webcamEnabled = config.cameraID != nil
    }

    // MARK: - Camera preview

    func startCameraPreview() {
        guard config.cameraID != nil || config.captureMicrophone else { return }
        camera.configure(cameraID: config.cameraID,
                         micID: config.microphoneID,
                         captureMic: config.captureMicrophone)
        camera.startSession()
    }

    // MARK: - Countdown

    /// Runs 3 → 2 → 1, then flips to recording and invokes `onRecording`.
    func beginCountdown(onRecording: @escaping () -> Void) {
        Task { @MainActor in
            for n in stride(from: 3, through: 1, by: -1) {
                stage = .countdown(n)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            showRecFlash = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            showRecFlash = false
            stage = .recording
            startTimer()
            capturePosition(at: 0)   // t=0 keyframe before timer fires
            startPositionTimer()
            onRecording()
        }
    }

    // MARK: - Recording lifecycle

    /// Begin screen + webcam capture once the countdown completes.
    func startRecording(displayID: CGDirectDisplayID?, excludingWindowNumbers: [Int]) {
        guard let displayID else { return }
        Task {
            do {
                let folder = try StorageManager.shared.folder(for: recordingID)
                self.folder = folder

                // Webcam + mic file (separate stream).
                if camera.producesFile {
                    let webcamURL = folder.appendingPathComponent(Recording.webcamFile)
                    camera.startRecording(url: webcamURL,
                                          frameRate: config.frameRate,
                                          videoBitrate: config.quality.videoBitrate,
                                          audioBitrate: config.audioBitrate)
                }

                // Screen + system audio file.
                // SCShareableContent (and the TCC permission prompt) is triggered here,
                // once, when the user actually starts recording.
                let screenURL = folder.appendingPathComponent(Recording.screenFile)
                try await screen.start(displayID: displayID,
                                       excludingWindowNumbers: excludingWindowNumbers,
                                       config: config,
                                       outputURL: screenURL)
            } catch {
                camera.cancelRecording()
                camera.stopSession()
                stopTimer()
                stage = .finished
                if let folder { try? FileManager.default.removeItem(at: folder) }
                onError?(error.localizedDescription)
                onFinish?(false)
            }
        }
    }

    // MARK: - Controls

    func toggleMic() {
        micEnabled.toggle()
        camera.setMicEnabled(micEnabled)
    }

    func toggleWebcam() {
        webcamEnabled.toggle()
        camera.setVideoEnabled(webcamEnabled)
    }

    func togglePause() {
        switch stage {
        case .recording:
            stage = .paused
            stopTimer(); stopPositionTimer()
            screen.setPaused(true); camera.setPaused(true)
        case .paused:
            stage = .recording
            startTimer(); startPositionTimer()
            screen.setPaused(false); camera.setPaused(false)
        default: break
        }
    }

    func stop() {
        guard stage != .finished else { return }
        stopTimer()
        stopPositionTimer()
        stage = .finished

        // Snapshot overlay-dependent state while windows still exist.
        let placement = webcamPlacementProvider?()
        let capturedKeyframes = positionKeyframes
        let hasWebcamVideo = camera.hasVideoTrack

        // Stop the AVCaptureSession — fast, non-blocking.
        camera.stopSession()

        // Return to the dashboard IMMEDIATELY — before any file I/O.
        // Pass the placeholder name so the recordings list can show a live
        // "Processing…" row while FFmpeg runs in background.
        onProcessingStarted?(Formatters.defaultName(startedAt))

        Task {
            // Finalize both AVAssetWriters concurrently in background.
            async let screenSaved = screen.stop()
            async let webcamSaved = camera.finishRecording()
            let saved = await screenSaved
            let webcamFileSaved = await webcamSaved

            guard saved else {
                if let folder { try? FileManager.default.removeItem(at: folder) }
                onFinish?(false)
                return
            }
            await finalize(hasWebcamVideo: hasWebcamVideo,
                           webcamFileSaved: webcamFileSaved,
                           placement: placement,
                           keyframes: capturedKeyframes)
        }
    }

    func discard() {
        guard stage != .finished else { return }
        stopTimer()
        stopPositionTimer()
        stage = .finished
        camera.stopSession()
        camera.cancelRecording()
        Task {
            await screen.cancel()
            if let folder { try? FileManager.default.removeItem(at: folder) }
            onFinish?(false)
        }
    }

    /// Persist metadata, then merge the streams into a single `final.mp4`.
    private func finalize(hasWebcamVideo: Bool,
                          webcamFileSaved: Bool,
                          placement: WebcamPlacement?,
                          keyframes: [WebcamPositionKeyframe]) async {
        var recording = Recording(
            id: recordingID,
            displayName: Formatters.defaultName(startedAt),
            createdAt: startedAt,
            duration: elapsed,
            hasWebcam: hasWebcamVideo,
            webcamPlacement: hasWebcamVideo ? placement : nil)
        StorageManager.shared.writeMeta(recording)

        guard let folder else { onFinish?(true); return }
        let screenURL = folder.appendingPathComponent(Recording.screenFile)
        let webcamURL = folder.appendingPathComponent(Recording.webcamFile)
        let outputURL = folder.appendingPathComponent(Recording.mergedFile)

        // Only merge when there's a webcam/mic stream to fold in.
        guard webcamFileSaved else { onFinish?(true); return }

        let diameter = placement?.diameter ?? 0.09375   // 180pt / 1920px default
        let kf = hasWebcamVideo ? keyframes : []
        do {
            try await Task.detached(priority: .userInitiated) {
                _ = try MergeService.merge(screen: screenURL,
                                           webcam: webcamURL,
                                           keyframes: kf,
                                           diameter: diameter,
                                           output: outputURL)
            }.value
            recording.mergedFileName = Recording.mergedFile
            StorageManager.shared.writeMeta(recording)
            // Single clean output: remove the raw streams.
            try? FileManager.default.removeItem(at: screenURL)
            try? FileManager.default.removeItem(at: webcamURL)
            onFinish?(true)
        } catch {
            // Keep the raw files so the recording is still usable.
            onError?((error as? MergeService.MergeError)?.errorDescription
                     ?? error.localizedDescription)
            onFinish?(true)
        }
    }

    // MARK: - Elapsed timer

    func startTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.elapsed += 1 }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    var formattedElapsed: String { Formatters.duration(elapsed) }

    // MARK: - Position tracking (4 Hz, pauses excluded)

    private func startPositionTimer() {
        positionTimer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.positionElapsed += 0.25
                self.capturePosition(at: self.positionElapsed)
            }
    }

    private func stopPositionTimer() {
        positionTimer?.cancel()
        positionTimer = nil
    }

    private func capturePosition(at time: TimeInterval) {
        guard let placement = webcamPlacementProvider?() else { return }
        // Skip if the circle hasn't moved more than ~0.3% of screen width (≈6px on 1920).
        if let last = positionKeyframes.last,
           abs(last.x - placement.x) < 0.003,
           abs(last.y - placement.y) < 0.003 { return }
        positionKeyframes.append(
            WebcamPositionKeyframe(time: time, x: placement.x, y: placement.y))
    }
}
