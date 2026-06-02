import SwiftUI
import AVFoundation

/// Hosts a live `AVCaptureVideoPreviewLayer` for the circular webcam overlay.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
    }

    final class PreviewNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(previewLayer)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }
}

/// The circular webcam content shown inside the floating overlay window.
struct WebcamOverlayView: View {
    @ObservedObject var session: RecordingSessionViewModel

    var body: some View {
        ZStack {
            if session.webcamEnabled {
                CameraPreview(session: session.camera.session)
            } else {
                Color.black
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 3))
    }
}
