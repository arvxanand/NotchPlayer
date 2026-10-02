import AppKit

/// Where the hardware notch is, and how big. Everything the panel draws is
/// positioned from this.
///
/// Adapted from matchnotch. What is gone compared to that copy: there is only
/// one panel width here, because unlike a seven-tab match panel nothing needs
/// to be wider than anything else -- so `wideWidth` and
/// `panelFrame(contentWidth:)` have no reason to exist, and the clock row that
/// hung below matchnotch's peek is gone with them (see `collapsedHeight`).
public struct NotchGeometry: Equatable, Sendable {
    public let screenFrame: CGRect
    /// Width of the physical cutout. Zero on Macs without one.
    public let notchWidth: CGFloat
    /// Height of the menu-bar strip the notch occupies.
    public let notchHeight: CGFloat
    public let hasNotch: Bool

    /// Width of ONE wing beside the cutout.
    ///
    /// Equal either side, deliberately: the art wing needs ~43pt of content
    /// and the waveform wing ~54pt, but an asymmetric pair would leave the
    /// black shape off-centre on the cutout. So the wings match, take the
    /// wider requirement, and the *content* is aligned against the cutout
    /// instead -- `8pt` in from the housing, with whatever is left over
    /// falling outboard where the menu bar's own items are.
    ///
    /// 72 rather than matchnotch's 120: less of the menu bar covered, and
    /// nothing here needs the room.
    public static let collapsedSideWidth: CGFloat = 72


    /// The concave shoulders' radius, shared by the shape that draws them and
    /// the window that has to be wide enough to contain them.
    ///
    /// `InverseCornerShape` draws **outside** its own rect -- its path starts
    /// at `rect.minX - topRadius` -- so a shape framed at exactly
    /// `collapsedWidth` inside a window of exactly `collapsedWidth` has both
    /// shoulders clipped off, and a clipped concave shoulder is a square
    /// corner, which is the entire thing that separates a notch app from a
    /// black rectangle parked under the camera.
    public static let shoulderRadius: CGFloat = 11

    /// HIG minimum interactive target. Applies to the transport buttons in the
    /// expanded panel. The collapsed peek is not a click target at all, so it
    /// is not padded out to meet this -- see `collapsedHeight`.
    public static let minimumHitHeight: CGFloat = 44

    /// The expanded panel as drawn: 37pt of empty menu-bar band over the
    /// camera housing, then the cover, the text column and the transport row
    /// below it. `PanelView.height` adds the same numbers up and a test
    /// asserts the two agree.
    public static let panelHeight: CGFloat = 185

    /// The window is always sized to the expanded bounds and the content
    /// animates inside it; resizing an NSPanel per frame fights the compositor
    /// and makes hover tracking flicker at the boundary.
    ///
    /// **Only `slack` points spare, and that is the point.** `setInteractive`
    /// makes the *whole window* take events while the panel is open, so every
    /// surplus point is a dead zone swallowing clicks meant for whatever is
    /// underneath. matchnotch carries 460pt here because its panel height
    /// genuinely varies with content; ours is a fixed layout, so it does not.
    ///
    /// Derived from `panelHeight` rather than written beside it, so growing
    /// the panel cannot leave a window too short to hold it.
    public static let slack: CGFloat = 16
    public var windowHeight: CGFloat { openHeight + Self.slack }

    /// The band `panelHeight` was designed around: this Mac's 37pt cutout.
    static let designedBand: CGFloat = 37

    /// Height of the virtual notch if AppKit won't say how tall the menu bar
    /// is. 24 is a notchless MacBook's menu bar. Not `NSStatusBar.system.thickness`, which reads 22 and leaves
    /// the shape short of the bar it is meant to sit in.
    public static let fallbackMenuBarHeight: CGFloat = 24

    /// The open panel's width on a screen with no notch. With a cutout, the
    /// panel is as wide as the peek, because the peek straddles hardware. With
    /// none, the peek is only its two wings (144pt, as little of the menu bar
    /// as possible) and the panel grows out of it to this Mac's width -- the
    /// width every panel layout was tuned at.
    public static let virtualPanelWidth: CGFloat = 352

    /// The menu bar's real height, from AppKit's own number for it.
    ///
    /// **Not `frame.maxY - visibleFrame.maxY`**, which overshoots: 25 for a
    /// 24pt bar on a notchless screen (measured off a capture, 1 Oct 2026),
    /// 43 for a 37pt one on this Mac. A virtual notch a point taller than the
    /// bar shows as a lip hanging under it.
    ///
    /// `menuBarHeight` only answers for the app's main menu, and this app has
    /// none -- an accessory app with a main menu would show it when active. So
    /// one is lent for the read and taken straight back, inside one runloop
    /// turn, which nothing can draw in between.
    @MainActor static var menuBarHeight: CGFloat {
        let app = NSApplication.shared, own = app.mainMenu, lent = NSMenu()
        app.mainMenu = lent
        defer { app.mainMenu = own }
        return lent.menuBarHeight
    }

    @MainActor public init(screen: NSScreen) {
        screenFrame = screen.frame
        let inset = screen.safeAreaInsets.top
        if inset > 0 {
            // The notch is whatever the menu bar can't use between the two
            // auxiliary areas.
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let measured = screen.frame.width - left - right
            notchWidth = measured > 0 ? measured : 180
            notchHeight = inset
            hasNotch = true
        } else {
            // The real menu bar, so the virtual notch fills it exactly.
            let bar = Self.menuBarHeight
            notchWidth = 0
            notchHeight = bar > 0 ? bar : Self.fallbackMenuBarHeight
            hasNotch = false
        }
    }

    /// Test seam: build a geometry without a real screen, so the no-notch
    /// branch is reachable on notched hardware.
    public init(screenFrame: CGRect, notchWidth: CGFloat, notchHeight: CGFloat, hasNotch: Bool) {
        self.screenFrame = screenFrame; self.notchWidth = notchWidth
        self.notchHeight = notchHeight; self.hasNotch = hasNotch
    }

    /// The cutout plus a wing each side.
    public var collapsedWidth: CGFloat { notchWidth + Self.collapsedSideWidth * 2 }

    /// How far the shell reaches below the menu-bar line.
    ///
    /// **The physical cutout is slightly taller than `safeAreaInsets.top`.**
    /// A shell sized exactly to the inset leaves a sliver of the housing's
    /// bottom edge showing under it, so the black does not quite meet the
    /// hardware -- which is the one flaw that gives a notch app away.
    ///
    /// Two points, and it has to be small: every point past the cutout is
    /// black drawn over whatever window is beneath, and the reason the peek
    /// stays in the strip at all is below.
    ///
    /// **Reported from the machine, not measured here.** It is invisible in a
    /// screen capture -- the capture has no camera housing in it -- so this
    /// number came from somebody looking at the hardware, and changing it
    /// needs the same.
    public static let housingOverhang: CGFloat = 2

    /// **The peek is menu-bar height plus `housingOverhang`, and nothing
    /// more.**
    ///
    /// This is load-bearing rather than cosmetic. matchnotch's peek hangs 26pt
    /// below the menu bar, which is where a browser's tab bar lives -- so
    /// brushing the cutout lit the peek while the pointer was over a tab, and
    /// that is why hover-to-expand is a setting that ships *off* there
    /// (TRAPS #73/#80). Staying inside the menu-bar strip makes that whole
    /// class of bug unreachable, which is what lets hover be this app's
    /// primary gesture.
    ///
    /// No overhang without a notch: there is no housing to cover, and the
    /// virtual notch is exactly the menu bar.
    public var collapsedHeight: CGFloat { notchHeight + (hasNotch ? Self.housingOverhang : 0) }

    /// The open panel. Identical to the peek's width on a notched screen; see
    /// `virtualPanelWidth` for why it differs without one.
    public var openWidth: CGFloat { hasNotch ? collapsedWidth : Self.virtualPanelWidth }

    /// The open panel's height: `panelHeight` with its 37pt band swapped for
    /// the menu bar on a notchless screen. **Literally `panelHeight` on every
    /// notched screen**, including ones whose inset isn't 37, so nothing there
    /// moves.
    public var openHeight: CGFloat {
        hasNotch ? Self.panelHeight : notchHeight + Self.panelHeight - Self.designedBand
    }

    /// The cutout itself in screen coordinates (origin bottom-left, as
    /// `NSEvent.mouseLocation` reports).
    public var notchScreenRect: CGRect {
        CGRect(x: screenFrame.midX - notchWidth / 2,
               y: screenFrame.maxY - notchHeight,
               width: notchWidth, height: notchHeight)
    }

    /// The visible collapsed peek in screen coordinates.
    public var collapsedScreenRect: CGRect {
        CGRect(x: screenFrame.midX - collapsedWidth / 2,
               y: screenFrame.maxY - collapsedHeight,
               width: collapsedWidth, height: collapsedHeight)
    }

    /// The expanded panel as drawn, in screen coordinates. This -- not the
    /// window frame -- is what "is the pointer on the panel" should ask, and
    /// what the panel collapses when the pointer leaves.
    public var panelScreenRect: CGRect {
        CGRect(x: screenFrame.midX - openWidth / 2,
               y: screenFrame.maxY - openHeight,
               width: openWidth, height: openHeight)
    }

    // MARK: - Where the pointer may travel without losing the hover

    /// How far either side of the cutout the pointer may sit and still count
    /// as on the notch, **once it has already arrived there**.
    public static let hoverStayMargin: CGFloat = 40

    /// The leaving region: the cutout plus a margin either side, still inside
    /// the menu-bar strip.
    ///
    /// **Never an entry point.** Entry is `notchScreenRect` alone. Asymmetry
    /// is deliberate -- a small door in, a bigger one out (TRAPS #84) -- so a
    /// pointer drifting a few points off the housing on its way down into the
    /// opening panel does not read as having left.
    public var hoverStayScreenRect: CGRect {
        entryScreenRect.insetBy(dx: -Self.hoverStayMargin, dy: 0)
    }

    /// Where the pointer has to arrive to open the panel. The cutout on a
    /// notched screen. Without one, **exactly the drawn peek, no margin**:
    /// that strip is real menu bar, with menus and status items under it, and
    /// `notchScreenRect` is zero wide there -- hover could never begin.
    public var entryScreenRect: CGRect { hasNotch ? notchScreenRect : collapsedScreenRect }

    /// How long the pointer has to rest on the entry rect before it counts.
    /// Zero on a notch, which is dead space. On a notchless screen the peek
    /// sits on the path to the menu bar, and a pointer sweeping across it to
    /// reach a menu must not pop the panel open.
    public var entryDwell: TimeInterval { hasNotch ? 0 : 0.3 }

    /// Nothing legible may be drawn in this band -- it is behind the camera
    /// housing, which is physical and cannot be drawn over. Without a notch
    /// it is the menu bar, so the open panel still starts below the bar's
    /// line rather than putting the title in it.
    public var notchExclusionTop: CGFloat { notchHeight }

    /// The window frame. One width, always -- the drawn width plus room for
    /// the shoulders to overhang it (see `shoulderRadius`). The extra 11pt
    /// either side is transparent, and click-through except while the panel is
    /// open.
    public var windowWidth: CGFloat { openWidth + Self.shoulderRadius * 2 }

    public func panelFrame() -> CGRect {
        CGRect(x: screenFrame.midX - windowWidth / 2,
               y: screenFrame.maxY - windowHeight,
               width: windowWidth, height: windowHeight)
    }

    /// Where the camera housing sits **inside the window**, top-left origin.
    ///
    /// Computed from the designed frame, never from the window's live
    /// position: the check parks the window out of the way while capturing,
    /// and reading `window.frame` after that produced an offset of -690.
    /// This is a property of the layout, not of where the window happens to
    /// be, which is exactly why the check survives being moved.
    public var housingInWindow: CGRect {
        CGRect(x: notchScreenRect.minX - panelFrame().minX, y: 0,
               width: notchWidth, height: notchHeight)
    }

    /// The camera housing in **top-left origin** screen coordinates, which is
    /// what `screencapture -R x,y,w,h` wants.
    ///
    /// This exists so `tools/check_notch.sh` can ask the binary rather than
    /// hard-coding a rect. matchnotch's checker carries `856,0,208,37` inline,
    /// which is this display's numbers and nothing else's -- a copy of that
    /// script on another Mac would silently check the wrong pixels.
    public var captureRect: CGRect {
        CGRect(x: notchScreenRect.minX, y: 0, width: notchWidth, height: notchHeight)
    }
}

/// Whether there is a notch to draw on, so the menu-bar item can say why the
/// notch is empty instead of looking broken. Same test as
/// `AppController.notchedScreen`: any screen with a top inset has the cutout.
///
/// **Never run on a Mac without a notch.** The rule is pure so every case can
/// be tested on this one, which has a notch.
public enum NotchPresence: Equatable, Sendable {
    case present
    /// A built-in screen with no cutout: a 13" MacBook Pro, an M1 Air.
    case noNotch
    /// No built-in screen at all: a desktop Mac, or a MacBook with the lid
    /// shut. The two can't be told apart from the screen list, so the wording
    /// covers both.
    case noBuiltInScreen

    public nonisolated static func of(_ screens: [(builtIn: Bool, topInset: CGFloat)]) -> NotchPresence {
        if screens.contains(where: { $0.topInset > 0 }) { return .present }
        return screens.contains(where: { $0.builtIn }) ? .noNotch : .noBuiltInScreen
    }

    @MainActor public static var current: NotchPresence {
        of(NSScreen.screens.map { (builtIn: $0.isBuiltIn, topInset: $0.safeAreaInsets.top) })
    }
}

extension NSScreen {
    public var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The laptop's own panel. Not in `NSScreen.screens` with the lid shut.
    public var isBuiltIn: Bool { displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }
}
