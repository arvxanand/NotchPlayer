import AppKit
import ServiceManagement
import SwiftUI

/// The menu-bar item: what is playing, a way to get the panel off the notch,
/// and a way to quit.
///
/// **Why this exists when the app deliberately has no dock icon and no window
/// to close.** Two notch apps share one notch. The user runs matchnotch as
/// well, and when both have something to say they draw over each other -- so
/// there has to be a way to stand one of them down without killing it from a
/// terminal. Hiding keeps the app running and the item in the menu bar, which
/// is the difference between standing down and disappearing: quitting a
/// `LSUIElement` app that has no icon means the only way back is Spotlight.
///
/// A popover, not an `NSMenu`. It was a menu first, and three lines of text
/// were the wrong answer for an app whose subject is an album cover -- see
/// `MenuPanel`. The cost of the change is this class having to do what AppKit
/// does for free with a menu: close on a second click, and not reopen itself
/// while dismissing (`closedAt` below).
@MainActor
public final class MenuBarItem: NSObject, NSPopoverDelegate {
    private let item: NSStatusItem
    private let popover = NSPopover()

    private let state: () -> (now: Now, permission: Permission)
    private let hidden: () -> Bool
    private let setHidden: (Bool) -> Void
    /// When the popover last closed. A `.transient` popover is dismissed by
    /// AppKit on *any* outside click, and the status item is outside it -- so
    /// clicking the icon to close fires both AppKit's dismissal and the
    /// button's action, in an order that is not guaranteed. matchnotch learned
    /// this; without it the second click closes and immediately reopens.
    private var closedAt: Date?

    public init(state: @escaping () -> (now: Now, permission: Permission),
                hidden: @escaping () -> Bool,
                setHidden: @escaping (Bool) -> Void) {
        self.state = state
        self.hidden = hidden
        self.setHidden = setHidden
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        // A system symbol, not a bundled asset: it picks up the menu bar's own
        // tint in both appearances, under Reduce Transparency, and on a tinted
        // wallpaper. `waveform` rather than anything Spotify-shaped, because
        // this is the app's icon and not the service's -- and because
        // matchnotch's item is a sport glyph two positions away, so the two
        // must not be confusable at 16pt.
        let image = NSImage(systemSymbolName: "waveform",
                            accessibilityDescription: "SpotifyNotch")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "SpotifyNotch"

        popover.contentSize = NSSize(width: MenuPanel.width, height: MenuPanel.height)
        // Transient: clicking anywhere else dismisses it, the way a menu does.
        popover.behavior = .transient
        // **AppKit's own animation off; `MenuPanel` animates itself in.**
        // `NSPopover`'s scale-and-fade lays SwiftUI out while it runs, which
        // matchnotch measured as choppy.
        popover.animates = false
        popover.delegate = self
        item.button?.target = self
        item.button?.action = #selector(toggle)
    }

    /// Rebuilt on every open rather than subscribed to the service.
    ///
    /// A closed popover has nobody reading it, and the alternative is a second
    /// observer re-rendering a hidden window every time the position ticks.
    /// The panel is a function of plain values for the same reason `RootView`
    /// is -- so this can hand it a snapshot.
    private func rebuild() {
        let (now, permission) = state()
        let hidden = hidden()
        popover.contentViewController = NSHostingController(rootView: MenuPanel(
            track: now.track,
            playing: now.isPlaying,
            subtitle: Self.summary(now: now, permission: permission, hidden: hidden),
            hidden: hidden,
            toggleHidden: { [weak self] in
                self?.setHidden(!hidden)
                self?.popover.performClose(nil)
            },
            login: Self.login,
            // Stays open so the box visibly changes -- unlike Hide, whose
            // effect is on the notch.
            toggleLogin: {
                Self.toggleLogin()
                print("launch at login: now \(Self.login)")
                return Self.login
            },
            quit: { NSApp.terminate(nil) }))
    }

    // MARK: - Launch at login

    /// Read on every open, never cached: the user can change it in System
    /// Settings -> General -> Login Items while the app runs.
    private static var login: MenuPanel.Login {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        // `.notFound` too: a debug binary outside a bundle has nothing to
        // register, and "off" is the truth about it.
        default: .off
        }
    }

    private static func toggleLogin() {
        do {
            switch login {
            case .on: try SMAppService.mainApp.unregister()
            case .off: try SMAppService.mainApp.register()
            case .needsApproval: SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            // The box stays as it was, which is the visible half of this.
            print("launch at login: \(error)")
        }
    }

    @objc private func toggle() {
        if popover.isShown { return popover.performClose(nil) }
        // AppKit already closed it for this very click.
        if let closedAt, Date().timeIntervalSince(closedAt) < 0.2 { return }
        guard let button = item.button else { return }
        rebuild()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // A status-item popover opens behind every other window otherwise --
        // the app is `.accessory` and has never activated itself. This is the
        // one place it may, because the user clicked the icon; the notch panel
        // still never takes focus, which is the rule that is load-bearing.
        popover.contentViewController?.view.window?.makeKey()
    }

    public func popoverDidClose(_ note: Notification) { closedAt = Date() }

    /// Remove the item when the app goes away. A status item outlives its
    /// owner otherwise and leaves a dead icon in the menu bar until the next
    /// login.
    public func remove() { NSStatusBar.system.removeStatusItem(item) }

    // MARK: - What the first line says

    /// The one-line description of the app's state.
    ///
    /// Pure and `nonisolated` so a test can call it for every case, rather
    /// than a test restating the strings it hopes the menu contains.
    ///
    /// Hidden wins over everything: if the panel is not on the notch, that is
    /// the fact the user opened this menu to check, and what Spotify happens
    /// to be playing is beside the point.
    public nonisolated static func summary(now: Now, permission: Permission,
                                           hidden: Bool) -> String {
        if hidden { return "Hidden from the notch" }
        if permission == .denied, now.track == nil { return "Cannot read Spotify" }
        switch now {
        case .notRunning: return "Spotify is not running"
        case .stopped: return "Nothing playing"
        // The service only publishes this before its first successful read,
        // so it means "still looking", not "broken".
        case .unknown: return "Reading Spotify\u{2026}"
        case .track(let track, _, _):
            let line = "\(shorten(track.name)) \u{2014} \(shorten(track.artist))"
            return now.isPlaying ? line : line + " (paused)"
        }
    }

    /// A menu that is wider than the app it belongs to looks broken, and track
    /// titles have no upper bound -- see the `longtitle` preview state, which
    /// exists because data sized to fit hides the case that does not.
    nonisolated static let limit = 34

    nonisolated static func shorten(_ text: String) -> String {
        guard text.count > limit else { return text }
        // Ellipsis, not three dots: one character, and VoiceOver reads it as
        // a truncation rather than as "dot dot dot".
        return text.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}
