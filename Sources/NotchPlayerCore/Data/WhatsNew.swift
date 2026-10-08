import Foundation

/// A short note of what changed, shown once in the notch after an update.
///
/// **Written here, not fetched.** GitHub's generated release notes are a list
/// of pull requests ("apple music support by @arvxanand in #23"), and a
/// Homebrew or fresh-download update never sees the in-app updater anyway. So
/// each version's lines live in the app, in plain words, and the GitHub
/// release uses the same text.
///
/// Shown when the app starts as a version it has not shown notes for. A fresh
/// install shows nothing: there is nothing it missed.
public enum WhatsNew {
    public struct Note: Equatable, Sendable {
        public let version: String
        public let lines: [String]
    }

    /// Short enough for one line each in the panel (`WhatsNewTests`).
    static let notes: [String: [String]] = [
        "0.6": [
            "Listening stats: swipe left on the open notch",
            "Stats take the colour of the album cover",
            "Covers for songs streamed from Apple Music",
        ],
    ]

    static let seenKey = "whatsNewSeen"

    /// What to show at launch, if anything. `ranBefore` tells an update from
    /// a fresh install when `seen` is missing: v0.5 and older never wrote it.
    static func pending(current: String, seen: String?, ranBefore: Bool) -> Note? {
        guard seen != current, seen != nil || ranBefore, let lines = notes[current] else { return nil }
        return Note(version: current, lines: lines)
    }

    /// Read once, first thing at launch: the cover cache's folder is made the
    /// first time any version runs, so it has to be looked at before this
    /// launch makes it.
    @MainActor static func atLaunch(current: String,
                                    defaults: UserDefaults = .standard) -> Note? {
        let ranBefore = FileManager.default.fileExists(atPath: ArtworkCache.directory.path)
        let note = pending(current: current, seen: defaults.string(forKey: seenKey), ranBefore: ranBefore)
        // Nothing to show is as good as shown, so a fresh install starts seen.
        if note == nil { defaults.set(current, forKey: seenKey) }
        return note
    }

    static func seen(_ version: String, defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: seenKey)
    }
}
