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

    /// One sample's decision. Pure, so the timing can be asserted without a
    /// pointer or a clock. A change of state only lands once it has held for
    /// its wait; a sample that agrees with the current state drops whatever
    /// was pending, which is what makes a sweep across the peek reset the
    /// dwell rather than add to it.
    nonisolated static func step(hit: Bool, inside: Bool, since: Date?, now: Date,
                                 dwell: TimeInterval, grace: TimeInterval)
        -> (inside: Bool, since: Date?) {
        guard hit != inside else { return (inside, nil) }
        let since = since ?? now
        return now.timeIntervalSince(since) >= (hit ? dwell : grace)
            ? (hit, nil) : (inside, since)
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

    /// How long the pointer must rest on the entry rect before the hover
    /// starts. Zero on a notch; see `NotchGeometry.entryDwell`.
    public var entryDwell: TimeInterval = 0

    /// When the pending change began: arriving (outside, now hitting) or
    /// leaving (inside, now missing). One date serves both because the two
    /// can never be pending at once.
    private var pendingSince: Date?

    // MARK: - Fading off the menus

    /// The peek is faded out so the menus under its wings show (#16).
    @Published public private(set) var faded = false
    /// Resting on one of these fades the peek. Empty means never.
    public var wingRects: [CGRect] = []
    /// A faded peek stays faded while the pointer is anywhere in here.
    public var menuBarRect: CGRect = .zero
    private var fadeSince: Date?

    /// How long the peek stays faded once nothing is holding it, so leaving
    /// one menu for the next across a gap doesn't flash it back.
    public static let fadeGrace: TimeInterval = 0.4

    /// What holds the fade, for `step`. Pure, for tests.
    ///
    /// **Going faded:** resting on a wing, and not on the notch's own hover --
    /// the stay region overlaps the inner part of each wing, and a pointer on
    /// its way into the panel is not aiming at a menu. **Staying faded:**
    /// anywhere on the menu bar, or with a menu open, wherever the pointer is
    /// -- so the peek doesn't come back over "Help" while its menu is being
    /// read. `menuOpen` is a closure because it asks the window server, and
    /// is only asked once the pointer has left the menu bar.
    nonisolated static func fadeHit(faded: Bool, point: CGPoint, inside: Bool, wings: [CGRect],
                                    menuBar: CGRect, menuOpen: () -> Bool) -> Bool {
        if faded { return menuBar.contains(point) || menuOpen() }
        return !inside && wings.contains { $0.contains(point) }
    }

    /// Whether any app has a menu open: its windows sit at the pop-up menu
    /// level. Layer is readable without Screen Recording permission.
    static func menuOpen() -> Bool {
        let level = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { $0[kCGWindowLayer as String] as? Int == level }
    }

    public init() {}

    public func start() { schedule(Self.idleInterval) }

    public func stop() {
        timer?.invalidate(); timer = nil
        faded = false; fadeSince = nil
    }

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

        // Entering waits out `entryDwell` (none on a notch); leaving waits
        // out `exitGrace`.
        let now = Date()
        let next = Self.step(hit: hit, inside: inside, since: pendingSince, now: now,
                             dwell: entryDwell, grace: Self.exitGrace)
        pendingSince = next.since
        if next.inside != inside { inside = next.inside }

        // The same timing rule for the fade: rest on a wing to go faded,
        // `fadeGrace` without menu bar or menu to come back.
        if !wingRects.isEmpty {
            let hold = Self.fadeHit(faded: faded, point: point, inside: inside, wings: wingRects,
                                    menuBar: menuBarRect, menuOpen: Self.menuOpen)
            let fade = Self.step(hit: hold, inside: faded, since: fadeSince, now: now,
                                 dwell: NotchGeometry.wingFadeDwell, grace: Self.fadeGrace)
            fadeSince = fade.since
            if fade.inside != faded { faded = fade.inside }
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
