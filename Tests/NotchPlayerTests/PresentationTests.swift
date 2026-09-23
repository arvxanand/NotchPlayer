import XCTest
@testable import NotchPlayerCore

private let track = Track(id: "x", name: "n", artist: "a", album: "b",
                          duration: 100, hasArtwork: false)

final class PresentationTests: XCTestCase {
    /// Every combination, because the whole reason this is a function is that
    /// the four ways of having nothing to show are different answers.
    func testTheFullMatrix() {
        let states: [Now] = [.notRunning, .stopped, .unknown("read failed"),
                             .track(track, state: .playing, position: 0)]
        var seen: [String: Presentation] = [:]
        for now in states {
            for permission in [Permission.unknown, .granted, .denied] {
                seen["\(now)|\(permission)"] = .of(now: now, permission: permission)
            }
        }
        // A track always draws, whatever the permission -- the notification
        // needs none, so the panel is readable either way.
        for permission in [Permission.unknown, .granted, .denied] {
            let p = Presentation.of(now: .track(track, state: .playing, position: 0),
                                    permission: permission)
            XCTAssertTrue(p.draws, "a known track must draw under \(permission)")
        }
        XCTAssertEqual(seen.values.filter { $0 == .permissionNeeded }.count, 1,
                       "exactly one combination should ask for permission")
    }

    func testOnlyARefusalWithNothingKnownAsksForPermission() {
        XCTAssertEqual(Presentation.of(now: .unknown("refused"), permission: .denied),
                       .permissionNeeded)
        // A read that failed for some other reason retries on its own clock.
        // A permanent error strip for a transient failure is worse than
        // silence.
        XCTAssertEqual(Presentation.of(now: .unknown("timeout"), permission: .granted),
                       .nothing)
        XCTAssertEqual(Presentation.of(now: .unknown("timeout"), permission: .unknown),
                       .nothing)
    }

    func testSpotifyBeingClosedNeverAsksForPermission() {
        // `refresh` answers `.notRunning` without sending an Apple Event, so a
        // denial cannot be reported for an app that is not open. Nagging about
        // Automation while Spotify is quit would be nagging about nothing.
        XCTAssertEqual(Presentation.of(now: .notRunning, permission: .denied), .nothing)
        XCTAssertEqual(Presentation.of(now: .stopped, permission: .denied), .nothing)
    }

    func testARefusalCostsTheButtonsAndNothingElse() {
        guard case let .track(_, _, controllable) =
                Presentation.of(now: .track(track, state: .playing, position: 12),
                                permission: .denied) else {
            return XCTFail("a known track stopped drawing when Automation was refused")
        }
        XCTAssertFalse(controllable)
        guard case let .track(shown, playing, ok) =
                Presentation.of(now: .track(track, state: .playing, position: 12),
                                permission: .granted) else {
            return XCTFail("granted should still draw the track")
        }
        XCTAssertTrue(ok)
        XCTAssertTrue(playing)
        XCTAssertEqual(shown, track)
    }

    func testIdleDrawsNothing() {
        XCTAssertFalse(Presentation.nothing.draws)
        XCTAssertTrue(Presentation.permissionNeeded.draws)
        XCTAssertTrue(Presentation.track(track, playing: false, controllable: true).draws)
    }
}

final class PermissionViewTests: XCTestCase {
    /// Verified by opening it on macOS 15.7.7 and photographing the result: it
    /// lands on the Automation pane, not merely on Privacy & Security. A deep
    /// link that silently opens the wrong pane is worse than a sentence,
    /// because the user follows it and finds nothing.
    func testTheSettingsLinkNamesTheAutomationPane() {
        let url = PermissionNote.settingsURL.absoluteString
        XCTAssertTrue(url.hasPrefix("x-apple.systempreferences:"), url)
        XCTAssertTrue(url.contains("Privacy_Automation"), url)
    }

    func testTheNoteSaysWhatIsWrongAndWhatToDo() {
        XCTAssertTrue(PermissionNote.defaultExplanation.contains("Automation"))
        XCTAssertFalse(PermissionNote.action.isEmpty)
        // Not an error code. -1743 means nothing to anybody.
        XCTAssertFalse(PermissionNote.defaultExplanation.contains("1743"))
    }

    /// The permission peek reuses `PeekView`, so the one-mark rule has to hold
    /// there too: no artwork URL means the cover slot draws the mark and the
    /// standalone one stays hidden.
    func testThePermissionPeekStillDrawsExactlyOneMark() {
        let stand = PeekView.unknownTrack
        XCTAssertNil(stand.artworkURL)
        XCTAssertFalse(PeekView.showsStandaloneMark(artworkURL: stand.artworkURL))
        XCTAssertTrue(ArtworkView.showsPlaceholderMark(url: stand.artworkURL, hasImage: false))
    }
}

/// The menu bar's one line of text. It is the only surface that says anything
/// when the panel is hidden, so every state has to have an answer here too.
final class MenuSummaryTests: XCTestCase {
    private let song = Track(id: "x", name: "Comes and Goes", artist: "KETTAMA",
                             album: "Comes and Goes", duration: 262, hasArtwork: true)

    private func summary(_ now: Now, _ permission: Permission = .granted,
                         hidden: Bool = false) -> String {
        MenuBarItem.summary(now: now, permission: permission, hidden: hidden)
    }

    func testEveryStateSaysSomething() {
        XCTAssertEqual(summary(.notRunning), "Spotify is not running")
        XCTAssertEqual(summary(.stopped), "Nothing playing")
        XCTAssertEqual(summary(.unknown("timeout")), "Reading Spotify\u{2026}")
        XCTAssertEqual(summary(.track(song, state: .playing, position: 3)),
                       "Comes and Goes \u{2014} KETTAMA")
    }

    func testPausedSaysSo() {
        XCTAssertEqual(summary(.track(song, state: .paused, position: 3)),
                       "Comes and Goes \u{2014} KETTAMA (paused)")
    }

    /// Hidden is the fact the user opened the menu to check. What Spotify is
    /// doing while the panel is off the notch is beside the point.
    func testHiddenOutranksEverything() {
        for now in [Now.notRunning, .stopped, .track(song, state: .playing, position: 0)] {
            XCTAssertEqual(summary(now, hidden: true), "Hidden from the notch")
        }
    }

    /// Permission is tracked apart from `Now` for a reason: the notification
    /// carries the track even when Apple Events are refused, so a refusal with
    /// a known track still names the track.
    func testARefusalWithATrackStillNamesTheTrack() {
        XCTAssertEqual(summary(.track(song, state: .playing, position: 0), .denied),
                       "Comes and Goes \u{2014} KETTAMA")
        XCTAssertEqual(summary(.stopped, .denied), "Cannot read Spotify")
    }

    func testALongTitleIsCutRatherThanWideningTheMenu() {
        let long = Track(id: "x", name: String(repeating: "verylongword ", count: 8),
                         artist: String(repeating: "artist ", count: 8),
                         album: "", duration: 1, hasArtwork: false)
        let line = summary(.track(long, state: .playing, position: 0))
        XCTAssertTrue(line.hasSuffix("\u{2026}"))
        XCTAssertLessThanOrEqual(line.count, MenuBarItem.limit * 2 + 3)
        // Short text is left alone entirely -- no ellipsis on a name that fits.
        XCTAssertFalse(summary(.track(song, state: .playing, position: 0)).contains("\u{2026}"))
    }
}
