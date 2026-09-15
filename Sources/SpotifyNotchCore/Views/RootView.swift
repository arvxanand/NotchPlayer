import SwiftUI

/// Everything the panel draws.
public struct RootView: View {
    let geometry: NotchGeometry
    let now: Now
    let permission: Permission
    let expanded: Bool
    let progress: Interpolator?
    /// Fixed bar values for a reproducible capture; nil animates.
    let holdBands: [Float]?
    /// `--probe`: fill the shell white so its geometry can be measured. The
    /// peek is otherwise unmeasurable -- a black shape on a dark menu bar is
    /// the same pixels as no shape, in a capture and to the eye.
    let probe: Bool
    /// A no-op in previews, so a capture cannot control the user's playback.
    let send: (SpotifyBridge.Command) -> Void

    public init(geometry: NotchGeometry, now: Now, permission: Permission = .granted,
                expanded: Bool = false,
                progress: Interpolator? = nil, holdBands: [Float]? = nil,
                probe: Bool = false,
                send: @escaping (SpotifyBridge.Command) -> Void = { _ in }) {
        self.geometry = geometry
        self.now = now
        self.permission = permission
        self.expanded = expanded
        self.progress = progress
        self.holdBands = holdBands
        self.probe = probe
        self.send = send
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
                    .animation(Motion.standard, value: open)
            }
            // Everything else -- Spotify closed, nothing loaded, a read that
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

    @ViewBuilder
    private var peek: some View {
        switch presentation {
        case .track(let track, let playing, _):
            PeekView(geometry: geometry, track: track, playing: playing, holdBands: holdBands)
        case .permissionNeeded:
            // The mark alone, in the slot the cover would take, with no bars
            // -- nothing is known about playback, and a row of dots would
            // claim otherwise. Still exactly one mark on screen.
            PeekView(geometry: geometry, track: PeekView.unknownTrack,
                     playing: false, holdBands: nil, showsWaveform: false)
        case .nothing:
            EmptyView()
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch presentation {
        case .track(let track, let playing, let controllable):
            PanelView(geometry: geometry, track: track, progress: progress,
                      playing: playing, controllable: controllable, send: send)
        case .permissionNeeded:
            PermissionPanel(geometry: geometry)
        case .nothing:
            EmptyView()
        }
    }
}

/// The black body. Its shoulders overhang its frame by `shoulderRadius`, which
/// is why `NotchGeometry.windowWidth` is wider than `collapsedWidth`.
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
            .frame(width: geometry.collapsedWidth,
                   height: expanded ? NotchGeometry.panelHeight : geometry.collapsedHeight)
    }
}
