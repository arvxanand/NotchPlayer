import Foundation

/// Which music app a track comes from, and everything about that app that
/// differs. `PlayerBridge` and `PlayerService` are one code path for both; this
/// is the data they read, so a new app is a new case here and not a new class.
///
/// Spotify's and Music's AppleScript dictionaries agree on the playback
/// vocabulary (`player position`, `player state`, `playpause`, `next track`,
/// `previous track`), so only what is spelled differently lives below. Music's
/// were read from `sdef /System/Applications/Music.app` (macOS 15.7.7).
public enum Source: Equatable, Sendable, CaseIterable {
    case spotify, appleMusic

    /// What the user knows it as.
    public var name: String { self == .spotify ? "Spotify" : "Apple Music" }

    public var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }

    /// What `tell application` takes.
    var appName: String { self == .spotify ? "Spotify" : "Music" }

    /// Distributed notifications that mean "the player changed". Spotify's
    /// carries the whole track. Music's payload is **not parsed**: it only
    /// triggers a read, so a key Apple renames costs nothing. Measured on macOS
    /// 15.7.7 (7 Oct 2026): pause and play each post it; a seek posts nothing.
    /// Music also posts the old `com.apple.iTunes.playerInfo` at the same
    /// instant with the same payload -- watching both reads twice per event.
    var notifications: [String] {
        [self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo"]
    }

    /// Whether the notification's `userInfo` is parsed (`Reading.from(notification:)`).
    var notificationCarriesTrack: Bool { self == .spotify }

    // MARK: - Scripts

    /// Nine fields, in the order `Reading.from(appleScript:)` expects. Music has
    /// no artwork URL (its cover is bytes, `coverScript`), so that field is empty,
    /// and its `duration` is seconds where the parser takes milliseconds.
    var readScript: String {
        switch self {
        case .spotify: """
            tell application "Spotify"
              set t to current track
              return {name of t, artist of t, album of t, album artist of t, \
            duration of t, artwork url of t, id of t, player position, player state as text}
            end tell
            """
        case .appleMusic: """
            tell application "Music"
              set t to current track
              return {name of t, artist of t, album of t, album artist of t, \
            (duration of t) * 1000, "", persistent ID of t, player position, player state as text}
            end tell
            """
        }
    }

    /// The cheap reconcile read: just the two things that drift.
    var positionScript: String {
        """
        tell application "\(appName)"
          return {player position, player state as text}
        end tell
        """
    }

    /// Shuffle, repeat, and whether they can be changed at all -- they cannot
    /// on Spotify's DJ, where a write silently does nothing. `shuffling
    /// enabled` and `repeating enabled` share the code `pReE`, so they are one
    /// value and one is read (`docs/TRAPS.md` #46). Music has no such lock.
    var modesScript: String {
        switch self {
        case .spotify: """
            tell application "Spotify"
              return {shuffling, repeating, shuffling enabled}
            end tell
            """
        case .appleMusic: """
            tell application "Music"
              return {shuffle enabled, song repeat is not off, true}
            end tell
            """
        }
    }

    /// Spotify only, and only on the notification path, which carries
    /// everything else: the cover's address.
    static let artworkScript = #"tell application "Spotify" to return artwork url of current track"#

    /// Music only: the first artwork's bytes. Music names no URL for a cover.
    static let coverScript = #"tell application "Music" to return raw data of artwork 1 of current track"#
}
