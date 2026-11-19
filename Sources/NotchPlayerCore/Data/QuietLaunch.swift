import AppKit

/// Starts a music app without it taking over the screen.
///
/// **Asking for a hidden launch is not enough.** Measured 18 Nov 2026,
/// Spotify 1.3.10: `open -g -j` (and `OpenConfiguration` with `activates`
/// off, `hides` on) still put Spotify in front with its window open. What
/// works is watching it as it starts and hiding it the moment it is active or
/// shows a window: the window was up for ~0.1s, then stayed hidden, and the
/// app that was in front got focus back. If it has not after 0.45s, it is
/// handed back by opening it -- `activate()` from this app is refused, and
/// earlier than 0.45s Spotify takes the front again (TRAPS #75).
///
/// Watches for a few seconds only, at 20 checks a second, then stops.
@MainActor
enum QuietLaunch {
    nonisolated static let handBackAfter: TimeInterval = 0.45
    /// Long enough for a cold launch; the watch stops here whatever happens.
    static let watchFor: TimeInterval = 8
    /// Windows can still appear a moment after the app says it is ready.
    static let settleAfterReady: TimeInterval = 3

    /// `ready` runs once, when the app has finished launching.
    static func open(_ source: Source, ready: @escaping @MainActor () -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        // Where focus goes back to: the app in front, unless that is this one.
        let back = NSWorkspace.shared.frontmostApplication
            .flatMap { $0.bundleIdentifier == source.bundleID ? nil : $0.bundleURL }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }

        let start = Date()
        var activated: Date?, readyAt: Date?, handedBack = false
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            MainActor.assumeIsolated {
                let now = Date()
                let done = now.timeIntervalSince(start) > watchFor
                    || readyAt.map { now.timeIntervalSince($0) > settleAfterReady } == true
                if done { timer.invalidate(); return }
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).first
                else { return }
                if app.isActive { activated = activated ?? now }
                if app.isActive || hasWindow(app.processIdentifier) { app.hide() }
                if !handedBack, let back, shouldHandBack(activatedAt: activated, now: now),
                   NSWorkspace.shared.frontmostApplication?.bundleIdentifier == source.bundleID {
                    handedBack = true
                    NSWorkspace.shared.openApplication(at: back, configuration: .init()) { _, _ in }
                }
                if readyAt == nil, app.isFinishedLaunching {
                    readyAt = now
                    ready()
                }
            }
        }
    }

    /// Hand focus back only once the app has held it for `handBackAfter`.
    nonisolated static func shouldHandBack(activatedAt: Date?, now: Date) -> Bool {
        guard let activatedAt else { return false }
        return now.timeIntervalSince(activatedAt) >= handBackAfter
    }

    /// An ordinary window of `pid` on screen.
    private static func hasWindow(_ pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }
}
