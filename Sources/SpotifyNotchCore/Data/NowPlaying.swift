import Foundation

/// What Spotify is playing. Duration is **seconds**, converted at the parsing
/// boundary -- both of Spotify's own surfaces report it in milliseconds while
/// its AppleScript dictionary describes the field as "the length of the track
/// in seconds", and mixing the two is a 1000x timing bug that looks like a
/// clock problem.
public struct Track: Equatable, Sendable {
    public let id: String
    public let name: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    /// Spotify says whether artwork exists; it does not always say where.
    public let hasArtwork: Bool
    /// Absent from the playback notification, present in an AppleScript read.
    /// So this is nil on the notification path until one Apple Event fills it
    /// in -- and stays nil forever if Automation is refused, which is a
    /// degraded display rather than a broken one.
    public var artworkURL: URL?

    public init(id: String, name: String, artist: String, album: String,
                duration: TimeInterval, hasArtwork: Bool, artworkURL: URL? = nil) {
        self.id = id; self.name = name; self.artist = artist; self.album = album
        self.duration = duration; self.hasArtwork = hasArtwork; self.artworkURL = artworkURL
    }
}

/// Spotify's own enum, decoded whole.
///
/// `isPlaying = state == "playing"` over a vendor's enum is a bug with a delay
/// fuse (matchnotch TRAPS #96): it is a `==` against one member of a set you
/// did not define, which assumes the set has two members. This one has three,
/// and two different spellings depending on which surface answers.
public enum PlayerState: String, CaseIterable, Sendable {
    case playing, paused, stopped

    /// AppleScript's `player state as text` answers `playing`; the
    /// notification's `Player State` answers `Playing`. Same enum, two
    /// vocabularies. **Unknown stays nil on purpose** -- an unhandled value
    /// must be visibly unhandled, not quietly `paused`.
    public init?(loose raw: String) {
        self.init(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/// The outcome of one read. `malformed` names what was missing, because
/// "nothing came back" and "nothing is there" are different answers and an
/// optional cannot tell them apart (TRAPS #92).
public enum Reading: Equatable, Sendable {
    case ok(Track, state: PlayerState, position: TimeInterval)
    case malformed(String)
}

/// What the app believes is happening. Four distinct answers, never collapsed
/// into "no music": each one draws something different, and `unknown` draws
/// whatever was already there.
public enum Now: Equatable, Sendable {
    /// Spotify is not launched.
    case notRunning
    /// Spotify is open with nothing loaded.
    case stopped
    case track(Track, state: PlayerState, position: TimeInterval)
    /// A read failed for a reason that is not "nothing is there". The service
    /// only ever publishes this before the *first* successful read; after
    /// that a failure leaves the last good value alone and retries.
    case unknown(String)

    public var track: Track? {
        if case let .track(t, _, _) = self { return t }
        return nil
    }
    public var isPlaying: Bool {
        if case let .track(_, state, _) = self { return state == .playing }
        return false
    }
    /// Whether the notch should draw anything at all.
    public var draws: Bool { track != nil }
}

/// Whether this app may talk to Spotify at all.
///
/// Deliberately separate from `Now`. The playback notification needs no
/// permission and carries everything except the artwork URL, so with Apple
/// Events refused the app still knows the track, the artist and the position
/// -- it just cannot fetch the cover or send a command. Folding that into
/// `Now` would force a choice between showing a permission error over a
/// perfectly readable track, and hiding the reason the buttons do nothing.
public enum Permission: Equatable, Sendable {
    case unknown, granted, denied
}

/// Advances the playback position locally between reads.
///
/// **On a `SuspendingClock`, not a `ContinuousClock`.** Spotify's own position
/// does not advance while the Mac is asleep, and a suspending clock does not
/// either, so the two agree across a lid-close with no correction. A
/// continuous clock counts the sleep and comes back wrong by exactly its
/// duration -- which is matchnotch TRAPS #91 arriving as a progress bar that
/// is an hour ahead.
public struct Interpolator: Equatable, Sendable {
    public let position: TimeInterval
    public let stamped: SuspendingClock.Instant
    public let advancing: Bool

    public init(position: TimeInterval, stamped: SuspendingClock.Instant, advancing: Bool) {
        self.position = position; self.stamped = stamped; self.advancing = advancing
    }

    /// The instant is a parameter rather than read inside, so this can be
    /// asserted at a chosen time instead of being timing-dependent.
    public func position(at now: SuspendingClock.Instant, duration: TimeInterval) -> TimeInterval {
        guard advancing else { return clamp(position, duration) }
        let elapsed = TimeInterval(stamped.duration(to: now).components.seconds)
            + Double(stamped.duration(to: now).components.attoseconds) / 1e18
        return clamp(position + max(0, elapsed), duration)
    }

    private func clamp(_ v: TimeInterval, _ duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return max(0, v) }
        return min(max(0, v), duration)
    }
}

// MARK: - Parsing

/// A value that may arrive as a number or as a string.
///
/// Not defensiveness for its own sake: the notification sends `Duration` as an
/// `NSNumber` and `Name` as an `NSString`, and one field arriving with more
/// than one type in the same payload is a documented trap (#78). A strict cast
/// does not fail partially -- it throws away the whole reading.
func loosely(number any: Any?) -> Double? {
    if let n = any as? NSNumber { return n.doubleValue }
    if let s = any as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
    return nil
}

func loosely(text any: Any?) -> String? {
    if let s = any as? String { return s }
    if let n = any as? NSNumber { return n.stringValue }
    return nil
}

func loosely(flag any: Any?) -> Bool? {
    if let n = any as? NSNumber { return n.boolValue }
    if let b = any as? Bool { return b }
    if let s = any as? String { return ["1", "true", "yes"].contains(s.lowercased()) }
    return nil
}

extension Reading {
    /// From `com.spotify.client.PlaybackStateChanged`'s `userInfo`.
    ///
    /// This is the cheap path and the main one: it needs no Apple Event, so no
    /// permission, no 3.3ms round trip, and no `osascript`. Everything the
    /// panel draws is here except the artwork URL.
    public static func from(notification info: [AnyHashable: Any]) -> Reading {
        guard let id = loosely(text: info["Track ID"]), !id.isEmpty else {
            return .malformed("Track ID")
        }
        guard let name = loosely(text: info["Name"]) else { return .malformed("Name") }
        guard let raw = loosely(text: info["Player State"]) else {
            return .malformed("Player State")
        }
        guard let state = PlayerState(loose: raw) else {
            return .malformed("Player State: unknown value \(raw.debugDescription)")
        }
        guard let ms = loosely(number: info["Duration"]) else { return .malformed("Duration") }
        guard let position = loosely(number: info["Playback Position"]) else {
            return .malformed("Playback Position")
        }
        let track = Track(id: id, name: name,
                          artist: loosely(text: info["Artist"]) ?? "",
                          album: loosely(text: info["Album"]) ?? "",
                          duration: ms / 1000,
                          hasArtwork: loosely(flag: info["Has Artwork"]) ?? false,
                          artworkURL: nil)
        return .ok(track, state: state, position: position)
    }

    /// From the nine-item AppleScript list. Order is fixed by
    /// `SpotifyBridge.readScript` and asserted by `fieldCount`.
    ///
    /// **A list, not a delimited string.** Building one with `& tab &` inside
    /// a `tell application` block silently produces nothing, because `tab`
    /// there is the *class name*, not the character (matchnotch TRAPS #1) --
    /// and a list also cannot be corrupted by a track title containing the
    /// separator.
    public static let fieldCount = 9

    public static func from(appleScript items: [String]) -> Reading {
        guard items.count == fieldCount else {
            return .malformed("expected \(fieldCount) fields, got \(items.count)")
        }
        guard !items[6].isEmpty else { return .malformed("id") }
        guard let state = PlayerState(loose: items[8]) else {
            return .malformed("player state: unknown value \(items[8].debugDescription)")
        }
        guard let ms = Double(items[4]) else { return .malformed("duration: \(items[4])") }
        guard let position = Double(items[7]) else { return .malformed("player position: \(items[7])") }
        let url = items[5].isEmpty ? nil : URL(string: items[5])
        let track = Track(id: items[6], name: items[0], artist: items[1], album: items[2],
                          duration: ms / 1000,
                          // No `Has Artwork` on this path; the URL is the
                          // better answer anyway -- it is what gets fetched.
                          hasArtwork: url != nil,
                          artworkURL: url)
        return .ok(track, state: state, position: position)
    }
}


/// What the notch should actually draw, resolved from the two things that
/// decide it.
///
/// **The whole point of this type is that it is a function, not a pile of
/// `if`s in a view body.** There are four distinct answers behind "nothing is
/// on screen" -- Spotify closed, Spotify open with nothing loaded, Automation
/// refused, and a read that did not come back -- and collapsing them produces
/// a UI that lies (matchnotch TRAPS #92). Resolving them here means the rule
/// can be *called* by a test rather than restated in one.
public enum Presentation: Equatable, Sendable {
    /// The notch looks like a notch.
    case nothing
    /// `controllable` is false when Apple Events are refused: the track, the
    /// artist and the position all still arrive over the notification, which
    /// needs no permission -- only the cover and the buttons are lost.
    case track(Track, playing: Bool, controllable: Bool)
    /// Something other than Spotify is making sound.
    ///
    /// All we can honestly know is which app it is. macOS stopped handing out
    /// titles for arbitrary audio when it gated MediaRemote behind a private
    /// entitlement in 15.4 -- verified on this machine, which answered with an
    /// empty dictionary while Spotify was playing (`docs/TRAPS.md`). So this
    /// case draws an icon, a name and a waveform, and does not pretend to a
    /// progress bar it cannot fill.
    case app(AudioSource)
    /// Spotify is running, we cannot talk to it, and we do not know what is
    /// playing. The only state that draws without music, because otherwise
    /// the app is silently dead and the user has no way to find out why.
    case permissionNeeded

    /// `source` is whatever is making sound, chosen by `AudioSources`.
    ///
    /// **Anything that is not Spotify wins while it is playing**, because it
    /// is the thing the user just started -- `AudioSources.chosen` has already
    /// applied the dwell, the exclusions and "most recent wins", so by the
    /// time it arrives here the answer is simply true. When it is Spotify, or
    /// when nothing is playing at all, the Spotify state below decides: a
    /// paused track still draws its panel, as it always has.
    public static func of(now: Now, permission: Permission,
                          source: AudioSource? = nil) -> Presentation {
        if let source, !source.isSpotify { return .app(source) }
        if let track = now.track {
            return .track(track, playing: now.isPlaying, controllable: permission != .denied)
        }
        // Only a *refusal* draws. A read that failed for some other reason
        // retries on its own clock, and a permanent error strip for a
        // transient failure would be worse than silence.
        //
        // `now` can only be `.unknown` here with Spotify running: `refresh`
        // answers `.notRunning` without sending an Apple Event at all, so a
        // denial cannot be reported for an app that is not open.
        if permission == .denied, case .unknown = now { return .permissionNeeded }
        return .nothing
    }

    public var draws: Bool { self != .nothing }
}
