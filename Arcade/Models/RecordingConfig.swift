import Foundation
import CoreGraphics

/// Output resolution presets. On a Retina display, 720p/1080p/1440p are below
/// the screen's native pixel density and will look softer than what you see;
/// `native` exports at the display's own resolution (sharpest, larger files).
enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"
    case native = "Native"

    var id: String { rawValue }

    var title: String {
        self == .native ? "Native (sharpest)" : rawValue
    }

    /// Fixed export height in pixels, or nil to keep the captured native height.
    var exportHeight: Int? {
        switch self {
        case .p720:   return 720
        case .p1080:  return 1080
        case .p1440:  return 1440
        case .native: return nil
        }
    }

    /// H.264 intermediate bitrate (bits/sec) for the WEBCAM stream (a small
    /// circular crop — modest bitrate is plenty). The SCREEN intermediate uses a
    /// higher, resolution-derived bitrate computed in ScreenRecorder.
    var cameraBitrate: Int { 8_000_000 }
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
