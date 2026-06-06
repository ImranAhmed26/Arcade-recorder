import SwiftUI
import AVKit

/// Project editor. Phase A: base playback + project summary. Narration recording,
/// the timeline, base trimming, and export land in later phases.
struct ProjectEditorView: View {
    @StateObject private var vm: ProjectEditorViewModel

    init(project: Project) {
        _vm = StateObject(wrappedValue: ProjectEditorViewModel(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: vm.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)

            Divider()

            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.project.name).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("\(Formatters.duration(vm.project.baseDuration)) · \(vm.project.clips.count) narration clip\(vm.project.clips.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                // Placeholders for upcoming phases.
                Button { } label: { Label("Add Narration", systemImage: "mic.badge.plus") }
                    .disabled(true)
                    .help("Coming next: record webcam + voice narration clips")
                Button { } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .disabled(true)
            }
            .padding(Theme.Space.lg)
            .background(Theme.windowBackground)
        }
        .navigationTitle(vm.project.name)
        .onDisappear { vm.player.pause() }
    }
}
