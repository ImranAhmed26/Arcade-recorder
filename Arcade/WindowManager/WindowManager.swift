import AppKit

/// Creates and tears down the floating overlay windows for a recording session.
/// Exposes the live windows so the screen recorder can exclude them from capture.
@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private init() {}

    private(set) var webcamWindow: WebcamOverlayWindow?
    private(set) var controlBarWindow: ControlBarWindow?
    private weak var mainWindow: NSWindow?

    /// The display being recorded (for Full Camera full-screen sizing).
    private var recordingScreen: NSScreen?
    /// The webcam circle's frame, saved while it's expanded full-screen so it can be restored.
    private var webcamCircleFrame: NSRect?

    /// Token for the active-Space change observer. We re-order overlays front
    /// every time the user switches Spaces so they remain visible above any
    /// fullscreen app the user switches to during a recording.
    private var spaceObserver: (any NSObjectProtocol)?

    /// All Arcade-owned windows that must be excluded from screen capture.
    var overlayWindows: [NSWindow] {
        [webcamWindow, controlBarWindow].compactMap { $0 }
    }

    func showOverlays(for session: RecordingSessionViewModel,
                      showWebcam: Bool,
                      screen: NSScreen) {
        recordingScreen = screen
        if showWebcam, webcamWindow == nil {
            let win = WebcamOverlayWindow(session: session)
            positionWebcam(win, on: screen)
            win.orderFrontRegardless()
            webcamWindow = win
        }
        if controlBarWindow == nil {
            let win = ControlBarWindow(session: session)
            positionControlBar(win, on: screen)
            win.orderFrontRegardless()
            controlBarWindow = win
        }

        // Observe every Space change and immediately re-assert the overlays
        // to the front. This is what makes them appear above fullscreen apps
        // when the user switches into a fullscreen Space after recording starts.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reorderOverlaysFront()
        }
    }

    /// Re-assert overlays to the top of the window stack.
    /// Called after the main window is hidden and on every Space change.
    func reorderOverlaysFront() {
        webcamWindow?.orderFrontRegardless()
        controlBarWindow?.orderFrontRegardless()
    }

    /// Expand the webcam overlay to fill the recorded display while Full Camera
    /// Mode is active (live preview of the full-camera segment), and restore the
    /// draggable circle when it ends. The window stays excluded from capture; the
    /// screen keeps recording underneath (ignored for that interval at export).
    func setWebcamFullScreen(_ full: Bool) {
        guard let win = webcamWindow else { return }
        if full {
            guard let screen = recordingScreen ?? win.screen ?? NSScreen.main else { return }
            if webcamCircleFrame == nil { webcamCircleFrame = win.frame }
            win.ignoresMouseEvents = true            // let clicks pass to the screen below
            win.isMovableByWindowBackground = false  // don't let a drag move the full-screen panel
            win.setFrame(screen.frame, display: true, animate: false)
            controlBarWindow?.orderFrontRegardless() // keep controls clickable on top
        } else {
            win.ignoresMouseEvents = false
            win.isMovableByWindowBackground = true
            if let frame = webcamCircleFrame {
                win.setFrame(frame, display: true, animate: false)
                webcamCircleFrame = nil
            }
        }
    }

    /// The webcam circle's position as fractions of the recorded display
    /// (top-left origin), captured while the overlay window still exists.
    func webcamPlacement(displayID: CGDirectDisplayID?) -> WebcamPlacement? {
        guard let win = webcamWindow else { return nil }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        } ?? NSScreen.main
        guard let screen, screen.frame.width > 0, screen.frame.height > 0 else { return nil }

        let s = screen.frame              // AppKit points, bottom-left origin
        // Always report the CIRCLE geometry, even while expanded full-screen for
        // Full Camera Mode, so placement/diameter stay correct.
        let w = webcamCircleFrame ?? win.frame
        let topFromTop = (s.minY + s.height) - (w.minY + w.height)
        return WebcamPlacement(
            x: (w.minX - s.minX) / s.width,
            y: topFromTop / s.height,
            diameter: w.width / s.width)
    }

    func hideOverlays() {
        // Stop observing Space changes before closing windows.
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
        webcamWindow?.orderOut(nil)
        controlBarWindow?.orderOut(nil)
        webcamWindow = nil
        controlBarWindow = nil
        recordingScreen = nil
        webcamCircleFrame = nil
        restoreMainWindow()
    }

    /// Hide the main dashboard window so it isn't captured in the recording.
    func hideMainWindow() {
        let main = NSApp.windows.first { window in
            window.isVisible
                && !(window is WebcamOverlayWindow)
                && !(window is ControlBarWindow)
                && window.styleMask.contains(.titled)
        }
        mainWindow = main
        main?.orderOut(nil)
        // After the main window is gone another app may come to foreground —
        // immediately re-assert overlays so they stay on top.
        reorderOverlaysFront()
    }

    func restoreMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow = nil
    }

    // MARK: - Positioning (always relative to the recorded display, not NSScreen.main)

    private func positionWebcam(_ window: NSWindow, on screen: NSScreen) {
        let f = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: f.minX + 40, y: f.minY + 40))
    }

    private func positionControlBar(_ window: NSWindow, on screen: NSScreen) {
        let f = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.minY + 32))
    }
}
