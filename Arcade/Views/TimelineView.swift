import SwiftUI

// MARK: - Timeline

/// Lightweight, non-NLE timeline strip for the project editor.
///
/// Layout (top-to-bottom):
///   ┌────────────────────────────────────────────┐
///   │  Time ruler (with tick marks + labels)      │
///   │  Base track (grey fill = full base range)   │
///   │  Narration lane (coloured clip blocks)      │
///   └────────────────────────────────────────────┘
///
/// Interactions:
///   • Click ruler          → seek playhead
///   • Drag clip body       → move (change timelineStart)
///   • Drag clip left edge  → trim in (adjusts trimIn + duration)
///   • Drag clip right edge → trim out (adjusts duration)
///   • Tap clip             → select (shows delete button)
///   • Delete key / button  → delete selected clip
struct TimelineView: View {
    /// Project (two-way): clip edits write back directly.
    @Binding var project: Project
    /// Current playhead in seconds (read-only from AVPlayer observer).
    @Binding var playhead: Double
    /// Called when the user scrubs so the editor can seek the AVPlayer.
    var onSeek: (Double) -> Void
    /// Called after any clip mutation so the editor can persist.
    var onChanged: () -> Void
    var onDeleteClip: (NarrationClip) -> Void

    // MARK: Layout constants
    private let rulerHeight: CGFloat = 24
    private let baseTrackH: CGFloat = 20
    private let narrationLaneH: CGFloat = 44
    private let handleW: CGFloat = 10

    var totalHeight: CGFloat { rulerHeight + baseTrackH + narrationLaneH + 8 }

    @State private var selectedID: UUID?
    /// Points-per-second zoom.  The user cannot zoom in Phase C; fixed at a
    /// comfortable default scaled to the container width via `GeometryReader`.
    @State private var pps: CGFloat = 80

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                // Derive pps so the full base fills ~90% of the visible width.
                let computedPPS: CGFloat = project.baseDuration > 0
                    ? geo.size.width * 0.9 / CGFloat(project.baseDuration)
                    : 80
                let usedPPS = computedPPS
                let totalW = CGFloat(project.baseDuration) * usedPPS

                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // 1. Ruler
                        ruler(pps: usedPPS, width: max(totalW, geo.size.width))
                            .frame(height: rulerHeight)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        // 2. Base track
                        baseTrack(pps: usedPPS)
                            .offset(y: rulerHeight + 2)

                        // 3. Narration lane
                        narrationLane(pps: usedPPS)
                            .offset(y: rulerHeight + baseTrackH + 4)

                        // 4. Playhead
                        playheadLine(pps: usedPPS)
                    }
                    .frame(width: max(totalW + 60, geo.size.width),
                           height: totalHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let t = max(0, Double(v.location.x / usedPPS))
                                onSeek(min(t, project.baseDuration))
                            }
                    )
                }
                .onAppear { pps = usedPPS }
                .onChange(of: geo.size.width) { _, w in
                    pps = project.baseDuration > 0 ? w * 0.9 / CGFloat(project.baseDuration) : 80
                }
            }
        }
        .frame(height: totalHeight)
    }

    // MARK: - Ruler

    @ViewBuilder
    private func ruler(pps: CGFloat, width: CGFloat) -> some View {
        Canvas { ctx, size in
            let step = tickStep(pps: pps)
            var t = 0.0
            while t <= project.baseDuration + step {
                let x = CGFloat(t) * pps
                let major = (t.truncatingRemainder(dividingBy: step * 5) < 0.001)
                let tickH: CGFloat = major ? 10 : 6
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: size.height - tickH))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }, with: .color(Theme.textSecondary.opacity(0.5)), lineWidth: 1)
                if major {
                    let label = Formatters.duration(t)
                    ctx.draw(Text(label).font(.system(size: 9)).foregroundStyle(Theme.textSecondary),
                             at: CGPoint(x: x, y: size.height - 14), anchor: .bottomLeading)
                }
                t += step
            }
        }
    }

    private func tickStep(pps: CGFloat) -> Double {
        // Choose a tick interval so labels don't crowd.
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 30, 60]
        return candidates.first { CGFloat($0) * pps >= 36 } ?? 60
    }

    // MARK: - Base track

    @ViewBuilder
    private func baseTrack(pps: CGFloat) -> some View {
        let w = CGFloat(project.baseDuration) * pps
        RoundedRectangle(cornerRadius: 4)
            .fill(Theme.separator.opacity(0.35))
            .frame(width: w, height: baseTrackH)
    }

    // MARK: - Narration lane

    @ViewBuilder
    private func narrationLane(pps: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach($project.clips) { $clip in
                clipBlock(clip: $clip, pps: pps)
            }
        }
        .frame(height: narrationLaneH)
    }

    // MARK: - Clip block

    @ViewBuilder
    private func clipBlock(clip: Binding<NarrationClip>, pps: CGFloat) -> some View {
        let c = clip.wrappedValue
        let x = CGFloat(c.timelineStart) * pps
        let w = max(handleW * 2 + 4, CGFloat(c.duration) * pps)
        let isSelected = selectedID == c.id

        ZStack(alignment: .leading) {
            // Body fill
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.primary.opacity(isSelected ? 0.85 : 0.6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Theme.primary : .clear, lineWidth: 2))

            HStack(spacing: 0) {
                // Left trim handle
                trimHandle()
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                let delta = Double(v.translation.width / pps)
                                let newTrimIn = max(0, c.trimIn + delta)
                                let newDur    = max(0.5, c.duration - delta)
                                let newStart  = max(0, c.timelineStart + delta)
                                clip.wrappedValue.trimIn       = newTrimIn
                                clip.wrappedValue.duration     = newDur
                                clip.wrappedValue.timelineStart = newStart
                            }
                            .onEnded { _ in onChanged() }
                    )

                Spacer()

                // Right trim handle
                trimHandle()
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                let newDur = max(0.5, c.duration + Double(v.translation.width / pps))
                                clip.wrappedValue.duration = newDur
                            }
                            .onEnded { _ in onChanged() }
                    )
            }
        }
        .frame(width: w, height: narrationLaneH - 8)
        .offset(x: x, y: 4)
        // Tap to select
        .onTapGesture { selectedID = (selectedID == c.id) ? nil : c.id }
        // Body drag → move
        .gesture(
            DragGesture()
                .onChanged { v in
                    let newStart = max(0, c.timelineStart + Double(v.translation.width / pps))
                    clip.wrappedValue.timelineStart = min(newStart, project.baseDuration - c.duration)
                }
                .onEnded { _ in onChanged() }
        )
        // Tooltip showing timing
        .help("\(Formatters.duration(c.timelineStart)) – \(Formatters.duration(c.timelineEnd))")
        // Delete selected clip with the Delete key
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Button {
                    onDeleteClip(c)
                    selectedID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white)
                        .background(Circle().fill(Theme.record))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
    }

    @ViewBuilder
    private func trimHandle() -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.white.opacity(0.5))
            .frame(width: handleW, height: narrationLaneH * 0.5)
            .padding(.horizontal, 2)
    }

    // MARK: - Playhead

    @ViewBuilder
    private func playheadLine(pps: CGFloat) -> some View {
        let x = CGFloat(playhead) * pps
        ZStack(alignment: .top) {
            // Line
            Rectangle()
                .fill(Theme.record)
                .frame(width: 1.5, height: totalHeight)
                .offset(x: x)
            // Thumb
            Circle()
                .fill(Theme.record)
                .frame(width: 10, height: 10)
                .offset(x: x - 4.25, y: 0)
        }
        .allowsHitTesting(false)
    }
}
