import SwiftUI
import AVFoundation

/// Projects library: create a tutorial project from an existing recording, then
/// open it in the editor. Navigation is by project id (avoids Hashable on Project).
struct ProjectsView: View {
    @StateObject private var model = ProjectsViewModel()
    @State private var showNew = false
    @State private var renaming: Project?
    @State private var renameText = ""

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: Theme.Space.lg)]

    var body: some View {
        NavigationStack {
            Group {
                if model.projects.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.lg) {
                            ForEach(model.projects) { project in
                                NavigationLink(value: project.id) {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Rename…") { renaming = project; renameText = project.name }
                                    Button("Delete", role: .destructive) { model.delete(project) }
                                }
                            }
                        }
                        .padding(Theme.Space.xl)
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem {
                    Button { showNew = true } label: { Label("New Project", systemImage: "plus") }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let project = model.projects.first(where: { $0.id == id }) {
                    ProjectEditorView(project: project)
                } else {
                    Text("Project not found").foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .onAppear { model.refresh() }
        .sheet(isPresented: $showNew) { NewProjectSheet(model: model) }
        .alert("Rename Project", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { if let p = renaming { model.rename(p, to: renameText) }; renaming = nil }
        }
        .alert("Couldn’t create project", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 44)).foregroundStyle(Theme.textSecondary)
            Text("No projects yet").font(.headline)
            Text("Create a project from one of your recordings to start adding narration.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button { showNew = true } label: { Label("New Project", systemImage: "plus") }
                .buttonStyle(.borderedProminent).tint(Theme.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}

// MARK: - Card

struct ProjectCard: View {
    let project: Project
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Theme.primaryTint)
                    Image(systemName: "film.stack").font(.title2).foregroundStyle(Theme.primary)
                }
            }
            .aspectRatio(16.0/9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.separator.opacity(0.5)))

            Text(project.name).font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary).lineLimit(1)
            HStack(spacing: 6) {
                Text(Formatters.duration(project.baseDuration))
                Text("·")
                Text("\(project.clips.count) clip\(project.clips.count == 1 ? "" : "s")")
            }
            .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .task { thumbnail = await loadThumb() }
    }

    private func loadThumb() async -> NSImage? {
        guard let url = StorageManager.shared.projectURL(project, fileName: project.baseFileName) else { return nil }
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 270)
        let t = CMTime(seconds: 1, preferredTimescale: 600)
        guard let cg = try? await gen.image(at: t).image else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}

// MARK: - New project sheet

struct NewProjectSheet: View {
    @ObservedObject var model: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var recordings: [Recording] = []
    @State private var selected: Recording.ID?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("New Project").font(.title2.bold())

            TextField("Project name", text: $name).textFieldStyle(.roundedBorder)

            SectionLabel("Base recording")
            if recordings.isEmpty {
                Text("No recordings yet — record something first.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(recordings, selection: $selected) { rec in
                    HStack {
                        Image(systemName: "film").foregroundStyle(Theme.textSecondary)
                        Text(rec.displayName).lineLimit(1)
                        Spacer()
                        Text(Formatters.duration(rec.duration))
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .tag(rec.id)
                }
                .frame(height: 240)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent).tint(Theme.primary)
                    .disabled(selected == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 460)
        .onAppear { recordings = StorageManager.shared.loadRecordings() }
    }

    private func create() {
        guard let id = selected, let rec = recordings.first(where: { $0.id == id }) else { return }
        model.create(named: name, from: rec)
        dismiss()
    }
}
