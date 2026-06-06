import Foundation
import AVFoundation
import AppKit

/// Generates and caches poster-frame thumbnails for recordings.
enum Thumbnailer {
    /// Returns a cached thumbnail if present, otherwise generates one from the
    /// screen video's first second and caches it next to the recording.
    static func thumbnail(for recording: Recording) async -> NSImage? {
        guard let videoURL = await StorageManager.shared.primaryURL(for: recording) else { return nil }
        let thumbURL = videoURL.deletingLastPathComponent()
            .appendingPathComponent(Recording.thumbFile)

        if let data = try? Data(contentsOf: thumbURL), let image = NSImage(data: data) {
            return image
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let cg = try? await generator.image(at: time).image else { return nil }

        let image = NSImage(cgImage: cg, size: .zero)
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? jpeg.write(to: thumbURL)
        }
        return image
    }
}
