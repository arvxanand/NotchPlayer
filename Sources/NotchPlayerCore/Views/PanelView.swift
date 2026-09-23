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
    /// Shuffle and repeat, as last read.
    let modes: Modes?
    let send: (SpotifyBridge.Command) -> Void
    let setRepeat: (Modes.Repeat) -> Void

    /// Raised while the pointer is dragging the progress line, so the panel
    /// is held open. Without it the watcher collapses the panel the moment the
    /// drag leaves the drawn frame, which is easy to do and takes the thing
    /// you are dragging with it.
    let onScrubbing: (Bool) -> Void
    /// The title opens the track, the artist their page, the cover the album.
    let openLink: (SpotifyLinks.Target) -> Void

    @State private var scrub: Double?
    /// Watched for the cover's colour, which arrives with the cover.
    @ObservedObject private var memory = ArtMemory.shared
    @AppStorage(Accent.enabledKey) private var coverAccent = true

    public init(geometry: NotchGeometry, track: Track, progress: Interpolator?,
                playing: Bool, controllable: Bool = true, modes: Modes? = nil,
                onScrubbing: @escaping (Bool) -> Void = { _ in },
                send: @escaping (SpotifyBridge.Command) -> Void = { _ in },
                setRepeat: @escaping (Modes.Repeat) -> Void = { _ in },
                openLink: @escaping (SpotifyLinks.Target) -> Void = { _ in }) {
        self.geometry = geometry; self.track = track; self.progress = progress
        self.playing = playing; self.controllable = controllable; self.modes = modes
        self.onScrubbing = onScrubbing; self.send = send; self.setRepeat = setRepeat
        self.openLink = openLink
    }

    public var body: some View {
        VStack(spacing: 0) {
            // The camera housing's band. `Color.clear` is greedy in both axes,
            // which is wanted horizontally and pinned vertically.
            Color.clear.frame(height: geometry.notchExclusionTop)

            HStack(alignment: .top, spacing: Self.gap) {
                // Plain buttons, not tap gestures: a `Button` acts on mouse-up,
                // which is the one click this never-key panel is guaranteed to
                // get (`docs/TRAPS.md` #37). No hover underline, because
                // `.onHover` never fires here (#40).
                Button { openLink(.album) } label: {
                    ArtworkView(url: track.artworkURL, side: Self.artSide, corner: Self.artCorner)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the album in Spotify")
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
                    TransportRow(playing: playing, modes: modes, send: send, setRepeat: setRepeat)
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
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Button { openLink(.track) } label: {
                        changing(Text(track.name)
                            .font(Type.title())
                            .foregroundStyle(Palette.primary)
                            // One line, truncated: a title that wraps changes the panel's
                            // height, and a panel that resizes per track is a panel that
                            // jumps every time the song does.
                            .lineLimit(1)
                            .truncationMode(.tail))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the song in Spotify")
                    Button { openLink(.artist) } label: {
                        changing(Text(track.artist)
                            .font(Type.label())
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the artist in Spotify")
                    .padding(.top, 2)
                }
                if Self.showsPlus(track) {
                    // Wider than the + target's overhang, so the title's own
                    // button and this one never share a point (`docs/TRAPS.md` #21).
                    Spacer(minLength: Self.plusGap)
                    plus
                }
            }

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
                        accent: memory.accent(for: coverAccent ? track.artworkURL : nil).map {
                            Color(red: $0.r, green: $0.g, blue: $0.b)
                        } ?? Palette.primary,
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

    /// The title and the artist, when the song changes: the old text lifts out
    /// and fades, **then** the new one rises in. In sequence, so the two never
    /// overlap -- two half-transparent lines of text on top of each other is
    /// the thing that looks broken.
    ///
    /// 4pt of travel over ~0.2s is about 0.3pt a frame; matchnotch's rule is
    /// that past ~20 it judders. Keyed on the track id, so a re-render of the
    /// same song never animates.
    private func changing(_ text: some View) -> some View {
        ZStack(alignment: .leading) {
            // No full-width frame: the title is a button, and a short one must
            // not answer clicks in the empty space beside it.
            text
                .id(track.id)
                .transition(Self.textChange)
        }
        // Scoped to the track, not `withAnimation` (matchnotch TRAPS #52).
        .animation(.easeOut(duration: 0.2 * Motion.slow), value: track.id)
    }

    /// Where Spotify puts its own: the right end of the title row. What it
    /// does is `SpotifyPlus`'s business -- it presses Spotify's +, or opens
    /// the song -- and either way it acts on mouse-up like every button here.
    ///
    /// **Pad, shape, then give the layout back** (`docs/TRAPS.md` #41): the
    /// 44pt target is live in full while the row lays out an 18pt glyph, so
    /// the title keeps its width and the artist row keeps its place.
    private var plus: some View {
        Button { openLink(.save) } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: Self.plusGlyph, weight: .regular))
                .foregroundStyle(Palette.primary)
                .frame(width: Self.plusGlyph, height: Self.plusGlyph)
                .padding(Self.plusOverhang)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-Self.plusOverhang)
        // Centred on the title's 21pt line.
        .padding(.top, (21 - Self.plusGlyph) / 2)
        .accessibilityLabel("Save the song")
    }

    /// Only a real track can be saved. A local file, an episode or an ad has
    /// no `spotify:track:` id, and a + that could do nothing is not drawn.
    public nonisolated static func showsPlus(_ track: Track) -> Bool {
        SpotifyLinks.pageURL(for: track.id) != nil
    }

    static var textChange: AnyTransition {
        let lift: CGFloat = Motion.reduced ? 0 : 4, s = Motion.slow
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: lift))
                .animation(.easeOut(duration: 0.22 * s).delay(0.12 * s)),
            removal: .opacity.combined(with: .offset(y: -lift))
                .animation(.easeIn(duration: 0.12 * s)))
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
    static let plusGlyph: CGFloat = 18
    /// How far the + target reaches past its glyph on each side: 44pt in all.
    static let plusOverhang: CGFloat = (NotchGeometry.minimumHitHeight - plusGlyph) / 2
    static let plusGap: CGFloat = plusOverhang + 4
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

    /// The + target, same coordinates, derived from the same constants. Its
    /// glyph's right edge is the text column's, like the progress line's.
    public static func plusRect(_ geometry: NotchGeometry) -> CGRect {
        let side = NotchGeometry.minimumHitHeight
        let glyphRight = geometry.screenFrame.midX + geometry.collapsedWidth / 2 - inset
        let glyphTop = geometry.notchExclusionTop + topGap + (21 - plusGlyph) / 2
        return CGRect(x: glyphRight - plusGlyph - plusOverhang, y: glyphTop - plusOverhang,
                      width: side, height: side)
    }

    public static func transportRects(_ geometry: NotchGeometry)
        -> [(name: String, rect: CGRect)] {
        let side = NotchGeometry.minimumHitHeight
        let top = geometry.notchExclusionTop + topGap + artSide + transportGap
        let centreX = geometry.screenFrame.midX
        let inner = TransportRow.centreToCentre, outer = TransportRow.outerCentreToCentre
        let mode = TransportRow.modeWidth
        let targets: [(String, CGFloat, CGFloat)] = [
            ("shuffle", -inner - outer, mode), ("previous", -inner, side),
            ("playpause", 0, side), ("next", inner, side), ("repeat", inner + outer, mode)]
        return targets.map { name, offset, width in
            (name, CGRect(x: centreX + offset - width / 2, y: top, width: width, height: side))
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
