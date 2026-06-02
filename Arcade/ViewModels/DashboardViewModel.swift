import Foundation
import AppKit
import Combine

/// Backs the recordings list: loading, refreshing, and row actions.
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var recordings: [Recording] = []

    func refresh() {
        recordings = StorageManager.shared.loadRecordings()
    }

    // MARK: - Row actions

    func play(_ recording: Recording) {
        guard let url = StorageManager.shared.primaryURL(for: recording),
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ recording: Recording) {
        guard let url = StorageManager.shared.primaryURL(for: recording) else { return }
        StorageManager.shared.reveal(url)
    }

    func rename(_ recording: Recording, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        StorageManager.shared.rename(recording, to: trimmed)
        refresh()
    }

    func delete(_ recording: Recording) {
        StorageManager.shared.delete(recording)
        refresh()
    }
}
