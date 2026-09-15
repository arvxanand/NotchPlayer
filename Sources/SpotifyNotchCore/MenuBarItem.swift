import AppKit

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
/// A plain `NSMenu`, not a popover. matchnotch's status item opens a SwiftUI
/// panel because it has settings and a fixture list; this one has three lines,
/// and a menu is what the system already draws well -- keyboard navigable,
/// VoiceOver correct, and it costs nothing when closed.
@MainActor
public final class MenuBarItem: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let visibility = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private let summary: () -> String
    private let hidden: () -> Bool
    private let setHidden: (Bool) -> Void

    public init(summary: @escaping () -> String,
                hidden: @escaping () -> Bool,
                setHidden: @escaping (Bool) -> Void) {
        self.summary = summary
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

        status.isEnabled = false
        visibility.target = self
        visibility.action = #selector(toggleHidden)
        let quit = NSMenuItem(title: "Quit SpotifyNotch",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(visibility)
        menu.addItem(.separator())
        menu.addItem(quit)
        // Built when the menu opens rather than on every state change: a
        // closed menu has nobody reading it, and the alternative is another
        // subscriber redrawing text thirty times a minute for nothing.
        menu.delegate = self
        item.menu = menu
    }

    /// Remove the item when the app goes away. A status item outlives its
    /// owner otherwise and leaves a dead icon in the menu bar until the next
    /// login.
    public func remove() { NSStatusBar.system.removeStatusItem(item) }

    public func menuWillOpen(_ menu: NSMenu) {
        status.title = summary()
        visibility.title = hidden() ? "Show in the Notch" : "Hide from the Notch"
    }

    @objc private func toggleHidden() { setHidden(!hidden()) }

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
