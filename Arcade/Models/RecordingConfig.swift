import Foundation
import CoreGraphics

/// Video quality presets. MVP defaults to 1080p.
enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"

    var id: String { rawValue }

    /// Target output dimensions (16:9).
    var dimensions: (width: Int, height: Int) {
        switch self {
        case .p720:  return (1280, 720)
        case .p1080: return (1920, 1080)
        case .p1440: return (2560, 1440)
        }
    }

    /// H.264 intermediate capture bitrate (bits/sec). Lower than original to
    /// reduce file size while still surviving one FFmpeg re-encode cleanly.
    var videoBitrate: Int {
        switch self {
        case .p720:  return 3_000_000
        case .p1080: return 6_000_000
        case .p1440: return 10_000_000
        }
    }
}

/// All user-selectable capture settings. Identifiers are stored as stable
/// strings so a saved config survives device re-enumeration.
struct RecordingConfig: Equatable {
    var displayID: CGDirectDisplayID?
    var cameraID: String?
    var microphoneID: String?

    var captureSystemAudio: Bool = true
    var captureMicrophone: Bool = true

    /// Whether the webcam is included this session (the Home "Screen + Camera"
    /// vs "Screen only" toggle). The camera selection itself is remembered.
    var includeCamera: Bool = true

    var quality: VideoQuality = .p1080
    var frameRate: Int = 30

    /// Countdown length in seconds before recording starts (0 = no countdown).
    var countdownSeconds: Int = 3

    /// User-selected persistent save directory (resolved from a security-scoped bookmark).
    var saveDirectory: URL?

    /// AAC audio bitrate (128–192 kbps band).
    var audioBitrate: Int = 160_000

    /// Camera to actually use this session — nil when "Screen only" is selected.
    var effectiveCameraID: String? { includeCamera ? cameraID : nil }
}

// MARK: - Persistence

extension RecordingConfig {
    /// Codable subset persisted between launches. The save directory is restored
    /// from its security-scoped bookmark instead, and live device availability is
    /// re-validated on the dashboard.
    private struct Persisted: Codable {
        var cameraID: String?
        var microphoneID: String?
        var captureSystemAudio: Bool
        var captureMicrophone: Bool
        var includeCamera: Bool?
        var quality: VideoQuality
        var frameRate: Int
        var countdownSeconds: Int?
    }

    private static let key = "arcade.config"

    func save() {
        let p = Persisted(cameraID: cameraID, microphoneID: microphoneID,
                          captureSystemAudio: captureSystemAudio,
                          captureMicrophone: captureMicrophone,
                          includeCamera: includeCamera,
                          quality: quality, frameRate: frameRate,
                          countdownSeconds: countdownSeconds)
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    mutating func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let p = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        cameraID = p.cameraID
        microphoneID = p.microphoneID
        captureSystemAudio = p.captureSystemAudio
        captureMicrophone = p.captureMicrophone
        includeCamera = p.includeCamera ?? true
        quality = p.quality
        frameRate = p.frameRate
        countdownSeconds = p.countdownSeconds ?? 3
    }
}
