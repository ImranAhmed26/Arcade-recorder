import Foundation

/// Composites a recording's separate streams into a single `final.mp4` using
/// FFmpeg: the circular webcam is overlaid onto the screen at the position it
/// occupied during recording, and both audio tracks are mixed.
///
///   screen.mp4 = screen video + system audio
///   webcam.mp4 = circular webcam video + microphone audio
///   →  final.mp4
enum MergeService {
    enum MergeError: LocalizedError {
        case ffmpegNotFound
        case probeFailed
        case ffmpegFailed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "FFmpeg was not found. Install it with `brew install ffmpeg`."
            case .probeFailed:
                return "Could not read the recorded video."
            case .ffmpegFailed(let log):
                return "Merging failed: \(log)"
            }
        }
    }

    // MARK: - Tool discovery

    private static let searchPaths = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
    ]

    private static func tool(_ name: String) -> String? {
        for dir in searchPaths {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static var isAvailable: Bool { tool("ffmpeg") != nil }

    // MARK: - Merge

    /// Merge the recording's streams. Returns the merged file URL.
    /// Runs FFmpeg synchronously; call from a background task.
    ///
    /// `keyframes` carry the webcam circle's position at recorded timestamps so
    /// the overlay moves in the output exactly as the user dragged it.
    /// `diameter` is the circle size as a fraction of the display width.
    /// `targetHeight` = nil keeps the captured native resolution (sharpest);
    /// otherwise the screen is Lanczos-downscaled to that height. `quality` is the
    /// VideoToolbox constant-quality value (≈1–100, higher = sharper/larger) — this
    /// is used instead of an average bitrate because hardware HEVC bitrate control
    /// badly undershoots on low-complexity screen content, leaving text soft.
    static func merge(screen: URL,
                      webcam: URL?,
                      keyframes: [WebcamPositionKeyframe],
                      diameter: Double,
                      targetHeight: Int?,
                      quality: Int,
                      output: URL) throws -> URL {
        guard let ffmpeg = tool("ffmpeg") else { throw MergeError.ffmpegNotFound }

        let (capW, capH, screenHasAudio) = try probe(screen)
        let webcamInfo = webcam.flatMap { try? probe($0) }
        let webcamHasVideo = (webcam != nil) && (webcamInfo?.width ?? 0) > 0
        let webcamHasAudio = webcamInfo?.hasAudio ?? false

        // Downscale to the chosen tier height with Lanczos for crisp text; never
        // upscale. nil targetHeight (Native) keeps the captured resolution.
        var screenW = capW, screenH = capH
        if let targetHeight, capH > targetHeight {
            screenH = targetHeight
            screenW = Int((Double(capW) * Double(targetHeight) / Double(capH)).rounded())
            if screenW % 2 != 0 { screenW += 1 }
        }

        var args = ["-y", "-v", "error", "-i", screen.path]
        if webcam != nil { args += ["-i", webcam!.path] }

        var filters: [String] = []
        var screenLabel = "0:v"
        if screenW != capW || screenH != capH {
            // Lanczos downscale, then a light luma-only unsharp to recover the
            // text/UI edge crispness lost when shrinking Retina content to the
            // chosen tier (downscaling is the main softness source — chroma is
            // left untouched to avoid colour halos).
            filters.append("[0:v]scale=\(screenW):\(screenH):flags=lanczos,unsharp=3:3:0.7:3:3:0.0[scr]")
            screenLabel = "[scr]"
        }
        var videoLabel = screenLabel

        if webcamHasVideo, !keyframes.isEmpty {
            let d = max(2, Int((diameter * Double(screenW)).rounded()))

            // Build time-varying x/y expressions from position keyframes (in final px).
            let xSteps = keyframes.map { (time: $0.time, px: clamp(Int($0.x * Double(screenW)), 0, screenW - d)) }
            let ySteps = keyframes.map { (time: $0.time, px: clamp(Int($0.y * Double(screenH)), 0, screenH - d)) }
            let xExpr = stepExpr(xSteps)
            let yExpr = stepExpr(ySteps)

            // SUPERSAMPLED CIRCLE: build the alpha mask at the camera's native
            // (cropped-square) resolution using W/H-relative geometry, then
            // area-downscale to the overlay size. Masking at full res + a quality
            // downscale yields a genuinely smooth, perfectly round edge that
            // survives compression — masking at the small overlay size (the old
            // approach) produced a low-res, polygonal-looking rim.
            //
            // Geometry is expressed as fractions of the plane width `W` so it
            // works at whatever native resolution the cropped webcam happens to be.
            let kRing = 1.6 / Double(d)   // black outline ≈ 1.6 px in the final overlay
            let kAA   = 1.2 / Double(d)   // edge softness ≈ 1.2 px in the final overlay
            let dd = "sqrt((X-W/2)*(X-W/2)+(Y-H/2)*(Y-H/2))"
            let ringInner = "(W*\(0.5 - kRing))"
            let blackRing = "gte(\(dd),\(ringInner))"
            let alpha = "clip((W/2-\(dd))/(W*\(kAA)),0,1)*255"

            let geq = "geq="
                + "r='if(\(blackRing),0,r(X,Y))':"
                + "g='if(\(blackRing),0,g(X,Y))':"
                + "b='if(\(blackRing),0,b(X,Y))':"
                + "a='\(alpha)'"

            // crop to centre square → mask at native res → high-quality downscale.
            filters.append("[1:v]crop='min(iw,ih)':'min(iw,ih)',format=rgba,\(geq),scale=\(d):\(d):flags=area[cam]")
            // A filter input must be a bracketed pad label. `screenLabel` is
            // "[scr]" after a downscale but a raw "0:v" stream specifier when no
            // scaling happened (e.g. the Native tier) — bracket it for overlay.
            let screenIn = screenLabel.hasPrefix("[") ? screenLabel : "[\(screenLabel)]"
            filters.append("\(screenIn)[cam]overlay=x='\(xExpr)':y='\(yExpr)':format=auto[v]")
            videoLabel = "[v]"
        }

        // Audio: mix whatever is present.
        var audioMap: [String] = []
        switch (screenHasAudio, webcamHasAudio) {
        case (true, true):
            filters.append("[0:a][1:a]amix=inputs=2:duration=longest:normalize=0[a]")
            audioMap = ["-map", "[a]"]
        case (true, false):
            audioMap = ["-map", "0:a"]
        case (false, true):
            audioMap = ["-map", "1:a"]
        case (false, false):
            audioMap = []
        }

        if !filters.isEmpty {
            args += ["-filter_complex", filters.joined(separator: ";")]
        }
        args += ["-map", videoLabel]
        args += audioMap
        // Final output: hardware HEVC in CONSTANT-QUALITY mode. Bitrate mode
        // undershoots on static screen content (≈3 Mbps regardless of target),
        // which softens text; quality mode allocates bits where detail exists.
        args += ["-c:v", "hevc_videotoolbox",
                 "-q:v", "\(quality)",
                 "-tag:v", "hvc1",          // Apple-compatible HEVC tag for QuickTime/IINA
                 "-c:a", "aac", "-b:a", "128k",
                 "-movflags", "+faststart",
                 output.path]

        try run(ffmpeg, args)
        return output
    }

    // MARK: - Expression helpers

    /// Builds a piecewise-constant FFmpeg expression from timestamped pixel values.
    /// e.g. [(0,40),(3,800)] → "if(lt(t,3.0),40,800)"
    /// A single step returns the plain pixel value; zero steps returns "0".
    private static func stepExpr(_ steps: [(time: Double, px: Int)]) -> String {
        guard !steps.isEmpty else { return "0" }
        guard steps.count > 1 else { return String(steps[0].px) }
        var expr = String(steps.last!.px)
        for i in stride(from: steps.count - 2, through: 0, by: -1) {
            expr = "if(lt(t,\(steps[i + 1].time)),\(steps[i].px),\(expr))"
        }
        return expr
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        max(lo, min(hi, v))
    }

    // MARK: - ffprobe

    private static func probe(_ url: URL) throws -> (width: Int, height: Int, hasAudio: Bool) {
        guard let ffprobe = tool("ffprobe") else { throw MergeError.ffmpegNotFound }
        let out = try capture(ffprobe, [
            "-v", "error",
            "-show_entries", "stream=codec_type,width,height",
            "-of", "csv=p=0", url.path,
        ])
        var w = 0, h = 0, hasAudio = false
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if parts.first == "video", parts.count >= 3 {
                w = Int(parts[1]) ?? w
                h = Int(parts[2]) ?? h
            } else if parts.first == "audio" {
                hasAudio = true
            }
        }
        return (w, h, hasAudio)
    }

    // MARK: - Process helpers

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let log = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw MergeError.ffmpegFailed(log.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ""
    }

    private static func capture(_ launchPath: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        try process.run()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MergeError.probeFailed }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
