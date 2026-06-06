import Foundation
import ScreenCaptureKit

/// Lightweight, display-friendly descriptors for the devices the user can pick.
/// These wrap the underlying SCKit / AVFoundation objects by stable identifier.

struct DisplayOption: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
}

struct CameraOption: Identifiable, Hashable {
    let id: String        // AVCaptureDevice.uniqueID
    let name: String
}

struct MicrophoneOption: Identifiable, Hashable {
    let id: String        // AVCaptureDevice.uniqueID
    let name: String
}
