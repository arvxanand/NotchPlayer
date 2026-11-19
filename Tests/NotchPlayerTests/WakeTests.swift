import XCTest
@testable import NotchPlayerCore

/// The notch while the music app is closed: its last song, paused, one press
/// from playing (`LastPlayed`, `QuietLaunch`).
final class WakeTests: XCTestCase {
    private let song = Track(id: "spotify:track:abc", name: "Bulletproof", artist: "La Roux",
                             album: "Bulletproof", duration: 205, hasArtwork: true,
                             artworkURL: URL(string: "https://i.scdn.co/image/ab67616d0000b273aa"))

    /// Closed with a last song: drawn, paused, with working buttons.
    func testAClosedAppShowsItsLastSongPaused() {
        XCTAssertEqual(Presentation.of(now: .notRunning, permission: .granted, last: song),
                       .track(song, playing: false, controllable: true))
        XCTAssertEqual(Presentation.of(now: .notRunning, permission: .granted, last: song, waking: true),
                       .track(song, playing: true, controllable: true), "a press is starting it")
    }

    /// Only while it is closed: open with nothing loaded, or no song saved,
    /// still draws nothing; a playing song always wins.
    func testTheLastSongOnlyStandsInWhileClosed() {
        XCTAssertEqual(Presentation.of(now: .notRunning, permission: .granted, last: nil), .nothing)
        XCTAssertEqual(Presentation.of(now: .stopped, permission: .granted, last: song), .nothing)
        let other = Track(id: "spotify:track:xyz", name: "Other", artist: "Someone", album: "",
                          duration: 100, hasArtwork: false)
        XCTAssertEqual(Presentation.of(now: .track(other, state: .playing, position: 3), permission: .granted,
                                       last: song),
                       .track(other, playing: true, controllable: true))
    }

    /// Kept per app, across restarts; ads are never kept.
    func testTheLastSongIsKeptPerAppButNeverAnAd() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WakeTests-\(UUID().uuidString)"))
        LastPlayed.save(song, defaults: defaults)
        XCTAssertEqual(LastPlayed.load(.spotify, defaults: defaults), song)
        XCTAssertNil(LastPlayed.load(.appleMusic, defaults: defaults))
        let ad = Track(id: "spotify:ad:123", name: "Advertisement", artist: "", album: "",
                       duration: 30, hasArtwork: false)
        LastPlayed.save(ad, defaults: defaults)
        XCTAssertEqual(LastPlayed.load(.spotify, defaults: defaults), song, "the ad did not replace it")
        LastPlayed.setLastSource(.appleMusic, defaults: defaults)
        XCTAssertEqual(LastPlayed.lastSource(defaults: defaults), .appleMusic)
    }

    /// Focus goes back only once the app has held it 0.45s (TRAPS #75).
    func testFocusIsHandedBackOnlyAfterTheAppHasSettled() {
        let start = Date()
        XCTAssertFalse(QuietLaunch.shouldHandBack(activatedAt: nil, now: start))
        XCTAssertFalse(QuietLaunch.shouldHandBack(activatedAt: start, now: start.addingTimeInterval(0.3)))
        XCTAssertTrue(QuietLaunch.shouldHandBack(activatedAt: start, now: start.addingTimeInterval(0.45)))
    }

    /// `play`, not the toggle: a toggle landing on an app still loading
    /// could pause it.
    func testAWokenAppIsToldToPlayNotToToggle() {
        XCTAssertEqual(Command.play.script(for: .spotify), #"tell application "Spotify" to play"#)
        XCTAssertEqual(Command.play.script(for: .appleMusic), #"tell application "Music" to play"#)
    }
}
