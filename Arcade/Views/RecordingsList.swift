import SwiftUI

/// Recent recordings list with thumbnails, metadata, and per-row actions.
struct RecordingsList: View {
    @ObservedObject var model: DashboardViewModel
    @State private var renaming: Recording?
    @State private var renameText = ""

    var body: some View {
        Group {
            if model.recordings.isEmpty {
                emptyState
            } else {
                List(model.recordings) { recording in
                    RecordingRow(recording: recording, model: model) {
                        renaming = recording
                        renameText = recording.displayName
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert("Rename Recording", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let r = renaming { model.rename(r, to: renameText) }
                renaming = nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No recordings yet")
                .font(.headline)
            Text("Your recordings will appear here after you stop one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct RecordingRow: View {
    let recording: Recording
    @ObservedObject var model: DashboardViewModel
    let onRename: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            thumb
            VStack(alignment: .leading, spacing: 3) {
                Text(recording.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(Formatters.duration(recording.duration), systemImage: "clock")
                    Text("•")
                    Text(Formatters.timestamp(recording.createdAt))
                    if recording.webcamFileName != nil {
                        Text("•")
                        Image(systemName: "person.crop.circle.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            actions
        }
        .padding(.vertical, 4)
        .task { thumbnail = await Thumbnailer.thumbnail(for: recording) }
        .contextMenu {
            Button("Play") { model.play(recording) }
            Button("Reveal in Finder") { model.reveal(recording) }
            Button("Rename…") { onRename() }
            Divider()
            Button("Delete", role: .destructive) { model.delete(recording) }
        }
    }

    private var thumb: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: "film").foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var actions: some View {
        HStack(spacing: 4) {
            iconButton("play.fill", help: "Play") { model.play(recording) }
            iconButton("folder", help: "Reveal in Finder") { model.reveal(recording) }
            iconButton("pencil", help: "Rename") { onRename() }
            iconButton("trash", help: "Delete") { model.delete(recording) }
        }
        .buttonStyle(.borderless)
    }

    private func iconButton(_ name: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name) }
            .help(help)
    }
}
