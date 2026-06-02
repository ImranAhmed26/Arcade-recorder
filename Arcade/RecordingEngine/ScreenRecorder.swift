import Foundation
import ScreenCaptureKit
import AVFoundation

/// Captures a display with ScreenCaptureKit and writes it (plus optional system
/// audio) to `screen.mp4` via `RecordingWriter`. Arcade's own overlay windows are
/// excluded from the captured content.
///
/// SCShareableContent (which triggers the screen-recording TCC prompt) is called
/// ONLY here, at the moment capture actually begins — not during device enumeration.
final class ScreenRecorder: NSObject {
    private var stream: SCStream?
    private var writer: RecordingWriter?
    private let outputQueue = DispatchQueue(label: "com.binate.arcade.screen.output")
    private var paused = false

    // MARK: - Start / stop

    func start(displayID: CGDirectDisplayID,
               excludingWindowNumbers: [Int],
               config: RecordingConfig,
               outputURL: URL) async throws {
        // Permission is pre-checked in AppState.startSession() via CGPreflightScreenCaptureAccess().
        // This call should always succeed; if it doesn't, surface a clear message.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        } catch {
            throw NSError(domain: "Arcade", code: 3, userInfo: [
                NSLocalizedDescriptionKey:
                    "Screen Recording permission was not granted. Please go to System Settings → Privacy & Security → Screen Recording, enable Arcade, then try again.",
            ])
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID })
                         ?? content.displays.first else {
            throw NSError(domain: "Arcade", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not find the selected display. Make sure Screen Recording permission is granted in System Settings → Privacy & Security."])
        }

        let excluded = content.windows.filter { excludingWindowNumbers.contains(Int($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let (w, h) = config.quality.dimensions
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = w
        streamConfig.height = h
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.queueDepth = 6
        streamConfig.showsCursor = true
        streamConfig.capturesAudio = config.captureSystemAudio
        if config.captureSystemAudio {
            streamConfig.sampleRate = 44_100
            streamConfig.channelCount = 2
        }

        let writer = try RecordingWriter(
            url: outputURL,
            width: w, height: h,
            frameRate: config.frameRate,
            videoBitrate: config.quality.videoBitrate,
            hasAudio: config.captureSystemAudio,
            audioBitrate: config.audioBitrate)
        self.writer = writer

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        if config.captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        }
        self.stream = stream
        try await stream.startCapture()
    }

    func setPaused(_ paused: Bool) {
        outputQueue.async { self.paused = paused }
    }

    @discardableResult
    func stop() async -> Bool {
        if let stream { try? await stream.stopCapture() }
        stream = nil
        let writer = self.writer
        self.writer = nil
        guard let writer, writer.hasStarted else {
            writer?.cancel()
            return false
        }
        await writer.finish()
        return true
    }

    func cancel() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil
        writer?.cancel()
        writer = nil
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard !paused, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
                    sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: raw),
                  status == .complete else { return }
            writer?.appendVideo(sampleBuffer)
        case .audio:
            writer?.appendAudio(sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Error surfaces via the onError callback in RecordingSessionViewModel.
    }
}
