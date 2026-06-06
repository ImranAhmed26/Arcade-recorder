import Foundation
import AVFoundation

/// Wraps an `AVAssetWriter` for a single MP4 output with one video track and an
/// optional audio track. H.264 is encoded via VideoToolbox (hardware) by default
/// for the `.h264` codec on Apple silicon / Intel with HW encoders. Audio is AAC.
///
/// Thread-safety: all `append`/`start`/`finish` calls for one instance must come
/// from a single serial queue (the capture output queue).
final class RecordingWriter {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput?
    private let audioInput: AVAssetWriterInput?

    private var started = false
    private(set) var firstPTS: CMTime?

    init(url: URL,
         width: Int,
         height: Int,
         frameRate: Int,
         videoBitrate: Int,
         hasVideo: Bool = true,
         hasAudio: Bool,
         audioBitrate: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        if hasVideo {
            let compression: [String: Any] = [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: true,
            ]
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compression,
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) { writer.add(input) }
            videoInput = input
        } else {
            videoInput = nil
        }

        if hasAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: audioBitrate,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) { writer.add(input) }
            audioInput = input
        } else {
            audioInput = nil
        }
    }

    /// Lazily begins the writer session anchored at the first received PTS so
    /// video and audio share a common timeline.
    private func startIfNeeded(at pts: CMTime) {
        guard !started else { return }
        started = true
        firstPTS = pts
        writer.startWriting()
        writer.startSession(atSourceTime: pts)
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let videoInput else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        startIfNeeded(at: pts)
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData else { return }
        videoInput.append(sampleBuffer)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let audioInput else { return }
        // If there's no video track, audio anchors the timeline itself.
        if videoInput == nil {
            startIfNeeded(at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        guard started, writer.status == .writing, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    var hasStarted: Bool { started }

    func finish() async {
        guard started, writer.status == .writing else {
            writer.cancelWriting()
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
    }

    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
    }
}
