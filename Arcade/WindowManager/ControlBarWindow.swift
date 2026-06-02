import AppKit
import SwiftUI

/// Floating, draggable control bar.
///
/// An `NSPanel` with `.nonactivatingPanel` so it floats over other apps'
/// full-screen spaces and its buttons can be clicked without yanking the user
/// out of the app they're recording. Excluded from capture via `sharingType = .none`.
final class ControlBarWindow: NSPanel {
    init(session: RecordingSessionViewModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true            // only key when a control needs it
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        sharingType = .none
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: ControlBarView(session: session))
        hosting.frame = contentLayoutRect
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
