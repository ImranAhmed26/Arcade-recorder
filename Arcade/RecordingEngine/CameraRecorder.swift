import Foundation
import AVFoundation

/// Manages the webcam AVCaptureSession. Drives the live preview layer and writes
/// a separate `webcam.mp4` containing the camera video + microphone audio.
///
/// Stream separation (for later FFmpeg composition):
///   screen.mp4  = screen video + system audio   (ScreenRecorder)
///   webcam.mp4  = camera video + microphone audio (this class)
///
/// All writer access happens on `sampleQueue`; UI calls (configure/start/stop)
/// come from the main actor and hop onto the queue where needed.
final class CameraRecorder: NSObject {
    let session = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let sampleQueue = DispatchQueue(label: "com.binate.arcade.camera.samples")

    private var hasCamera = false
    private var hasMic = false

    // Touched only on sampleQueue.
    private var writer: RecordingWriter?
    private var recording = false
    private var paused = false
    private var micEnabled = true
    private var videoEnabled = true

    // MARK: - Configuration

    /// Build the session with the chosen camera and/or microphone.
    func configure(cameraID: String?, micID: String?, captureMic: Bool) {
        session.beginConfiguration()
        session.sessionPreset = .high
        for input in session.inputs { session.removeInput(input) }

        if let cameraID, let device = AVCaptureDevice(uniqueID: cameraID),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
            hasCamera = true
            if !session.outputs.contains(videoOutput) {
                videoOutput.alwaysDiscardsLateVideoFrames = false
                videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
                if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            }
        }

        if captureMic, let micID, let device = AVCaptureDevice(uniqueID: micID),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
            hasMic = true
            if !session.outputs.contains(audioOutput) {
                audioOutput.setSampleBufferDelegate(self, queue: sampleQueue)
                if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
            }
        }
        session.commitConfiguration()
    }

    var producesFile: Bool { hasCamera || hasMic }
    var hasVideoTrack: Bool { hasCamera }

    // MARK: - Session lifecycle

    func startSession() {
        guard !session.isRunning else { return }
        let session = self.session
        sampleQueue.async { session.startRunning() }
    }

    func stopSession() {
        guard session.isRunning else { return }
        let session = self.session
        sampleQueue.async { session.stopRunning() }
    }

    // MARK: - Recording

    /// Begin writing the webcam file. Safe to call even if no camera/mic (no-op).
    func startRecording(url: URL, frameRate: Int, videoBitrate: Int, audioBitrate: Int) {
        guard producesFile else { return }
        sampleQueue.async {
            self.writer = try? RecordingWriter(
                url: url,
                width: 1280, height: 720,   // camera native is variable; writer scales source frames
                frameRate: frameRate,
                videoBitrate: videoBitrate,
                hasVideo: self.hasCamera,
                hasAudio: self.hasMic,
                audioBitrate: audioBitrate)
            self.recording = true
        }
    }

    func setPaused(_ paused: Bool) { sampleQueue.async { self.paused = paused } }
    func setMicEnabled(_ enabled: Bool) { sampleQueue.async { self.micEnabled = enabled } }
    func setVideoEnabled(_ enabled: Bool) { sampleQueue.async { self.videoEnabled = enabled } }

    /// Finalize the webcam file. Returns true if a file was written.
    @discardableResult
    func finishRecording() async -> Bool {
        await withCheckedContinuation { continuation in
            sampleQueue.async {
                self.recording = false
                guard let writer = self.writer, writer.hasStarted else {
                    self.writer?.cancel()
                    self.writer = nil
                    continuation.resume(returning: false)
                    return
                }
                self.writer = nil
                Task {
                    await writer.finish()
                    continuation.resume(returning: true)
                }
            }
        }
    }

    func cancelRecording() {
        sampleQueue.async {
            self.recording = false
            self.writer?.cancel()
            self.writer = nil
        }
    }
}

extension CameraRecorder: AVCaptureVideoDataOutputSampleBufferDelegate,
                          AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard recording, !paused, let writer else { return }
        if output === videoOutput {
            guard videoEnabled else { return }
            writer.appendVideo(sampleBuffer)
        } else if output === audioOutput {
            guard micEnabled else { return }
            writer.appendAudio(sampleBuffer)
        }
    }
}
