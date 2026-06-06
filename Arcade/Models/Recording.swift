import Foundation

/// Normalized placement of the circular webcam overlay, expressed as fractions
/// of the recorded display (so it maps cleanly onto the screen video at any
/// resolution). Origin is top-left, matching FFmpeg's overlay coordinates.
struct WebcamPlacement: Codable, Equatable {
    var x: Double          // left edge / display width
    var y: Double          // top edge / display height
    var diameter: Double   // diameter / display width
}

/// One position sample captured during recording. `time` is seconds of recording
/// elapsed (pauses excluded), so it aligns with the FFmpeg timeline variable `t`.
struct WebcamPositionKeyframe: Codable {
    let time: Double   // seconds since recording started (pauses not counted)
    let x: Double      // left edge as fraction of display width
    let y: Double      // top edge as fraction of display height (top-left = FFmpeg origin)
}

/// Recording mode of a segment within a session.
/// - `normal`: screen + circular webcam PiP (the default).
/// - `fullCamera`: a full-screen webcam segment (Full Camera Mode).
enum SegmentMode: String, Codable, Equatable {
    case normal
    case fullCamera
}

/// One contiguous mode segment of a recording, on the pause-excluded media clock
/// (same clock as `WebcamPositionKeyframe`). Segments are recorded during capture
/// and, in a later phase, stitched in order at export. While the export ignores
/// them, a recording stays byte-identical to the pre-segment behavior.
struct RecordingSegment: Codable, Equatable {
    let mode: SegmentMode
    let start: TimeInterval
    var end: TimeInterval
}

/// A single saved recording. Each recording lives in its own folder:
///   <saveDir>/<id>/final.mp4   (merged webcam + screen — the primary output)
///   <saveDir>/<id>/screen.mp4  (raw screen + system audio, removed after merge)
///   <saveDir>/<id>/webcam.mp4  (raw webcam + mic, optional, removed after merge)
///   <saveDir>/<id>/meta.json
struct Recording: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    let createdAt: Date
    var duration: TimeInterval

    /// Folder containing this recording's files.
    let folderName: String
    let screenFileName: String
    let webcamFileName: String?

    /// Set once the screen + webcam streams have been merged.
    var mergedFileName: String?

    /// Where the webcam circle sat on screen, used by the merge step.
    var webcamPlacement: WebcamPlacement?

    /// Ordered mode segments (Full Camera Mode). Empty for older recordings.
    /// Currently recorded for metadata only; export stitching lands in a later phase.
    var segments: [RecordingSegment] = []

    static let screenFile = "screen.mp4"
    static let webcamFile = "webcam.mp4"
    static let mergedFile = "final.mp4"
    static let thumbFile = "thumb.jpg"
    static let metaFile = "meta.json"

    init(id: UUID = UUID(),
         displayName: String,
         createdAt: Date,
         duration: TimeInterval,
         hasWebcam: Bool,
         webcamPlacement: WebcamPlacement? = nil) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.duration = duration
        self.folderName = id.uuidString
        self.screenFileName = Recording.screenFile
        self.webcamFileName = hasWebcam ? Recording.webcamFile : nil
        self.webcamPlacement = webcamPlacement
    }

    /// The file the dashboard should play / thumbnail: merged if present, else screen.
    var primaryFileName: String { mergedFileName ?? screenFileName }
}
