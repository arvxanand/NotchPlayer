import AppKit

/// Tracks whether the pointer is over the notch, *without* the panel needing
/// to receive mouse events.
///
/// This exists because the panel must be genuinely click-through while
/// collapsed. SwiftUI's `.onHover` only fires when the window accepts events,
/// and a window that accepts events swallows clicks meant for whatever is
/// underneath -- browser tabs and menu-bar items, which are always more
/// important than this app. Same for `.onTapGesture`. Both fail *silently*,
/// which is how you get a UI that looks finished and does nothing.
///
/// Polling `NSEvent.mouseLocation` costs nothing measurable at 12Hz and needs
/// no permission at all. Adapted from matchnotch with the scroll/swipe half
/// removed: that needed a global event monitor, and a global monitor needs a
/// real `NSApplication` to receive anything (TRAPS #17). Nothing here does.
@MainActor
public final class HoverWatcher: ObservableObject {
    /// True while the pointer is inside the region we currently care about.
    @Published public private(set) var inside = false

    /// The cutout itself, in screen coordinates. Small on purpose: it is dead
    /// space on the menu bar, so claiming it costs the user nothing.
    public var notchRect: CGRect = .zero

    /// While expanded we watch the whole drawn panel, so the pointer can
    /// travel down into it -- to the transport buttons -- without it
    /// collapsing underfoot.
    public var activeRect: CGRect?

    /// Where the pointer may travel to **without losing** a hover it already
    /// has. Never an entry point; see `hoverRegion`.
    public var stayRect: CGRect?

    /// Bumped each time a click lands anywhere on screen; read
    /// `lastClickPoint` for where. Detected by polling the button state rather
    /// than by receiving the event, because the panel must stay
    /// click-through. Its one job here is click-outside-to-collapse.
    @Published public private(set) var clickSeq = 0
    public private(set) var lastClickPoint: CGPoint = .zero

    /// Where the pointer counts as "on the notch".
    ///
    /// **Asymmetric on purpose: a small door in, a bigger one out**
    /// (TRAPS #84). Arriving takes the cutout alone; leaving takes the cutout
    /// *or* `stayRect`. Widening the *entry* is what caused matchnotch's
    /// BUGS #73 -- the peek lighting up from across a browser's tab bar -- so
    /// entry stays exactly the housing.
    var hoverRegion: CGRect {
        Self.hoverRegion(notch: notchRect, stay: stayRect, active: activeRect, inside: inside)
    }

    /// Pure, so all four combinations can be asserted without driving a real
    /// pointer. `nonisolated` for exactly that reason: it touches no state, so
    /// a test should not have to hop to the main actor to ask it a question.
    nonisolated static func hoverRegion(notch: CGRect, stay: CGRect?, active: CGRect?,
                            inside: Bool) -> CGRect {
        if let active { return active }
        return inside ? (stay ?? notch) : notch
    }

    private var timer: Timer?
    private var wasPressed = false
    /// Idle rate. Cheap, and good enough to notice the pointer arriving.
    private static let idleInterval: TimeInterval = 1.0 / 12.0
    /// Near the cutout we sample faster, or a short click falls between frames.
    private static let activeInterval: TimeInterval = 1.0 / 30.0
    private var currentInterval: TimeInterval = 1.0 / 12.0

    /// How long the pointer must be outside before the hover drops.
    ///
    /// Without it, a fast diagonal across the housing on the way somewhere
    /// else opens and closes the panel inside 100ms, which reads as a flicker
    /// rather than as a hover that was never meant. It is also what lets the
    /// pointer cross the seam between the peek and the opening panel while the
    /// two rects are mid-swap.
    public static let exitGrace: TimeInterval = 0.25
    private var outsideSince: Date?

    public init() {}

    public func start() { schedule(Self.idleInterval) }

    public func stop() { timer?.invalidate(); timer = nil }

    private func schedule(_ interval: TimeInterval) {
        timer?.invalidate()
        currentInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        // .common so it keeps firing while a menu is open or during a drag.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        let point = NSEvent.mouseLocation
        let hit = hoverRegion.contains(point)

        // Entering is immediate; leaving waits out `exitGrace`.
        if hit {
            outsideSince = nil
            if !inside { inside = true }
        } else if inside {
            let since = outsideSince ?? Date()
            outsideSince = since
            if Date().timeIntervalSince(since) >= Self.exitGrace { inside = false }
        }

        // Report every press with where it landed; the view decides whether it
        // means anything. Polled, not received, because the panel has to stay
        // click-through while collapsed.
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        if pressed && !wasPressed {
            lastClickPoint = point
            clickSeq += 1
        }
        wasPressed = pressed

        // Sample faster near the cutout so a quick click is not missed between
        // frames, and drop back to idle rate once the pointer leaves.
        let wanted = (hit || notchRect.insetBy(dx: -40, dy: -40).contains(point))
            ? Self.activeInterval : Self.idleInterval
        if wanted != currentInterval { schedule(wanted) }
    }
}
