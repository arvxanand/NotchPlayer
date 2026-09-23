import XCTest
@testable import SpotifyNotchCore

private func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")
    return try! Data(contentsOf: XCTUnwrap(url))
}

private func dictionary(_ name: String) -> [AnyHashable: Any] {
    try! JSONSerialization.jsonObject(with: fixture(name)) as! [AnyHashable: Any]
}

private func list(_ name: String) -> [String] {
    try! JSONSerialization.jsonObject(with: fixture(name)) as! [String]
}

final class NotificationParsingTests: XCTestCase {
    func testTheRealPlayingPayloadParses() {
        guard case let .ok(track, state, position) =
                Reading.from(notification: dictionary("notification-playing")) else {
            return XCTFail("real captured payload did not parse")
        }
        XCTAssertEqual(state, .playing)
        XCTAssertEqual(track.name, "D>E>A>T>H>M>E>T>A>L")
        XCTAssertEqual(track.artist, "Panchiko")
        XCTAssertEqual(track.id, "spotify:track:4sIFi8LpJWPvI5xviWFyA6")
        XCTAssertEqual(position, 23.69, accuracy: 0.001)
        XCTAssertTrue(track.hasArtwork)
        // **The one-line 1000x bug.** Spotify reports 261849 and its own
        // dictionary calls the field seconds. It is milliseconds.
        XCTAssertEqual(track.duration, 261.849, accuracy: 0.0005)
        XCTAssertLessThan(track.duration, 600, "a 4-minute track cannot be 261849 seconds")
        // The notification never carries the URL, only the flag.
        XCTAssertNil(track.artworkURL)
    }

    func testTheNotificationSpellsThePlayerStateWithACapital() {
        // AppleScript answers `playing`; the notification answers `Playing`.
        // Two vocabularies for one enum, and a `==` against either spelling
        // is wrong half the time.
        guard case let .ok(_, state, _) =
                Reading.from(notification: dictionary("notification-paused")) else {
            return XCTFail("captured pause payload did not parse")
        }
        XCTAssertEqual(state, .paused)
    }

    func testNumericFieldsAreAcceptedAsStringsToo() {
        // One field can send more than one type in the same payload, and a
        // strict cast does not fail partially -- it discards the whole read.
        guard case let .ok(track, state, position) =
                Reading.from(notification: dictionary("notification-stringly-typed")) else {
            return XCTFail("stringly-typed payload did not parse")
        }
        XCTAssertEqual(state, .playing)
        XCTAssertEqual(track.duration, 261.849, accuracy: 0.0005)
        XCTAssertEqual(position, 23.69, accuracy: 0.001)
        XCTAssertTrue(track.hasArtwork)
    }

    func testAMissingFieldNamesItselfRatherThanReturningNil() {
        // "Nothing came back" and "nothing is there" are different answers.
        var info = dictionary("notification-playing")
        info["Track ID"] = nil
        XCTAssertEqual(Reading.from(notification: info), .malformed("Track ID"))
        info = dictionary("notification-playing")
        info["Duration"] = nil
        XCTAssertEqual(Reading.from(notification: info), .malformed("Duration"))
    }

    func testAnUnknownPlayerStateIsVisiblyUnhandled() {
        // Spotify's enum has three members today. A fourth must not silently
        // become `paused` -- it must show up as a malformed read and say what
        // the value was.
        var info = dictionary("notification-playing")
        info["Player State"] = "Buffering"
        guard case let .malformed(what) = Reading.from(notification: info) else {
            return XCTFail("an unknown player state parsed as something")
        }
        XCTAssertTrue(what.contains("Buffering"), "the reason should name the value: \(what)")
    }
}

final class AppleScriptParsingTests: XCTestCase {
    func testTheRealNineItemListParses() {
        guard case let .ok(track, state, position) =
                Reading.from(appleScript: list("applescript-read")) else {
            return XCTFail("real captured list did not parse")
        }
        XCTAssertEqual(state, .paused)
        XCTAssertEqual(track.artist, "Panchiko")
        XCTAssertEqual(track.duration, 261.849, accuracy: 0.0005)
        XCTAssertEqual(position, 23.69, accuracy: 0.001)
        XCTAssertEqual(track.artworkURL?.host, "i.scdn.co")
        XCTAssertTrue(track.hasArtwork)
    }

    func testTheFieldOrderIsPinnedToTheScriptThatProducesIt() {
        // If the script grows a field, this is what notices. The count is
        // read from the script rather than written out twice.
        let returns = SpotifyBridge.readScript
            .components(separatedBy: "return {")[1]
            .components(separatedBy: "}")[0]
        XCTAssertEqual(returns.components(separatedBy: ",").count, Reading.fieldCount)
    }

    func testAShortListIsMalformedAndSaysSo() {
        guard case let .malformed(what) = Reading.from(appleScript: ["one", "two"]) else {
            return XCTFail("a two-item list parsed")
        }
        XCTAssertTrue(what.contains("\(Reading.fieldCount)"))
    }

    /// Provenance note: this fixture is CONSTRUCTED, not captured -- no
    /// podcast has been played through the app. It asserts the branch exists
    /// and degrades, which is worth having; it is not evidence about what
    /// Spotify really sends.
    func testATrackWithNoArtworkStillParses() {
        guard case let .ok(track, state, _) =
                Reading.from(appleScript: list("applescript-no-artwork.CONSTRUCTED")) else {
            return XCTFail("a track with no artwork did not parse")
        }
        XCTAssertEqual(state, .playing)
        XCTAssertNil(track.artworkURL)
        XCTAssertFalse(track.hasArtwork)
        XCTAssertEqual(track.duration, 3480, accuracy: 0.5)
        // The name is still there, which is the whole point: no cover is a
        // placeholder, not an empty panel.
        XCTAssertFalse(track.name.isEmpty)
    }
}

final class PlayerStateTests: XCTestCase {
    func testBothSpellingsOfEveryMemberDecode() {
        for state in PlayerState.allCases {
            XCTAssertEqual(PlayerState(loose: state.rawValue), state)
            XCTAssertEqual(PlayerState(loose: state.rawValue.capitalized), state)
            XCTAssertEqual(PlayerState(loose: " \(state.rawValue.uppercased()) "), state)
        }
    }

    func testAnUnknownSpellingIsNil() {
        XCTAssertNil(PlayerState(loose: "buffering"))
        XCTAssertNil(PlayerState(loose: ""))
    }
}

final class InterpolatorTests: XCTestCase {
    func testAPausedTrackDoesNotAdvance() {
        let start = SuspendingClock.now
        let i = Interpolator(position: 30, stamped: start, advancing: false)
        XCTAssertEqual(i.position(at: start.advanced(by: .seconds(90)), duration: 200), 30)
    }

    func testAPlayingTrackAdvancesWithTheClock() {
        let start = SuspendingClock.now
        let i = Interpolator(position: 30, stamped: start, advancing: true)
        XCTAssertEqual(i.position(at: start.advanced(by: .seconds(12)), duration: 200),
                       42, accuracy: 0.001)
        XCTAssertEqual(i.position(at: start.advanced(by: .milliseconds(1500)), duration: 200),
                       31.5, accuracy: 0.001)
    }

    func testItNeverRunsPastTheEndOfTheTrack() {
        // A stale stamp -- the reconcile tick missed, or Spotify stopped
        // without saying so -- must not draw a bar past 100%.
        let start = SuspendingClock.now
        let i = Interpolator(position: 190, stamped: start, advancing: true)
        XCTAssertEqual(i.position(at: start.advanced(by: .seconds(600)), duration: 200), 200)
    }

    func testItNeverGoesNegativeAndSurvivesAnUnknownDuration() {
        let start = SuspendingClock.now
        XCTAssertEqual(Interpolator(position: -5, stamped: start, advancing: false)
            .position(at: start, duration: 200), 0)
        // duration 0 means "we do not know how long this is", which must not
        // clamp everything to zero.
        XCTAssertEqual(Interpolator(position: 30, stamped: start, advancing: true)
            .position(at: start.advanced(by: .seconds(5)), duration: 0), 35, accuracy: 0.001)
    }
}

final class BridgeFailureTests: XCTestCase {
    private func error(_ code: Int) -> NSDictionary {
        [NSAppleScript.errorNumber: code, NSAppleScript.errorMessage: "code \(code)"]
    }

    /// Four outcomes, each meaning something different on screen. Collapsing
    /// them into "no music" produces a UI that lies.
    func testEveryErrorCodeMapsToItsOwnAnswer() {
        XCTAssertEqual(SpotifyBridge.failure(from: error(-1743)), .denied)
        XCTAssertEqual(SpotifyBridge.failure(from: error(-600)), .notRunning)
        XCTAssertEqual(SpotifyBridge.failure(from: error(-609)), .notRunning)
        XCTAssertEqual(SpotifyBridge.failure(from: error(-1728)), .noTrack)
        XCTAssertEqual(SpotifyBridge.failure(from: error(-42)), .other(-42, "code -42"))
    }

    func testPermissionDeniedIsNotTheSameAsNoMusic() {
        XCTAssertNotEqual(SpotifyBridge.failure(from: error(-1743)),
                          SpotifyBridge.failure(from: error(-1728)))
    }

    func testNoCommandActivatesSpotify() {
        // Bringing Spotify forward to talk to it clobbers whatever the user
        // was doing, and is never necessary.
        for command in SpotifyBridge.Command.simple + [.seek(42), .shuffle(true), .repeating(true)] {
            XCTAssertFalse(command.source.contains("activate"), "\(command) activates Spotify")
        }
    }
}

final class NowTests: XCTestCase {
    private let track = Track(id: "x", name: "n", artist: "a", album: "b",
                              duration: 100, hasArtwork: false)

    func testOnlyATrackDrawsAnything() {
        XCTAssertTrue(Now.track(track, state: .paused, position: 0).draws)
        XCTAssertFalse(Now.notRunning.draws)
        XCTAssertFalse(Now.stopped.draws)
        XCTAssertFalse(Now.unknown("x").draws)
    }

    func testPausedIsNotPlaying() {
        XCTAssertTrue(Now.track(track, state: .playing, position: 0).isPlaying)
        XCTAssertFalse(Now.track(track, state: .paused, position: 0).isPlaying)
        XCTAssertFalse(Now.track(track, state: .stopped, position: 0).isPlaying)
    }

    func testTheFourNonPlayingAnswersAreAllDistinct() {
        let all: [Now] = [.notRunning, .stopped, .unknown("read failed"),
                          .track(track, state: .paused, position: 0)]
        for (i, a) in all.enumerated() {
            for (j, b) in all.enumerated() where i != j { XCTAssertNotEqual(a, b) }
        }
    }
}

final class ClockTests: XCTestCase {
    func testTheOrdinaryCases() {
        XCTAssertEqual(Clock.mmss(0), "0:00")
        XCTAssertEqual(Clock.mmss(23.69), "0:23")
        XCTAssertEqual(Clock.mmss(59), "0:59")
        XCTAssertEqual(Clock.mmss(60), "1:00")
        XCTAssertEqual(Clock.mmss(261.849), "4:21")
    }

    func testItRoundsDownRatherThanToNearest() {
        // A clock showing 0:01 before a second has passed is wrong in the
        // direction people notice.
        XCTAssertEqual(Clock.mmss(0.9), "0:00")
        XCTAssertEqual(Clock.mmss(59.99), "0:59")
    }

    func testPastAnHourItGrowsAField() {
        // Podcasts and DJ sets are routinely longer than an hour; 73:20 is not
        // a time anybody reads.
        XCTAssertEqual(Clock.mmss(3600), "1:00:00")
        XCTAssertEqual(Clock.mmss(4400), "1:13:20")
    }

    func testRemainingCarriesItsSignAndNeverGoesPositive() {
        XCTAssertEqual(Clock.remaining(position: 23.69, duration: 261.849), "-3:58")
        XCTAssertEqual(Clock.remaining(position: 0, duration: 60), "-1:00")
        // At the end it reads 0:00, not -0:00 -- a signed zero is not a
        // time. A stale stamp past the end clamps to the same thing rather
        // than counting up.
        XCTAssertEqual(Clock.remaining(position: 261.849, duration: 261.849), "0:00")
        XCTAssertEqual(Clock.remaining(position: 300, duration: 261.849), "0:00")
        // And the sign is there for every real remaining time.
        XCTAssertEqual(Clock.remaining(position: 260.9, duration: 261.849), "0:00")
        XCTAssertEqual(Clock.remaining(position: 259, duration: 261.849), "-0:02")
        XCTAssertTrue(Clock.remaining(position: 1, duration: 261.849).hasPrefix("-"))
    }

    func testAnUnknownDurationSaysSoRatherThanLying() {
        XCTAssertEqual(Clock.remaining(position: 10, duration: 0), "--:--")
        XCTAssertEqual(Clock.mmss(.infinity), "--:--")
        XCTAssertEqual(Clock.mmss(.nan), "--:--")
    }

    /// Digits that change width as they tick make the clock jitter once a
    /// second, forever. The font is the fix and this is the reminder.
    func testTheClockFaceIsMonospacedDigit() {
        XCTAssertEqual(String(describing: Type.clock()),
                       String(describing: Type.clock()))
    }
}

final class ProgressLineTests: XCTestCase {
    func testTheFillTracksTheFraction() {
        XCTAssertEqual(ProgressLine.filled(0, in: 200), 0)
        XCTAssertEqual(ProgressLine.filled(0.5, in: 200), 100)
        XCTAssertEqual(ProgressLine.filled(1, in: 200), 200)
    }

    func testItNeverDrawsOutsideItsTrack() {
        // A stale interpolator or a zero duration must not produce a negative
        // frame, which SwiftUI turns into a runtime complaint, nor a bar wider
        // than the track it sits in.
        XCTAssertEqual(ProgressLine.filled(-3, in: 200), 0)
        XCTAssertEqual(ProgressLine.filled(9, in: 200), 200)
        XCTAssertEqual(ProgressLine.filled(.nan, in: 200), 0)
        XCTAssertEqual(ProgressLine.filled(0.5, in: 0), 0)
        XCTAssertEqual(ProgressLine.filled(0.5, in: -10), 0)
    }
}
