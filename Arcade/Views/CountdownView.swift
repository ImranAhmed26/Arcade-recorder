import SwiftUI

/// Full-screen dimming overlay with a large 3 → 2 → 1 → REC countdown.
/// The webcam preview stays visible because it lives in a separate floating window.
struct CountdownView: View {
    @ObservedObject var session: RecordingSessionViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            Group {
                if session.showRecFlash {
                    Text("REC")
                        .font(.system(size: 96, weight: .heavy, design: .rounded))
                        .foregroundStyle(.red)
                } else if case .countdown(let n) = session.stage {
                    Text("\(n)")
                        .font(.system(size: 140, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .id(n)
                }
            }
            .transition(.scale.combined(with: .opacity))
            .shadow(radius: 20)
        }
        .animation(.spring(duration: 0.35), value: session.stage)
        .animation(.easeInOut, value: session.showRecFlash)
    }
}
