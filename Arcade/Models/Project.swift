import Foundation

/// A webcam + voice narration clip layered over the base recording at a timestamp.
/// Rendered as a circular picture-in-picture during its window.
struct NarrationClip: Codable, Identifiable, Equatable {
    let id: UUID
    var fileName: String        // clip-<id>.mp4 (webcam + mic)
    var timelineStart: Double   // seconds on the base timeline
    var duration: Double        // placed length (after trim)
    var trimIn: Double          // in-point within the source clip
    var pip: WebcamPlacement    // circle position/size (reuses the recorder's type)

    init(id: UUID = UUID(),
         fileName: String,
         timelineStart: Double,
         duration: Double,
         trimIn: Double = 0,
         pip: WebcamPlacement) {
        self.id = id
        self.fileName = fileName
        self.timelineStart = timelineStart
        self.duration = duration
        self.trimIn = trimIn
        self.pip = pip
    }

    var timelineEnd: Double { timelineStart + duration }
}

/// A tutorial project: a base screen recording with narration clips layered on top.
/// Each project lives in its own folder, mirroring the `Recording` per-folder pattern:
///   <saveDir>/Projects/<id>/base.mp4      (copied from the source recording)
///   <saveDir>/Projects/<id>/clip-<id>.mp4 (narration clips)
///   <saveDir>/Projects/<id>/project.json
///   <saveDir>/Projects/<id>/export.mp4    (after export)
struct Project: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date

    let folderName: String
    var baseFileName: String
    var baseDuration: Double

    /// Base trim (Phase D). Defaults to the full clip.
    var baseTrimIn: Double
    var baseTrimOut: Double

    var clips: [NarrationClip]

    static let baseFile = "base.mp4"
    static let metaFile = "project.json"
    static let exportFile = "export.mp4"

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = Date(),
         baseDuration: Double,
         clips: [NarrationClip] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.folderName = id.uuidString
        self.baseFileName = Project.baseFile
        self.baseDuration = baseDuration
        self.baseTrimIn = 0
        self.baseTrimOut = baseDuration
        self.clips = clips
    }

    /// Visible base length after trimming.
    var trimmedDuration: Double { max(0, baseTrimOut - baseTrimIn) }
}
