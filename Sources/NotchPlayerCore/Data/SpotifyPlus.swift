import AppKit
import ApplicationServices

/// The panel's +: saving the playing song.
///
/// **Spotify's dictionary cannot save a song, and the Web API needs a
/// developer app capped at five users** -- so the + presses Spotify's *own* +
/// through Accessibility, the channel VoiceOver uses. Spotify's button then
/// does what it always does: a song not yet saved goes to Liked Songs, a saved
/// one opens Spotify's playlist picker. Measured on 22 Sep 2026: the button
/// in the now-playing bar labelled "Add to playlist" on a saved song opened
/// the real picker when pressed. Which button that is: `target(in:)`.
///
/// **Opt-in, and every failure opens the song instead** -- the same album,
/// song highlighted, that the title opens. Off, not allowed, button not found,
/// or a label that is not one of the two we know: the click still lands in
/// Spotify on the right song, it just does not press anything.
@MainActor
public enum SpotifyPlus {
    /// UserDefaults. Off by default: this needs a second macOS permission.
    public static let enabledKey = "plusUsesSpotify"
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Verified the way `PermissionNote.settingsURL` was: opened, and the
    /// Accessibility list is what came up.
    static let settingsURL = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    // MARK: - The settings row

    /// Read on every open of the menu: the user can take the permission away
    /// in System Settings, and a rebuild may lose it too (ad-hoc signing).
    public static var status: MenuPanel.Grant {
        grant(enabled: enabled, trusted: AXIsProcessTrusted())
    }

    public static func toggle() -> MenuPanel.Grant {
        switch status {
        case .on: enabled = false
        case .off:
            enabled = true
            prompt()
        case .needsApproval: repair()
        }
        print("plus: now \(status)")
        return status
    }

    /// macOS's own prompt, which adds the app to the list with a button to
    /// System Settings. Only on the user's click, never at launch.
    private static func prompt() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Switched on and still refused: almost always an entry made for an
    /// earlier build, which every update leaves behind (`docs/TRAPS.md` #51).
    /// Switching that entry off and on keeps the old build's requirement, and
    /// macOS will not prompt while it exists -- so delete **our own** entry
    /// and ask again, which is what `tccutil reset` by hand did. It can only
    /// take away a permission this app was refused anyway; nobody else's is
    /// touched, and it runs only on the user's click.
    private static func repair() {
        if let id = Bundle.main.bundleIdentifier {
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", "Accessibility", id]
            try? reset.run()
            reset.waitUntilExit()
            print("plus: reset Accessibility for \(id) (\(reset.terminationStatus))")
        }
        prompt()
        NSWorkspace.shared.open(settingsURL)
    }

    /// One repair per launch from the + itself, so declining the prompt does
    /// not bring it back on every click. The settings row always repairs.
    private static var repairedThisLaunch = false

    // MARK: - The click

    public static func save(_ track: Track) {
        let fallback = { SpotifyLinks.open(.track, for: track) }
        switch route(enabled: enabled, trusted: AXIsProcessTrusted(),
                     repaired: repairedThisLaunch) {
        case .openSong: return fallback()
        // The prompt and the Accessibility pane are what the click shows.
        // Not the song as well: that would switch to Spotify's full-screen
        // Space and could bury the prompt.
        case .repair:
            repairedThisLaunch = true
            return repair()
        case .press: break
        }
        guard let spotify = NSRunningApplication.runningApplications(
                  withBundleIdentifier: bundleID).first,
              let url = spotify.bundleURL else { return fallback() }
        // Through LaunchServices, like the links: an accessory app asking
        // `activate()` of another app can be refused, and this also brings
        // back a window the user closed.
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        let pid = spotify.processIdentifier
        Task {
            let pressed = await Task.detached { press(pid: pid) }.value
            if let pressed { print("plus: pressed \"\(pressed)\"") } else {
                print("plus: Spotify's + not found, opening the song")
                fallback()
            }
        }
    }

    // MARK: - Pure, so a test can call them

    public enum Route: Equatable, Sendable { case press, openSong, repair }

    public nonisolated static func route(enabled: Bool, trusted: Bool, repaired: Bool) -> Route {
        guard enabled else { return .openSong }
        if trusted { return .press }
        return repaired ? .openSong : .repair
    }

    public nonisolated static func grant(enabled: Bool, trusted: Bool) -> MenuPanel.Grant {
        !enabled ? .off : trusted ? .on : .needsApproval
    }

    /// The now-playing bar starts at the first and its transport at the
    /// second; the + sits between them.
    nonisolated static let anchor = "Now playing view", transport = "Previous"
    /// Not saved, saved. Nothing else is ever pressed: after a redesign the
    /// buttons in that stretch could be anything at all.
    nonisolated static let accepted: Set<String> = ["Add to Liked Songs", "Add to playlist"]

    /// Which of Spotify's buttons, labels in document order, is its + for the
    /// playing song: the first known label between the anchor and the
    /// transport. **Between, not next**: on 23 Sep a "Lossless" badge
    /// appeared in front of it. Bounded by the transport so the page's own
    /// rows, which carry the same labels, can never match; no transport, no
    /// press, since that is a layout nobody has seen.
    public nonisolated static func target(in labels: [String]) -> Int? {
        guard let start = labels.firstIndex(of: anchor),
              let end = labels[start...].firstIndex(of: transport) else { return nil }
        return labels[start..<end].firstIndex(where: accepted.contains)
    }

    // MARK: - Accessibility, off the main thread (every call is IPC)

    nonisolated static let bundleID = "com.spotify.client"

    /// Polls, because Spotify arrives over a Space switch when it runs full
    /// screen -- until it is in front it shows Accessibility no windows at
    /// all (`docs/TRAPS.md` #49). Answers the label it pressed, or nil.
    private nonisolated static func press(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        // Chromium only builds its web-content tree when asked. It stays on
        // for the life of that Spotify process.
        // ponytail: never switched back off; costs Spotify a little until it quits.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let deadline = Date().addingTimeInterval(3)
        repeat {
            var buttons: [AXUIElement] = [], visited = 0
            collect(app, into: &buttons, visited: &visited, depth: 0)
            let labels = buttons.map(label)
            if let i = target(in: labels),
               AXUIElementPerformAction(buttons[i], kAXPressAction as CFString) == .success {
                return labels[i]
            }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        return nil
    }

    /// Spotify's whole window was ~2,700 elements when measured; the caps are
    /// there so a pathological tree cannot hang the click.
    private nonisolated static func collect(_ e: AXUIElement, into out: inout [AXUIElement],
                                            visited: inout Int, depth: Int) {
        visited += 1
        guard depth < 60, visited < 20_000 else { return }
        if string(e, kAXRoleAttribute) == kAXButtonRole { out.append(e) }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return }
        for child in children { collect(child, into: &out, visited: &visited, depth: depth + 1) }
    }

    /// Spotify puts a button's name in its description, not its title.
    private nonisolated static func label(_ e: AXUIElement) -> String {
        [string(e, kAXTitleAttribute), string(e, kAXDescriptionAttribute)]
            .filter { !$0.isEmpty }.joined(separator: " | ")
    }

    private nonisolated static func string(_ e: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
}
