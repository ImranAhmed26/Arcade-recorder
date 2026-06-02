import AppKit
import SwiftUI

/// A borderless, circular, draggable webcam overlay.
///
/// This is an `NSPanel` (not `NSWindow`) with `.nonactivatingPanel`. That is the
/// decisive factor for appearing over OTHER apps' full-screen spaces: a regular
/// NSWindow from a Dock app will not reliably join another application's
/// full-screen Space, but a non-activating floating panel will. Excluded from
/// screen capture via `sharingType = .none`.
final class WebcamOverlayWindow: NSPanel {
    init(session: RecordingSessionViewModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above all normal/fullscreen content during a recording.
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        sharingType = .none                     // excluded from screen capture
        isMovableByWindowBackground = true       // drag the circle anywhere
        // .canJoinAllSpaces + .fullScreenAuxiliary → appear in every Space,
        // including other apps' fullscreen spaces. .stationary keeps it put
        // during Space transitions; .ignoresCycle hides it from Cmd-Tab cycling.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = false

        let hosting = NSHostingView(rootView: WebcamOverlayView(session: session))
        hosting.frame = contentLayoutRect
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
