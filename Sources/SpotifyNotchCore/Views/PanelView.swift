import SwiftUI

/// The expanded panel: larger cover, track and artist, progress.
///
/// Everything legible sits **below** the menu-bar line. The top 37pt is left
/// empty black because that band is behind the camera housing, which is
/// physical -- so the footprint check passes in the expanded state by
/// construction rather than by luck.
public struct PanelView: View {
    let geometry: NotchGeometry
    let track: Track
    /// Nil while nothing is playing; the panel then shows a static bar.
    let progress: Interpolator?
    let playing: Bool
    /// False when Apple Events are refused. The track still arrives over the
    /// notification, so the panel is fully readable -- it is the buttons that
    /// cannot work, and saying so is better than three controls that swallow
    /// every press.
    let controllable: Bool
    let send: (SpotifyBridge.Command) -> Void

    /// Raised while the pointer is dragging the progress line, so the panel
    /// is held open. Without it the watcher collapses the panel the moment the
    /// drag leaves the drawn frame, which is easy to do and takes the thing
    /// you are dragging with it.
    let onScrubbing: (Bool) -> Void

    @State private var scrub: Double?

    public init(geometry: NotchGeometry, track: Track, progress: Interpolator?,
                playing: Bool, controllable: Bool = true,
                onScrubbing: @escaping (Bool) -> Void = { _ in },
                send: @escaping (SpotifyBridge.Command) -> Void = { _ in }) {
        self.geometry = geometry; self.track = track; self.progress = progress
        self.playing = playing; self.controllable = controllable
        self.onScrubbing = onScrubbing; self.send = send
    }

    public var body: some View {
        VStack(spacing: 0) {
            // The camera housing's band. `Color.clear` is greedy in both axes,
            // which is wanted horizontally and pinned vertically.
            Color.clear.frame(height: geometry.notchExclusionTop)

            HStack(alignment: .top, spacing: Self.gap) {
                ArtworkView(url: track.artworkURL, side: Self.artSide, corner: Self.artCorner)
                details
            }
            .padding(.horizontal, Self.inset)
            .padding(.top, Self.topGap)

            // Centred on the panel, not on the text column: it sits below both
            // the cover and the text, so the panel's own centre line is what
            // the eye measures it against.
            //
            // The note takes the row's exact height, so the panel is one size
            // in every state -- one `panelHeight`, one set of expected bounds
            // in the footprint check, and no second animation to tune.
            Group {
                if controllable {
                    TransportRow(playing: playing, send: send)
                } else {
                    PermissionNote().padding(.horizontal, Self.inset)
                }
            }
            .padding(.top, Self.transportGap)

            Spacer(minLength: 0)
        }
        .frame(width: geometry.collapsedWidth, height: NotchGeometry.panelHeight)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(track.name)
                .font(Type.title())
                .foregroundStyle(Palette.primary)
                // One line, truncated: a title that wraps changes the panel's
                // height, and a panel that resizes per track is a panel that
                // jumps every time the song does.
                .lineLimit(1)
                .truncationMode(.tail)
            Text(track.artist)
                .font(Type.label())
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 2)

            Spacer(minLength: 0)

            // **The clock has to be published by something that ticks.** A
            // value worked out inside a body only updates when something else
            // invalidates the view, and once a track is playing nothing else
            // does -- the notification is silent until the state changes. So
            // the progress would freeze at whatever it was when the panel
            // opened (matchnotch TRAPS #14).
            //
            // TimelineView rather than a `Timer.publish` in an initialiser,
            // which dies when the parent re-renders (#6). 1Hz because that is
            // how often the smallest thing on screen -- the seconds digit --
            // actually changes (#66).
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                // While a drag is in flight the finger is the truth, not the
                // clock: the times count with the knob, which is the feedback
                // that makes a 280pt bar precise enough to land on a verse.
                let played = progress?.position(at: .now, duration: track.duration) ?? 0
                let position = scrub.map { $0 * track.duration } ?? played
                VStack(spacing: 4) {
                    ProgressLine(
                        fraction: track.duration > 0 ? position / track.duration : 0,
                        onScrub: seekable ? { scrub = $0; onScrubbing(true) } : nil,
                        onCommit: seekable ? { commit($0) } : nil)
                    HStack(spacing: 0) {
                        Text(Clock.mmss(position))
                        Spacer(minLength: 8)
                        Text(Clock.remaining(position: position, duration: track.duration))
                    }
                    .font(Type.clock())
                    .foregroundStyle(Palette.secondary)
                }
            }
        }
        .frame(height: Self.artSide, alignment: .top)
    }

    /// A track of zero length has no position to seek to, and a refused
    /// Automation permission means the write would fail -- in both cases the
    /// line draws, and does not pretend to be a control.
    private var seekable: Bool { controllable && track.duration > 0 }

    private func commit(_ fraction: Double) {
        // Send before clearing, so the service has already taken the new
        // position as true by the time the view stops drawing the drag. The
        // other order shows one frame of the old position.
        send(.seek(fraction * track.duration))
        scrub = nil
        onScrubbing(false)
    }

    // MARK: - Metrics

    public static let artSide: CGFloat = 72
    /// 8 on 72 is about a ninth. The peek's cover takes a fifth because a
    /// small square needs proportionally more curve to read as rounded at
    /// all; a large one at the same ratio reads as a blob.
    public static let artCorner: CGFloat = 8
    public static let inset: CGFloat = 16
    public static let gap: CGFloat = 14
    public static let topGap: CGFloat = 14
    /// 8 and 10, not 12 and 14, and not 5 and 7.
    ///
    /// Three spacings were rendered and measured: the gap from the times to
    /// the glyph tops, and from the glyph bottoms to the panel edge, come out
    /// 23/25, 19/21 and 16/18. All three are balanced, so the only question is
    /// absolute tightness -- and the text block above has a ~20pt gap of its
    /// own between the artist and the progress line. 19/21 matches that
    /// rhythm; 16 reads as cramped against a block spaced more loosely than
    /// itself, and 23 reads as a separate zone.
    public static let transportGap: CGFloat = 8
    public static let bottomGap: CGFloat = 10

    /// Where the transport targets land on screen, top-left origin -- what
    /// `CGWarpMouseCursorPosition` and `screencapture -R` want.
    ///
    /// **This duplicates what the HStack does, and that is the point.** It is
    /// not used for layout; it is used by `tools/hit_probe.sh` to aim real
    /// clicks. If the arithmetic here and SwiftUI's layout disagree, the probe
    /// clicks empty space and reports no effect -- so the duplication checks
    /// itself rather than drifting silently, which is the failure mode when
    /// arithmetic quietly replaces a layout guide.
    /// The draggable band of the progress line, in the same top-left screen
    /// coordinates as `transportRects`, so a probe can put a real pointer on
    /// it. Emitted by `--hit-rects`.
    ///
    /// Derived from the same constants the view lays out with rather than
    /// measured from a capture: a probe that aims at hand-copied numbers
    /// stops testing the panel the first time the panel moves.
    public static func progressRect(_ geometry: NotchGeometry) -> CGRect {
        let left = geometry.screenFrame.midX - geometry.collapsedWidth / 2 + inset + artSide + gap
        let right = geometry.screenFrame.midX + geometry.collapsedWidth / 2 - inset
        let centre = geometry.notchExclusionTop + Self.progressCentreBelowNotch
        return CGRect(x: left, y: centre - ProgressLine.hitHeight / 2,
                      width: right - left, height: ProgressLine.hitHeight)
    }

    /// How far below the notch the progress line's centre sits.
    ///
    /// **Measured off a capture, not derived.** Adding up the nominal sizes of
    /// the rows above it -- title 21, gap 2, artist 16, gap 4 -- gives 95, and
    /// the line is at **103**: SwiftUI lays text out from font metrics, which
    /// are taller than the point sizes they are named for. Eight points is
    /// most of a hit band, and a probe aimed with the derived number reported
    /// a dead control that was working.
    public static let progressCentreBelowNotch: CGFloat = 66

    public static func transportRects(_ geometry: NotchGeometry)
        -> [(name: String, rect: CGRect)] {
        let side = NotchGeometry.minimumHitHeight
        let top = geometry.notchExclusionTop + topGap + artSide + transportGap
        let centreX = geometry.screenFrame.midX
        return zip(["previous", "playpause", "next"], [-1.0, 0, 1]).map { name, offset in
            let x = centreX + CGFloat(offset) * TransportRow.centreToCentre - side / 2
            return (name, CGRect(x: x, y: top, width: side, height: side))
        }
    }

    /// The panel's height, added up rather than written down.
    ///
    /// `NotchGeometry.panelHeight` has to agree with this, and a test asserts
    /// it does -- a constant that drifts from the layout it describes is how
    /// a panel ends up with its last row clipped, or with a band of dead
    /// space that swallows clicks.
    public static func height(_ geometry: NotchGeometry) -> CGFloat {
        geometry.notchExclusionTop + topGap + artSide
            + transportGap + NotchGeometry.minimumHitHeight + bottomGap
    }

    /// What the text column gets. Derived, so a change to the cover or the
    /// insets cannot leave the two disagreeing.
    public static func detailsWidth(_ geometry: NotchGeometry) -> CGFloat {
        geometry.collapsedWidth - inset * 2 - artSide - gap
    }

    /// The fixed vertical furniture in the text column, without the flexible
    /// gap. Asserted against `artSide` by a test, because a column that
    /// overflows a fixed-height parent does not overflow visibly -- SwiftUI
    /// crushes the flexible sibling instead, and every automated check keeps
    /// agreeing all is well (matchnotch TRAPS #90).
    public static let detailsFixedHeight: CGFloat = 21 + 2 + 16 + 4 + ProgressLine.thickness + 14
}
