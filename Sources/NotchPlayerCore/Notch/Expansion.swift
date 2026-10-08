import AppKit
import Combine

/// Turns "the pointer is on the cutout" into "the panel is open".
///
/// Separate from both the view and the panel because it is the one piece that
/// has to talk to all three: it reads `HoverWatcher`, it flips the window's
/// `ignoresMouseEvents`, and it publishes a flag SwiftUI animates on.
@MainActor
public final class Expansion: ObservableObject {
    @Published public private(set) var expanded = false

    /// The menu bar is gone -- an app is full screen, or it auto-hides -- so
    /// the closed peek hides until the pointer opens it (#17). Kept here only
    /// because `Live` already observes this object.
    @Published public var fullScreen = false

    /// Faded so the menus under the wings show; see `HoverWatcher.faded`.
    @Published public private(set) var faded = false

    /// Which page the open panel shows. Every open starts on the player, so
    /// leaving the picks without choosing is just moving away.
    public enum Page: Sendable { case player, picks }
    @Published public private(set) var page = Page.player

    /// Whether there is a picks page to go to: Spotify's, so not while Music
    /// is the one showing.
    public var hasPicks: () -> Bool = { false }

    private var scrollMonitor: Any?
    private var swipeSum = CGSize.zero

    private let watcher: HoverWatcher
    private var geometry: NotchGeometry?
    private var bag: Set<AnyCancellable> = []

    /// Flips the window between click-through and click-taking. Only ever
    /// true while the panel is open and has something to click: a window that
    /// accepts events swallows clicks meant for whatever is underneath, and
    /// this app is never more important than the window you are working in.
    public var setInteractive: ((Bool) -> Void)?

    /// Called the instant the panel opens.
    ///
    /// This is the fix for the stale-position ceiling: a seek made in
    /// Spotify's own window while paused publishes no notification, and the
    /// reconcile tick is off while paused, so the stored position can be
    /// wrong. It is invisible in the collapsed peek, which draws no progress
    /// bar -- opening the panel is the exact moment it starts mattering.
    public var onOpen: (() -> Void)?

    /// Whether there is anything to expand into. Without this, brushing the
    /// cutout while nothing is playing opens an empty panel.
    public var hasContent: () -> Bool = { false }

    /// Set while the user is dragging something in the panel -- today, the
    /// progress line.
    ///
    /// A drag that starts on the bar and continues past the bottom of the
    /// panel is an ordinary thing to do, and without this the watcher sees the
    /// pointer leave, collapses the panel, and takes the control out from
    /// under the hand holding it.
    private var holding = false

    /// Optional rather than defaulted, because a default argument expression
    /// is evaluated nonisolated and `HoverWatcher` is main-actor bound.
    public init(watcher: HoverWatcher? = nil) {
        self.watcher = watcher ?? HoverWatcher()
    }

    public func start(geometry: NotchGeometry) {
        self.geometry = geometry
        // Entry is the cutout alone (the drawn peek, without a notch);
        // leaving takes the wider region. A small door in, a bigger one out.
        watcher.notchRect = geometry.entryScreenRect
        watcher.stayRect = geometry.hoverStayScreenRect
        watcher.entryDwell = geometry.entryDwell
        watcher.wingRects = geometry.wingScreenRects
        watcher.menuBarRect = geometry.menuBarScreenRect
        watcher.$faded
            .removeDuplicates()
            .sink { [weak self] faded in self?.faded = faded }
            .store(in: &bag)
        watcher.$inside
            .removeDuplicates()
            .sink { [weak self] inside in self?.hover(inside) }
            .store(in: &bag)
        watcher.start()
    }

    public func stop() {
        holding = false
        watcher.stop()
        bag.removeAll()
        collapse()
    }

    /// Pure, so the four combinations can be asserted without a pointer.
    ///
    /// Opening needs content; closing never does -- otherwise a track ending
    /// while the panel is open would strand it there with nothing to draw and
    /// no way to shut it.
    /// `nonisolated` because it touches no state -- three booleans in, one
    /// out. A test should not have to hop actors to ask a question about
    /// arithmetic.
    public nonisolated static func shouldExpand(inside: Bool, hasContent: Bool,
                                                expanded: Bool, holding: Bool = false) -> Bool {
        // Holding keeps an open panel open; it cannot open a closed one. A
        // drag has to start somewhere, and that somewhere is the open panel.
        if holding, expanded { return true }
        return inside && (hasContent || expanded)
    }

    /// Hold the panel open through a drag, and re-decide when it ends.
    ///
    /// **The re-decide is the whole reason this is a method and not a flag.**
    /// `$inside` is `removeDuplicates`d, so if the pointer left during the
    /// drag there is no further event to act on -- releasing outside the panel
    /// would leave it open until the pointer went back in and out again.
    public func hold(_ on: Bool) {
        guard on != holding else { return }
        holding = on
        if !on { hover(watcher.inside) }
    }

    private func hover(_ inside: Bool) {
        let wanted = Self.shouldExpand(inside: inside, hasContent: hasContent(),
                                       expanded: expanded, holding: holding)
        guard wanted != expanded else { return }
        if wanted { open() } else { collapse() }
    }

    private func open() {
        guard let geometry else { return }
        expanded = true
        // Once open, the whole drawn panel holds the hover, so the pointer can
        // travel down into it without it collapsing underfoot.
        watcher.activeRect = geometry.panelScreenRect
        setInteractive?(true)
        // **Local, so no permission**: it only sees scrolls sent to this app,
        // which the open panel gets because it is under the pointer. Not the
        // global monitor matchnotch had (`docs/DECISIONS.md`). Passed on
        // untouched, so the picks still scroll.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.scrolled(event) }
            return event
        }
        onOpen?()
    }

    private func collapse() {
        guard expanded else { return }
        expanded = false
        page = .player
        scrollMonitor.map(NSEvent.removeMonitor)
        scrollMonitor = nil
        watcher.activeRect = nil
        setInteractive?(false)
    }

    public func show(_ page: Page) {
        guard expanded, page == .player || hasPicks() else { return }
        self.page = page
    }

    /// One trackpad gesture, added up from its first touch to its last.
    /// A mouse wheel has no phases, so it never flips a page.
    private func scrolled(_ event: NSEvent) {
        switch event.phase {
        case .began:
            swipeSum = .zero
        case .changed:
            swipeSum.width += event.scrollingDeltaX
            swipeSum.height += event.scrollingDeltaY
        case .ended, .cancelled:
            // The way the fingers moved, whichever way scrolling is set.
            let fingers = event.isDirectionInvertedFromDevice ? swipeSum.width : -swipeSum.width
            if let page = Self.swipe(dx: fingers, dy: swipeSum.height,
                                     precise: event.hasPreciseScrollingDeltas) {
                show(page)
            }
            swipeSum = .zero
        default:
            break
        }
    }

    /// Fingers moving left bring in the page on the right, the picks; moving
    /// right go back. Mostly sideways and at least 40pt, so scrolling the
    /// picks up and down never flips the page.
    nonisolated static func swipe(dx: CGFloat, dy: CGFloat, precise: Bool) -> Page? {
        guard precise, abs(dx) >= 40, abs(dx) > 2 * abs(dy) else { return nil }
        return dx < 0 ? .picks : .player
    }
}
