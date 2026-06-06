import Foundation
import AVKit
import Combine

/// Drives a single project's editor. Phase A: base playback only. Narration
/// recording, timeline editing, base trimming, and export arrive in later phases.
@MainActor
final class ProjectEditorViewModel: ObservableObject {
    @Published var project: Project
    let player: AVPlayer

    init(project: Project) {
        self.project = project
        if let url = StorageManager.shared.projectURL(project, fileName: project.baseFileName) {
            player = AVPlayer(url: url)
        } else {
            player = AVPlayer()
        }
    }

    func save() {
        StorageManager.shared.writeProject(project)
    }
}
