import Foundation

/// Fixed states, so every branch the views can draw can be looked at without
/// waiting for real conditions.
///
/// A branch with no preview is a branch nobody has ever looked at.
public enum PreviewData {
    public struct State: Equatable, Sendable {
        public let name: String
        public let now: Now
        /// Fixed bar values, so a capture is identical run to run. Nil means
        /// "animate", which is right for looking at it and wrong for a check
        /// that compares pictures.
        public let bands: [Float]?
        /// What this state is for, shown by `--list-previews`. A state whose
        /// purpose has to be guessed gets dropped from the check list.
        public let caption: String
        /// Whether Apple Events are available. `.denied` is a whole second
        /// axis of rendering, not a variant of "no music".
        public var permission: Permission = .granted

        /// A stopped clock, so the panel's progress bar renders the same in
        /// every capture. `advancing: false` is what makes it reproducible.
        public var progress: Interpolator? {
            guard case let .track(_, _, position) = now else { return nil }
            return Interpolator(position: position, stamped: .now, advancing: false)
        }
    }

    static let cover = URL(string:
        "https://i.scdn.co/image/ab67616d0000b273e045aa197ada995407bf92fc")

    static func track(name: String = "D>E>A>T>H>M>E>T>A>L",
                      artist: String = "Panchiko",
                      artwork: URL? = cover) -> Track {
        Track(id: "spotify:track:4sIFi8LpJWPvI5xviWFyA6", name: name, artist: artist,
              album: "D>E>A>T>H>M>E>T>A>L", duration: 261.849,
              hasArtwork: artwork != nil, artworkURL: artwork)
    }

    /// Held bar values: a quiet passage and a loud one, so the extremes of the
    /// bar geometry are both looked at rather than only the middle.
    static let quiet = Bands.synthetic(at: 0.4).map { $0 * 0.18 }
    static let loud = Bands.synthetic(at: 2.1).map { min(1, $0 * 1.9) }

    /// **The one list.** `Tour` derives from it, the check script derives from
    /// it, and the coverage test asserts that property rather than a count
    /// somebody has to keep editing.
    public static let all: [State] = [
        State(name: "playing", now: .track(track(), state: .playing, position: 23.69),
              bands: nil, caption: "the ordinary case, bars animating"),
        State(name: "paused", now: .track(track(), state: .paused, position: 23.69),
              bands: nil, caption: "bars settled flat, cover at full strength"),
        State(name: "quiet", now: .track(track(), state: .playing, position: 23.69),
              bands: quiet, caption: "bars near their minimum -- the row-of-dots end"),
        State(name: "loud", now: .track(track(), state: .playing, position: 23.69),
              bands: loud, caption: "bars clipped at their maximum -- must not overflow the strip"),
        // The panel truncates rather than wrapping, because a title that wraps
        // changes the panel's height and a panel that resizes per track jumps
        // every time the song does. Preview data sized *to* a limit hides the
        // limit, so this one is comfortably past it.
        State(name: "longtitle",
              now: .track(track(name: "Everything In Its Right Place (Remastered "
                                    + "2016 Deluxe Anniversary Edition Bonus Track)",
                                artist: "Radiohead & A Very Long Collaborator Name"),
                          state: .playing, position: 23.69),
              bands: nil, caption: "title and artist both past the column -- must truncate, not wrap"),
        // Non-Latin script exercises the system font's fallback chain and,
        // for Arabic, right-to-left layout inside a left-aligned column.
        State(name: "nonlatin",
              now: .track(track(name: "夜に駆ける — ヨルシカ",
                                artist: "أم كلثوم"),
                          state: .playing, position: 23.69),
              bands: nil, caption: "CJK and Arabic -- font fallback and RTL"),
        State(name: "noart", now: .track(track(name: "Episode 412: The Long Way Round",
                                               artist: "Some Podcast", artwork: nil),
                                         state: .playing, position: 12.5),
              bands: nil, caption: "podcast or local file: the mark stands in for the cover"),
        // Automation refused, but a notification has already arrived -- so
        // the track, artist and position are all known and only the cover and
        // the buttons are missing. The panel says why instead of showing three
        // controls that swallow every press.
        State(name: "denied",
              now: .track(track(artwork: nil), state: .playing, position: 23.69),
              bands: nil,
              caption: "Automation refused mid-track: readable, not controllable",
              permission: .denied),
        // Automation refused and nothing has played since launch, so nothing
        // is known at all. The one state that draws without music -- otherwise
        // the app is silently dead and the user cannot find out why.
        State(name: "nopermission",
              now: .unknown("Automation permission refused (-1743)"), bands: nil,
              caption: "Automation refused at launch: the only no-music state that draws",
              permission: .denied),
        State(name: "stopped", now: .stopped, bands: nil,
              caption: "Spotify open, nothing loaded -- draws nothing"),
        State(name: "notrunning", now: .notRunning, bands: nil,
              caption: "Spotify not launched -- draws nothing"),
    ]

    /// Nil for an unknown name, on purpose.
    ///
    /// matchnotch's equivalent falls through to `default: .idle`, so a typo'd
    /// state renders a blank notch and looks like a bug in the app rather than
    /// a bug in the command line. Failing loudly costs one `guard`.
    public static func named(_ name: String) -> State? {
        all.first { $0.name == name }
    }

    public static var names: [String] { all.map(\.name) }

    /// The states that draw something, which is the set the footprint check
    /// can run against. The ones that draw nothing would capture the desktop
    /// through a transparent window and fail by construction.
    ///
    /// **Asks `Presentation`, not `Now`.** `nopermission` has no track at all
    /// and still draws, which is the whole point of that state -- keying this
    /// off `now.draws` would have quietly excluded it from every check.
    public static var drawing: [State] {
        all.filter { Presentation.of(now: $0.now, permission: $0.permission).draws }
    }

    /// What `tools/check_notch.sh` captures: every drawing state collapsed,
    /// **and every one of them expanded**.
    ///
    /// The expanded panel is 100pt taller and draws real text, so "nothing
    /// legible behind the camera housing" is a different claim about it than
    /// about the peek -- and it is the one a long title would break first.
    public static var checkSpecs: [String] {
        drawing.map { "--preview \($0.name)" }
            + drawing.map { "--preview \($0.name) --expanded" }
    }
}
