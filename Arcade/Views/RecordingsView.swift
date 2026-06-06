import SwiftUI

/// Recordings library: searchable responsive grid of recording cards.
struct RecordingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var model: DashboardViewModel
    @State private var search = ""
    @State private var renaming: Recording?
    @State private var renameText = ""

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: Theme.Space.lg)]

    private var filtered: [Recording] {
        guard !search.isEmpty else { return model.recordings }
        return model.recordings.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.recordings.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.lg) {
                        if let name = appState.processingRecordingName {
                            ProcessingCard(name: name)
                        }
                        ForEach(filtered) { rec in
                            RecordingCard(recording: rec, model: model) { r in
                                renaming = r; renameText = r.displayName
                            }
                        }
                    }
                    .padding(Theme.Space.xl)
                }
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

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            Text("Recordings")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .frame(width: 160)
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 6)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(Theme.separator.opacity(0.6)))

            IconButton("arrow.clockwise", help: "Refresh") { model.refresh() }
        }
        .padding(Theme.Space.xl)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "film.stack")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textSecondary)
            Text("No recordings yet").font(.headline)
            Text("Your recordings will appear here after you stop one.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Card

struct RecordingCard: View {
    let recording: Recording
    @ObservedObject var model: DashboardViewModel
    var compact: Bool = false
    var onRename: ((Recording) -> Void)?

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            thumb
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Formatters.duration(recording.duration))
                    Text("·")
                    Text(Formatters.timestamp(recording.createdAt))
                    if recording.webcamFileName != nil {
                        Image(systemName: "person.crop.circle.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            }
        }
        .task { thumbnail = await Thumbnailer.thumbnail(for: recording) }
        .contextMenu { menu }
    }

    private var thumb: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Theme.primaryTint)
                Image(systemName: "film").font(.title2).foregroundStyle(Theme.primary)
            }

            if hovering {
                Color.black.opacity(0.28)
                Button { model.play(recording) } label: {
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)

                HStack {
                    Spacer()
                    VStack {
                        Menu {
                            menu
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .padding(6)
                        Spacer()
                    }
                }
            }
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
            .strokeBorder(Theme.separator.opacity(0.5)))
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Play") { model.play(recording) }
        Button("Reveal in Finder") { model.reveal(recording) }
        if let onRename { Button("Rename…") { onRename(recording) } }
        Divider()
        Button("Delete", role: .destructive) { model.delete(recording) }
    }
}

/// Placeholder card shown while a recording is still being merged.
struct ProcessingCard: View {
    let name: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ZStack {
                Rectangle().fill(Theme.primaryTint)
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Processing…").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .aspectRatio(16.0/9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))

            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text("Merging webcam and screen…")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
