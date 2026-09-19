import AppKit
import SwiftUI

/// The window itself. A borderless, transparent, non-activating panel pinned
/// above the menu bar at the top-centre of the screen.
///
/// Deliberately not an NSStatusItem: this has to sit *at* the notch and expand
/// outward from it, which a menu-bar item cannot do.
public final class NotchPanel: NSPanel {
    public private(set) var geometry: NotchGeometry

    public init<Content: View>(screen: NSScreen, @ViewBuilder content: () -> Content) {
        geometry = NotchGeometry(screen: screen)
        super.init(contentRect: geometry.panelFrame(),
                   // .nonactivatingPanel keeps focus in whatever the user is
                   // actually doing; hovering the notch must never steal it.
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        // Click-through until the user actually engages with the panel. A
        // window that accepts events swallows clicks meant for whatever is
        // underneath it -- browser tabs, menu-bar items -- and this app is
        // never more important than the window you are actually using.
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        // Above the menu bar (.mainMenu is 24) so we can overlap the notch.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]

        let host = FirstMouseHostingView(rootView: content())
        host.frame = CGRect(origin: .zero, size: geometry.panelFrame().size)
        host.autoresizingMask = [.width, .height]
        contentView = host
        setFrame(geometry.panelFrame(), display: true)
        orderFrontRegardless()
    }

    // Borderless panels refuse key status by default; the expanded panel has
    // buttons, so it needs to be able to take clicks -- but **only then**.
    // A click-through panel that can become key is a window that can take
    // keyboard focus while being unable to receive a mouse event, which is
    // nobody's idea of correct and is a plausible way to interrupt someone's
    // typing from a process they cannot see.
    public override var canBecomeKey: Bool { !ignoresMouseEvents }
    public override var canBecomeMain: Bool { false }

    /// Accept clicks only while the panel is expanded and has something to
    /// click. Everything else passes straight through.
    public func setInteractive(_ interactive: Bool) {
        ignoresMouseEvents = !interactive
    }

    /// Move the panel out of the way of whoever is using the machine.
    ///
    /// The footprint check works in **window-local** coordinates -- the camera
    /// housing is a fixed offset inside the window -- so where the window sits
    /// on screen has no bearing on what is being asserted. Parking it means a
    /// capture run does not spend a minute flashing panels across the menu bar
    /// somebody is trying to type under.
    ///
    /// **On screen, at the bottom, not off it.** A window moved entirely
    /// outside every display stops being capturable: macOS drops the backing
    /// store, and `screencapture -l` comes back with something that is not
    /// your window at all (measured: a 1040x74 image for a 374x201 window).
    public func park() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.screens.first else { return }
        setFrameOrigin(CGPoint(x: screen.frame.maxX - frame.width, y: screen.frame.minY))
        orderFrontRegardless()
    }

    /// Re-measure after a display change (external monitor, resolution switch,
    /// lid open). Geometry is read fresh rather than cached at launch.
    public func reposition(to screen: NSScreen) {
        geometry = NotchGeometry(screen: screen)
        setFrame(geometry.panelFrame(), display: true)
        orderFrontRegardless()
    }
}

/// A hosting view that takes the *first* click in a window that is not key.
///
/// **This is what a drag needs and a button does not.** The panel never
/// activates the app, so it is rarely the key window; AppKit gives an inactive
/// window's first click to the window itself unless the view under it says
/// otherwise. A `Button` survives that, because it acts on mouse-**up** -- so
/// the transport worked for three milestones and hid the problem. A
/// `DragGesture` needs the mouse-down that was being eaten, and without this
/// the progress line could not be grabbed at all: no error, no gesture, the
/// pointer simply slid over it.
///
/// matchnotch needed the same subclass for its popover, for the same reason.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// `NSHostingView` declares this initialiser as required, and a subclass
    /// has to restate it. Never used -- there are no nibs in this app.
    @MainActor required init?(coder: NSCoder) { nil }
    @MainActor required init(rootView: Content) { super.init(rootView: rootView) }
}
