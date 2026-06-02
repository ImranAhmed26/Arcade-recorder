import Foundation
import AVFoundation
import AppKit

/// Enumerates available displays, cameras, and microphones for the config UI.
/// Display enumeration uses NSScreen (no screen-recording permission needed).
/// Camera/mic enumeration uses AVFoundation (triggers camera/mic TCC, not screen).
@MainActor
final class DeviceManager: ObservableObject {
    @Published var displays: [DisplayOption] = []
    @Published var cameras: [CameraOption] = []
    @Published var microphones: [MicrophoneOption] = []

    func refreshAll() {
        refreshDisplays()
        refreshCameras()
        refreshMicrophones()
    }

    // MARK: - Displays (NSScreen — no screen-recording permission required)

    func refreshDisplays() {
        var options: [DisplayOption] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let id = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            let res = screen.deviceDescription[.size] as? NSSize ?? screen.frame.size
            let w = Int(res.width * screen.backingScaleFactor)
            let h = Int(res.height * screen.backingScaleFactor)
            let label = index == 0
                ? "Main Display — \(w)×\(h)"
                : "Display \(index + 1) — \(w)×\(h)"
            options.append(DisplayOption(id: id, name: label))
        }
        displays = options
    }

    // MARK: - Cameras / Microphones (AVFoundation)

    func refreshCameras() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        cameras = session.devices.map { CameraOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    func refreshMicrophones() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio, position: .unspecified)
        microphones = session.devices.map { MicrophoneOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    // MARK: - Lookups

    func camera(for id: String?) -> AVCaptureDevice? {
        guard let id else { return nil }
        return AVCaptureDevice(uniqueID: id)
    }

    func microphone(for id: String?) -> AVCaptureDevice? {
        guard let id else { return nil }
        return AVCaptureDevice(uniqueID: id)
    }
}
