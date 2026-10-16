import SwiftUI

/// Everything the panel draws.
public struct RootView: View {
    let geometry: NotchGeometry
    let now: Now
    let permission: Permission
    let expanded: Bool
    let progress: Interpolator?
    /// Shuffle and repeat.
    let modes: Modes?
    /// Fixed bar values for a reproducible capture; nil animates.
    let holdBands: [Float]?
    /// `--probe`: fill the shell white so its geometry can be measured. The
    /// peek is otherwise unmeasurable -- a black shape on a dark menu bar is
    /// the same pixels as no shape, in a capture and to the eye.
    let probe: Bool
    /// Raised while the progress line is being dragged; the panel is held open
    /// for as long as it is.
    let onScrubbing: (Bool) -> Void
    /// A no-op in previews, so a capture cannot control the user's playback.
    let send: (Command) -> Void
    let setRepeat: (Modes.Repeat) -> Void
    /// The title, the artist or the cover was clicked. A no-op in previews.
    let openLink: (LinkTarget, Track) -> Void
    /// The closed peek steps aside: the menu bar is gone (full screen, #17),
    /// or the pointer is resting on a wing to reach a menu under it (#16).
    /// Opening still works -- the hover spot is where it always was -- and the
    /// open panel draws as usual.
    let concealed: Bool
    /// Whose permission state `.permissionNeeded` is about; a track carries its own.
    let source: Source
    /// Which page the open panel shows, and what the stats page counts.
    let page: Expansion.Page
    let plays: [Play]
    /// Previews only: the queue page shows this instead of reading Spotify's file.
    let queue: QueueView.Content?
    /// Nil draws the player alone: no stats button, no dots.
    let showPage: ((Expansion.Page) -> Void)?
    /// Set, the open panel shows what's new instead, until dismissed.
    let whatsNew: WhatsNew.Note?
    let dismissWhatsNew: () -> Void

    public init(geometry: NotchGeometry, now: Now, permission: Permission = .granted,
                expanded: Bool = false,
                progress: Interpolator? = nil, modes: Modes? = nil, holdBands: [Float]? = nil,
                probe: Bool = false, concealed: Bool = false, source: Source = .spotify,
                page: Expansion.Page = .player, plays: [Play] = [], queue: QueueView.Content? = nil,
                showPage: ((Expansion.Page) -> Void)? = nil,
                whatsNew: WhatsNew.Note? = nil, dismissWhatsNew: @escaping () -> Void = {},
                onScrubbing: @escaping (Bool) -> Void = { _ in },
                send: @escaping (Command) -> Void = { _ in },
                setRepeat: @escaping (Modes.Repeat) -> Void = { _ in },
                openLink: @escaping (LinkTarget, Track) -> Void = { _, _ in }) {
        self.geometry = geometry
        self.now = now
        self.permission = permission
        self.expanded = expanded
        self.concealed = concealed
        self.source = source
        self.progress = progress
        self.modes = modes
        self.holdBands = holdBands
        self.probe = probe
        self.onScrubbing = onScrubbing
        self.send = send
        self.setRepeat = setRepeat
        self.openLink = openLink
        self.page = page; self.plays = plays; self.queue = queue; self.showPage = showPage
        self.whatsNew = whatsNew; self.dismissWhatsNew = dismissWhatsNew
    }

    private var presentation: Presentation { .of(now: now, permission: permission) }
    private var open: Bool { expanded && presentation.draws }

    public var body: some View {
        Group {
            if probe {
                Shell(geometry: geometry, fill: .white, expanded: false)
            } else if presentation.draws {
                Shell(geometry: geometry, fill: Palette.background, expanded: open)
                    .overlay(alignment: .top) { content }
                    // Clipped to the shell so neither layer can spill past the
                    // shoulders mid-morph.
                    .clipShape(InverseCornerShape(
                        topRadius: NotchGeometry.shoulderRadius,
                        bottomRadius: Shell.bottomRadius(expanded: open)))
                    // Before the open animation, so opening from concealed
                    // fades in with the growth. Concealing alone is a quick
                    // dissolve: a blink reads as a glitch.
                    .opacity(concealed && !open ? 0 : 1)
                    .animation(.easeOut(duration: 0.15), value: concealed)
                    .animation(Motion.standard, value: open)
            }
            // Everything else -- the player closed, nothing loaded, a read that
            // has not come back -- draws nothing. The notch looks like a notch.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Both layers are always present and cross-faded, rather than swapped.
    ///
    /// **Not a `.transition` combined with `.opacity`**, which makes both
    /// views semi-transparent at once so they show through each other
    /// (matchnotch TRAPS #22). Here they never overlap visually: the peek's
    /// content lives in the wings and the panel's lives below the menu-bar
    /// line, so a plain opacity crossfade has nothing to muddy.
    ///
    /// The panel fades in over 0.14s, **not** timed to the spring. A spring's
    /// last few percent of travel is its slowest, so a fade matched to its
    /// nominal duration visibly hangs at the end (#36). The shell reaches
    /// most of its height early; the content should arrive then.
    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .top) {
            peek
                .opacity(open ? 0 : 1)
                .animation(.easeOut(duration: 0.10), value: open)
            panel
                .opacity(open ? 1 : 0)
                .animation(.easeIn(duration: 0.14).delay(open ? 0.06 : 0), value: open)
        }
    }

    /// The peek's stand-in track when nothing is known: no title, the player's mark.
    private var stand: Track {
        var track = PeekView.unknownTrack
        track.source = source
        return track
    }

    @ViewBuilder
    private var peek: some View {
        switch presentation {
        case .track(let track, let playing, _):
            // **Settled while hidden.** Under the open panel or concealed the
            // peek is at opacity 0, but live bars would still commit thirty
            // frames a second for the window server to composite. Flat bars
            // are drawn once; the live ones come back as the peek fades in.
            PeekView(geometry: geometry, track: track,
                     playing: playing && !open && !concealed, holdBands: holdBands)
        case .permissionNeeded:
            // The mark alone, in the slot the cover would take, with no bars
            // -- nothing is known about playback, and a row of dots would
            // claim otherwise. Still exactly one mark on screen.
            PeekView(geometry: geometry, track: stand,
                     playing: false, holdBands: nil, showsWaveform: false)
        case .nothing:
            EmptyView()
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch presentation {
        case .track(_, _, _) where whatsNew != nil:
            WhatsNewView(geometry: geometry, note: whatsNew!, dismiss: dismissWhatsNew)
        case .track(let track, let playing, let controllable):
            let pages: [Expansion.Page] = showPage == nil ? [.player]
                : track.source == .spotify ? [.player, .stats, .queue] : [.player, .stats]
            // A queue page left behind by a switch to Music shows as the stats.
            let current = pages.contains(page) ? page : pages.last ?? .player
            ZStack(alignment: .top) {
                pageView(PanelView(geometry: geometry, track: track, progress: progress,
                                   playing: playing, controllable: controllable, modes: modes,
                                   onScrubbing: onScrubbing, send: send, setRepeat: setRepeat,
                                   openLink: { openLink($0, track) },
                                   showStats: showPage.map { show in { show(.stats) } }),
                         .player, current)
                if pages.contains(.stats) {
                    pageView(StatsView(geometry: geometry, plays: plays, artwork: track.artworkURL),
                             .stats, current)
                }
                if pages.contains(.queue) {
                    pageView(QueueView(geometry: geometry, track: track, showing: current == .queue,
                                       fixed: queue),
                             .queue, current)
                }
                if pages.count > 1 { dots(pages.count, current.rawValue) }
            }
            .animation(Self.pageMotion, value: current)
        case .permissionNeeded:
            PermissionPanel(geometry: geometry, source: source)
        case .nothing:
            EmptyView()
        }
    }
}

extension RootView {
    /// The same move as the menu panel's pages (`MenuPanel.pageMotion`): both
    /// pages always exist, and only opacity and a short offset animate, which
    /// are transforms -- nothing is laid out again mid-move.
    static var pageMotion: Animation { MenuPanel.pageMotion }
    static let travel: CGFloat = 14

    /// Faded, nudged toward its side, and inert when it is not the page
    /// showing, so an invisible one cannot swallow the visible one's clicks.
    func pageView(_ content: some View, _ which: Expansion.Page, _ current: Expansion.Page) -> some View {
        let on = which == current
        return content
            .opacity(on ? 1 : 0)
            .offset(x: CGFloat(which.rawValue - current.rawValue) * Self.travel)
            .allowsHitTesting(on)
            .accessibilityHidden(!on)
    }

    /// Which page this is, in the bottom gap under the transport.
    func dots(_ count: Int, _ current: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Palette.primary : Palette.secondary.opacity(0.5))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 3)
        .accessibilityHidden(true)
    }
}

/// The black body. Its shoulders overhang its frame by `shoulderRadius`, which
/// is why `NotchGeometry.windowWidth` is wider than `openWidth`.
///
/// Its width changes only on a notchless screen, where the narrow peek grows
/// into the full panel; on a notch both widths are the same.
struct Shell: View {
    let geometry: NotchGeometry
    let fill: Color
    var expanded = false

    /// Collapsed the shape is a 37pt strip, where a large bottom radius would
    /// eat the whole thing; open it is a panel, where a small one reads as a
    /// hard edge. Animatable through `InverseCornerShape.animatableData`, so
    /// the corner grows with the height rather than snapping at the end.
    static func bottomRadius(expanded: Bool) -> CGFloat { expanded ? 22 : 8 }

    var body: some View {
        // `probed` on this one and not on the clip shape above: both animate
        // the same value on the same spring, and counting both is how a probe
        // reports a fake trajectory (matchnotch's `PageProbe` found exactly
        // that confound).
        InverseCornerShape(topRadius: NotchGeometry.shoulderRadius,
                           bottomRadius: Self.bottomRadius(expanded: expanded),
                           probed: true)
            .fill(fill)
            .frame(width: expanded ? geometry.openWidth : geometry.collapsedWidth,
                   height: expanded ? geometry.openHeight : geometry.collapsedHeight)
    }
}
