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
    static func merge(screen: URL,
                      webcam: URL?,
                      keyframes: [WebcamPositionKeyframe],
                      diameter: Double,
                      output: URL) throws -> URL {
        guard let ffmpeg = tool("ffmpeg") else { throw MergeError.ffmpegNotFound }

        let (screenW, screenH, screenHasAudio) = try probe(screen)
        let webcamInfo = webcam.flatMap { try? probe($0) }
        let webcamHasVideo = (webcam != nil) && (webcamInfo?.width ?? 0) > 0
        let webcamHasAudio = webcamInfo?.hasAudio ?? false

        var args = ["-y", "-v", "error", "-i", screen.path]
        if webcam != nil { args += ["-i", webcam!.path] }

        var filters: [String] = []
        var videoLabel = "0:v"

        if webcamHasVideo, !keyframes.isEmpty {
            let d = max(2, Int((diameter * Double(screenW)).rounded()))

            // Build time-varying x/y expressions from position keyframes.
            let xSteps = keyframes.map { (time: $0.time, px: clamp(Int($0.x * Double(screenW)), 0, screenW - d)) }
            let ySteps = keyframes.map { (time: $0.time, px: clamp(Int($0.y * Double(screenH)), 0, screenH - d)) }
            let xExpr = stepExpr(xSteps)
            let yExpr = stepExpr(ySteps)

            let r = Double(d) / 2.0
            let aa = 1.3                                   // edge softness (px) → anti-aliased rim
            let ringW = max(1.5, Double(d) * 0.012)        // thin black outline
            // Actual (not squared) distance from the circle centre.
            let dd = "sqrt((X-\(r))*(X-\(r))+(Y-\(r))*(Y-\(r)))"
            // Color: thin black ring near the edge, original pixel inside.
            let blackRing = "gte(\(dd),\(r - ringW))"
            // Alpha: smooth ramp from opaque to transparent across `aa` px at the
            // rim instead of a hard 1/0 cutoff — removes the jagged circle edge.
            let alpha = "clip((\(r)-\(dd))/\(aa),0,1)*255"

            let geq = "geq="
                + "r='if(\(blackRing),0,r(X,Y))':"
                + "g='if(\(blackRing),0,g(X,Y))':"
                + "b='if(\(blackRing),0,b(X,Y))':"
                + "a='\(alpha)'"

            filters.append("[1:v]crop='min(iw,ih)':'min(iw,ih)',scale=\(d):\(d),format=rgba,\(geq)[cam]")
            filters.append("[0:v][cam]overlay=x='\(xExpr)':y='\(yExpr)':format=auto[v]")
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
        // Final output: HEVC via hardware VideoToolbox at 5 Mbps (~37 MB/min ceiling).
        // HEVC at 5 Mbps delivers significantly better visual quality than H.264
        // at 10 Mbps for screen content (text, UI, code) and compresses motion
        // (YT video, animations) much more efficiently.
        args += ["-c:v", "hevc_videotoolbox", "-b:v", "5M",
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
