import Foundation
import Combine
import AppKit
import ScreenCaptureKit

/// The single source of truth for which screen / phase the app is in.
/// Flow: signIn → dashboard → countdown → recording → dashboard
enum AppPhase: Equatable {
    case signIn
    case dashboard
    case countdown
    case recording
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .signIn

    /// Shared recording configuration, edited on the dashboard and locked
    /// once a recording session begins.
    @Published var config = RecordingConfig()

    /// Device enumeration, shared by the config panel and the recording engine.
    let devices = DeviceManager()

    /// The live session, present only during countdown + recording.
    @Published var session: RecordingSessionViewModel?

    /// Bumped after a recording is saved so the dashboard list refreshes.
    @Published var recordingsRevision = 0

    /// User-facing error (e.g. screen-recording permission denied). Drives an alert.
    @Published var errorMessage: String?

    /// True while a finished recording is being merged into its final file.
    @Published var isProcessing = false

    /// Display name of the recording currently being processed, shown as a
    /// placeholder row in the recordings list while FFmpeg runs.
    @Published var processingRecordingName: String?

    /// Whether screen-recording permission has been confirmed via SCShareableContent.
    /// Checked once on dashboard appear; must be true before a recording can start.
    @Published var hasScreenPermission = false

    /// Authentication (Google OAuth + Keychain). Drives the signIn ↔ dashboard phase.
    let auth = AuthService()
    private var authCancellable: AnyCancellable?

    /// App appearance (System / Light / Dark), persisted across launches.
    @Published var themeMode: ThemeMode = .system {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "arcade.themeMode")
            applyAppearance()
        }
    }

    /// Drive the AppKit appearance directly so every view (and its semantic
    /// text/surface colors) updates immediately, not just after a re-render.
    func applyAppearance() {
        guard NSApp != nil else { return }   // safe no-op if called before launch
        switch themeMode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Check (and cache) screen-recording permission by probing SCShareableContent.
    /// This is the only place that call is made outside of the actual recorder.
    func checkScreenPermission() async {
        guard !hasScreenPermission else { return }
        if (try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) != nil {
            hasScreenPermission = true
        }
    }

    init() {
        config.loadPersisted()
        if let raw = UserDefaults.standard.string(forKey: "arcade.themeMode"),
           let mode = ThemeMode(rawValue: raw) {
            themeMode = mode
        }
        applyAppearance()

        // Drive the top-level phase from auth state: signed out → signIn,
        // signed in → leave the recording flow alone but enter the app from signIn.
        authCancellable = auth.$currentUser.sink { [weak self] user in
            guard let self else { return }
            if user == nil {
                self.phase = .signIn
            } else if self.phase == .signIn {
                self.phase = .dashboard
            }
        }
        auth.restore()   // automatic session restore on launch
    }

    func signOut() {
        auth.signOut()   // phase follows via the auth subscription
    }

    /// Begin a new recording session: lock config, show overlays, run countdown.
    func startSession() {
        // Apply the "Screen only" toggle: clear the camera for this session.
        var sessionConfig = config
        sessionConfig.cameraID = config.effectiveCameraID
        let session = RecordingSessionViewModel(config: sessionConfig)
        session.onFinish = { [weak self] saved in
            self?.endSession(saved: saved)
        }
        session.onError = { [weak self] message in
            self?.errorMessage = message
        }
        session.onProcessingStarted = { [weak self] name in
            self?.beginProcessing(recordingName: name)
        }
        session.webcamPlacementProvider = { [weak self] in
            guard let self else { return nil }
            return WindowManager.shared.webcamPlacement(displayID: self.config.displayID)
        }
        self.session = session
        phase = .countdown

        // Resolve the NSScreen for the recorded display so overlays appear on
        // the correct screen, not always NSScreen.main.
        let targetScreen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                == config.displayID
        }) ?? NSScreen.main ?? NSScreen.screens[0]

        session.startCameraPreview()
        WindowManager.shared.showOverlays(for: session,
                                          showWebcam: config.effectiveCameraID != nil,
                                          screen: targetScreen)

        let displayID = config.displayID
        session.beginCountdown { [weak self] in
            guard let self else { return }
            self.phase = .recording
            let excluded = WindowManager.shared.overlayWindows.map { $0.windowNumber }
            WindowManager.shared.hideMainWindow()
            session.startRecording(displayID: displayID, excludingWindowNumbers: excluded)
        }
    }

    /// Capture has stopped; dismiss overlays and show the dashboard while the
    /// merge runs in the background. The session stays alive until it finishes.
    private func beginProcessing(recordingName: String) {
        isProcessing = true
        processingRecordingName = recordingName
        WindowManager.shared.hideOverlays()
        phase = .dashboard
    }

    private func endSession(saved: Bool) {
        WindowManager.shared.hideOverlays()
        session = nil
        isProcessing = false
        processingRecordingName = nil
        phase = .dashboard
        if saved { recordingsRevision += 1 }
    }
}
