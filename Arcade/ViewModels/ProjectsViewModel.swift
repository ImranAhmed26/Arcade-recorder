import Foundation
import AppKit
import Combine

/// Backs the Projects library: load, create-from-recording, rename, delete.
@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published var errorMessage: String?

    func refresh() {
        projects = StorageManager.shared.loadProjects()
    }

    /// Create a project using an existing recording's primary file as the base.
    @discardableResult
    func create(named name: String, from recording: Recording) -> Project? {
        guard let source = StorageManager.shared.primaryURL(for: recording),
              FileManager.default.fileExists(atPath: source.path) else {
            errorMessage = "That recording's file is missing."
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? recording.displayName : trimmed
        do {
            let project = try StorageManager.shared.createProject(
                named: finalName, baseSource: source, baseDuration: recording.duration)
            refresh()
            return project
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func rename(_ project: Project, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = project
        updated.name = trimmed
        StorageManager.shared.writeProject(updated)
        refresh()
    }

    func delete(_ project: Project) {
        StorageManager.shared.deleteProject(project)
        refresh()
    }
}
