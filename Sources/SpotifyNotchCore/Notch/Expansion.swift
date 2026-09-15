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

    /// Optional rather than defaulted, because a default argument expression
    /// is evaluated nonisolated and `HoverWatcher` is main-actor bound.
    public init(watcher: HoverWatcher? = nil) {
        self.watcher = watcher ?? HoverWatcher()
    }

    public func start(geometry: NotchGeometry) {
        self.geometry = geometry
        // Entry is the cutout alone; leaving takes the wider region. A small
        // door in, a bigger one out.
        watcher.notchRect = geometry.notchScreenRect
        watcher.stayRect = geometry.hoverStayScreenRect
        watcher.$inside
            .removeDuplicates()
            .sink { [weak self] inside in self?.hover(inside) }
            .store(in: &bag)
        watcher.start()
    }

    public func stop() {
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
                                                expanded: Bool) -> Bool {
        inside && (hasContent || expanded)
    }

    private func hover(_ inside: Bool) {
        let wanted = Self.shouldExpand(inside: inside, hasContent: hasContent(),
                                       expanded: expanded)
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
        onOpen?()
    }

    private func collapse() {
        guard expanded else { return }
        expanded = false
        watcher.activeRect = nil
        setInteractive?(false)
    }
}
