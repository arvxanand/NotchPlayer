import AppKit
import ApplicationServices

/// The panel's +: saving the playing song.
///
/// **Spotify's dictionary cannot save a song, and the Web API needs a
/// developer app capped at five users** -- so the + presses Spotify's *own* +
/// through Accessibility, the channel VoiceOver uses. **It always ends in a
/// playlist list, never a silent like.** A saved song's + opens Spotify's
/// picker, so that one is pressed. An unsaved song's + would only add it to
/// Liked Songs (24 Sep 2026: the owner's click did exactly that, with no
/// picker), so it is left alone and the song title's right-click menu opens
/// instead, at its "Add to playlist" list. Which button: `target(in:)`;
/// which way: `step(for:)`.
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

    nonisolated static let unsaved = "Add to Liked Songs", addToPlaylist = "Add to playlist"
    /// Not in the SDK's role constants; what Spotify's song and artist names report.
    nonisolated static let linkRole = "AXLink"

    public enum Step: Equatable, Sendable { case pressPlus, openMenu }

    /// Spotify's + on an unsaved song likes it and shows no picker, so that
    /// one is never pressed.
    public nonisolated static func step(for plusLabel: String) -> Step {
        plusLabel == unsaved ? .openMenu : .pressPlus
    }

    /// The playing song's title: the first link in the now-playing bar,
    /// before the artists. Buttons and links in document order.
    public nonisolated static func titleLink(in items: [(role: String, label: String)]) -> Int? {
        guard let start = items.firstIndex(where: { $0.role == kAXButtonRole && $0.label == anchor }),
              let end = items[start...].firstIndex(where: { $0.role == kAXButtonRole && $0.label == transport })
        else { return nil }
        return items[start..<end].firstIndex { $0.role == linkRole }
    }

    // MARK: - Accessibility, off the main thread (every call is IPC)

    nonisolated static let bundleID = "com.spotify.client"

    /// Polls, because Spotify arrives over a Space switch when it runs full
    /// screen -- until it is in front it shows Accessibility no windows at
    /// all (`docs/TRAPS.md` #49). Answers the label it pressed, or nil.
    /// `pressing: false` (`--find-plus`) never presses Spotify's +; the
    /// menu, which adds nothing, still opens.
    private nonisolated static func press(pid: pid_t, pressing: Bool = true) -> String? {
        let app = AXUIElementCreateApplication(pid)
        let started = Date(), deadline = started.addingTimeInterval(3)
        var seen = "", set: [Int32] = []
        repeat {
            // Chromium only builds its web-content tree when asked, and
            // Spotify 1.3.0 only hears **AXEnhancedUserInterface**
            // (AXManualAccessibility answers -25205, unsupported). **Asked on
            // every poll, not once**: asked while Spotify is still on its
            // full-screen Space, it keeps the flag and builds nothing, even
            // once it is in front (`docs/TRAPS.md` #68). The one that works
            // still answers -25208, so the result is only logged.
            // ponytail: never switched back off; costs Spotify a little until it quits.
            set = ["AXEnhancedUserInterface", "AXManualAccessibility"].map {
                AXUIElementSetAttributeValue(app, $0 as CFString, kCFBooleanTrue).rawValue
            }
            var found: [AXUIElement] = [], visited = 0
            collect(app, roles: [kAXButtonRole, linkRole], into: &found, visited: &visited, depth: 0)
            let items = found.map { (role: string($0, kAXRoleAttribute), label: label($0)) }
            let buttons = items.indices.filter { items[$0].role == kAXButtonRole }
            seen = "\(visited) elements, \(buttons.count) buttons, anchor "
                + (items.contains { $0.label == anchor } ? "found" : "missing")
            if let b = target(in: buttons.map { items[$0].label }) {
                let plus = buttons[b], name = items[plus].label
                print(String(format: "plus: found \"%@\" after %.2fs", name, Date().timeIntervalSince(started)))
                switch step(for: name) {
                case .pressPlus:
                    guard pressing else { return "would press \(name)" }
                    return AXUIElementPerformAction(found[plus], kAXPressAction as CFString) == .success
                        ? name : nil
                case .openMenu:
                    guard let title = titleLink(in: items) else {
                        print("plus: no song title in the bar"); return nil
                    }
                    return openAddToPlaylist(app: app, title: found[title]) ? "\(addToPlaylist) menu" : nil
                }
            }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        // What it saw, so a failure in the field says which step failed.
        print("plus: gave up after 3s: \(seen); windows \(count(app, kAXWindowsAttribute)); set \(set)")
        return nil
    }

    private nonisolated static func count(_ e: AXUIElement, _ attribute: String) -> Int {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(e, attribute as CFString, &value)
        return (value as? [AXUIElement])?.count ?? -1
    }

    /// `--find-plus`: the click's whole path, run from a launch of this very
    /// bundle (so it has this build's permission), without pressing
    /// Spotify's +. On an unsaved song it does open the playlist list.
    public nonisolated static func findProbe() {
        guard let spotify = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let url = spotify.bundleURL else { return print("plus: Spotify isn't running") }
        print("plus: trusted \(AXIsProcessTrusted())")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        print("plus: result \(press(pid: spotify.processIdentifier, pressing: false) ?? "nothing")")
    }

    /// The title's right-click menu, then its "Add to playlist" item, which
    /// opens the list of playlists beside it. Pressing that item only opens
    /// the list: nothing is added until the user picks a playlist. Measured
    /// 24 Sep 2026, Spotify 1.3.0.277: the menu is web content in the window,
    /// up within 0.7s.
    private nonisolated static func openAddToPlaylist(app: AXUIElement, title: AXUIElement) -> Bool {
        // A menu left open by an earlier click, even for an earlier song,
        // stays open while Spotify is in the background, and asking for the
        // title's menu then **closes** it (measured 24 Sep 2026: open, closed,
        // open on three asks). So close it first and never press its item.
        if menuItem(in: app) != nil {
            _ = AXUIElementPerformAction(title, kAXShowMenuAction as CFString)
            let closing = Date().addingTimeInterval(1)
            while menuItem(in: app) != nil, Date() < closing { Thread.sleep(forTimeInterval: 0.1) }
        }
        let shown = AXUIElementPerformAction(title, kAXShowMenuAction as CFString)
        guard shown == .success else { print("plus: title menu refused (\(shown.rawValue))"); return false }
        let deadline = Date().addingTimeInterval(2)
        repeat {
            Thread.sleep(forTimeInterval: 0.1)
            if let item = menuItem(in: app) {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
        } while Date() < deadline
        print("plus: no \"\(addToPlaylist)\" in the title's menu after 2s")
        return false
    }

    private nonisolated static func menuItem(in app: AXUIElement) -> AXUIElement? {
        var items: [AXUIElement] = [], visited = 0
        collect(app, roles: [kAXMenuItemRole], into: &items, visited: &visited, depth: 0)
        return items.first { label($0) == addToPlaylist }
    }

    /// Spotify's whole window was ~2,700 elements when measured; the caps are
    /// there so a pathological tree cannot hang the click.
    /// Skips the menu bar: nothing we press lives there, and Spotify's own
    /// menus must never be mistaken for the one the title opens.
    private nonisolated static func collect(_ e: AXUIElement, roles: Set<String>,
                                            into out: inout [AXUIElement],
                                            visited: inout Int, depth: Int) {
        visited += 1
        guard depth < 60, visited < 20_000 else { return }
        let role = string(e, kAXRoleAttribute)
        guard role != kAXMenuBarRole else { return }
        if roles.contains(role) { out.append(e) }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return }
        for child in children {
            collect(child, roles: roles, into: &out, visited: &visited, depth: depth + 1)
        }
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
