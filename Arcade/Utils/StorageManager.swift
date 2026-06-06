import Foundation
import AppKit

/// Owns the persistent save directory and reads/writes recordings on disk.
/// The chosen directory survives launches via a security-scoped bookmark.
@MainActor
final class StorageManager: ObservableObject {
    static let shared = StorageManager()

    private let bookmarkKey = "arcade.saveDirectory.bookmark"
    private let defaultsKey = "arcade.saveDirectory.path"

    /// Currently active save directory, with security scope started (if needed).
    private(set) var saveDirectory: URL?

    private init() {
        resolveBookmark()
    }

    // MARK: - Directory selection

    /// Resolve the stored bookmark into a usable, scope-started URL.
    func resolveBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            // Fall back to a sensible default the first time.
            saveDirectory = defaultDirectory()
            return
        }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale) {
            _ = url.startAccessingSecurityScopedResource()
            saveDirectory = url
            if stale { persistBookmark(for: url) }
        } else {
            saveDirectory = defaultDirectory()
        }
    }

    /// Store a newly picked directory.
    func setSaveDirectory(_ url: URL) {
        saveDirectory?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        saveDirectory = url
        persistBookmark(for: url)
    }

    private func persistBookmark(for url: URL) {
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            UserDefaults.standard.set(url.path, forKey: defaultsKey)
        }
    }

    private func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("Arcade", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Recording folders

    /// Create (if needed) and return the folder for a given recording id.
    func folder(for id: UUID) throws -> URL {
        guard let root = saveDirectory else {
            throw NSError(domain: "Arcade", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No save directory selected."])
        }
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// URL of a file inside a recording's folder.
    func url(for recording: Recording, fileName: String) -> URL? {
        saveDirectory?
            .appendingPathComponent(recording.folderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// The file to play / thumbnail: merged output if present, else raw screen.
    func primaryURL(for recording: Recording) -> URL? {
        url(for: recording, fileName: recording.primaryFileName)
    }

    // MARK: - Metadata persistence

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func writeMeta(_ recording: Recording) {
        guard let folder = try? folder(for: recording.id) else { return }
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(recording) {
            try? data.write(to: folder.appendingPathComponent(Recording.metaFile))
        }
    }

    /// Load all recordings whose folder still contains a readable meta.json and
    /// a screen file. Missing/moved files are skipped gracefully. Newest first.
    func loadRecordings() -> [Recording] {
        guard let root = saveDirectory,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil) else { return [] }

        var result: [Recording] = []
        for folder in entries where folder.hasDirectoryPath {
            let metaURL = folder.appendingPathComponent(Recording.metaFile)
            guard let data = try? Data(contentsOf: metaURL),
                  let recording = try? decoder.decode(Recording.self, from: data) else { continue }
            let primary = folder.appendingPathComponent(recording.primaryFileName)
            guard FileManager.default.fileExists(atPath: primary.path) else { continue }
            result.append(recording)
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    func delete(_ recording: Recording) {
        guard let root = saveDirectory else { return }
        let folder = root.appendingPathComponent(recording.folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    func rename(_ recording: Recording, to newName: String) {
        var updated = recording
        updated.displayName = newName
        writeMeta(updated)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Open the active save directory in Finder.
    func revealSaveDirectory() {
        if let dir = saveDirectory {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
        }
    }

    // MARK: - Projects (tutorial editor)

    /// `<saveDir>/Projects` — kept in its own subfolder so it never collides with
    /// recording folders (loadRecordings ignores it: no Recording meta inside).
    func projectsRoot() throws -> URL {
        guard let root = saveDirectory else {
            throw NSError(domain: "Arcade", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No save directory selected."])
        }
        let dir = root.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func projectFolder(_ id: UUID) throws -> URL {
        let dir = try projectsRoot().appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func projectURL(_ project: Project, fileName: String) -> URL? {
        (try? projectsRoot())?
            .appendingPathComponent(project.folderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    func writeProject(_ project: Project) {
        guard let folder = try? projectFolder(project.id) else { return }
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(project) {
            try? data.write(to: folder.appendingPathComponent(Project.metaFile))
        }
    }

    /// Projects with a readable project.json and an existing base file. Newest first.
    func loadProjects() -> [Project] {
        guard let root = try? projectsRoot(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil) else { return [] }
        var result: [Project] = []
        for folder in entries where folder.hasDirectoryPath {
            let metaURL = folder.appendingPathComponent(Project.metaFile)
            guard let data = try? Data(contentsOf: metaURL),
                  let project = try? decoder.decode(Project.self, from: data) else { continue }
            let base = folder.appendingPathComponent(project.baseFileName)
            guard FileManager.default.fileExists(atPath: base.path) else { continue }
            result.append(project)
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    func deleteProject(_ project: Project) {
        guard let folder = try? projectsRoot()
            .appendingPathComponent(project.folderName, isDirectory: true) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Create a project by copying a source video in as the self-contained base asset.
    func createProject(named name: String, baseSource: URL, baseDuration: Double) throws -> Project {
        let project = Project(name: name, baseDuration: baseDuration)
        let folder = try projectFolder(project.id)
        let baseDest = folder.appendingPathComponent(Project.baseFile)
        try? FileManager.default.removeItem(at: baseDest)
        try FileManager.default.copyItem(at: baseSource, to: baseDest)
        writeProject(project)
        return project
    }
}
