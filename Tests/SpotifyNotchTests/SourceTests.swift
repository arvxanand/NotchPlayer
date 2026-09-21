import CoreAudio
import XCTest
@testable import SpotifyNotchCore

/// Which app the notch follows. Every rule here is one the user chose, so
/// each gets asserted rather than described in a comment.
final class SourceTests: XCTestCase {

    private func source(_ bundle: String, name: String = "An App",
                        object: AudioObjectID = 1) -> AudioSource {
        AudioSource(object: object, pid: 100, appPID: 100, name: name, bundleID: bundle)
    }
    private let chrome = "com.google.Chrome"
    private let now = Date()

    // MARK: - The three-second dwell

    func testAShortSoundNeverReachesTheNotch() {
        let started = now
        // A notification ding: a second of audio, then gone.
        XCTAssertFalse(AudioSources.adopted(started: started,
                                            now: started.addingTimeInterval(1),
                                            isSpotify: false))
        XCTAssertTrue(AudioSources.adopted(started: started,
                                           now: started.addingTimeInterval(AudioSources.dwell),
                                           isSpotify: false))
    }

    /// Spotify announces itself over its own notification and is never a
    /// stray ding. Making it wait would be a regression in the case the whole
    /// app was built for.
    func testSpotifyDoesNotWait() {
        XCTAssertTrue(AudioSources.adopted(started: now, now: now, isSpotify: true))
        XCTAssertFalse(AudioSources.adopted(started: now, now: now, isSpotify: false))
    }

    func testTheDwellIsLongEnoughToOutlastANotification() {
        XCTAssertGreaterThanOrEqual(AudioSources.dwell, 2)
        XCTAssertLessThanOrEqual(AudioSources.dwell, 5, "a video should not feel broken")
    }

    // MARK: - Calls are never tapped

    func testConferencingAppsAreExcluded() {
        for bundle in ["us.zoom.xos", "com.apple.FaceTime", "com.microsoft.teams"] {
            XCTAssertTrue(AudioSources.isExcluded(bundle), bundle)
        }
        for bundle in [chrome, "com.spotify.client", "com.colliderli.iina"] {
            XCTAssertFalse(AudioSources.isExcluded(bundle), bundle)
        }
    }

    /// An excluded app is not merely hidden: it is never chosen, so no tap is
    /// ever built for it and its audio never enters this process.
    func testAnExcludedAppIsNeverChosenEvenWhenItIsTheOnlyThingPlaying() {
        let zoom = source("us.zoom.xos", name: "zoom.us")
        XCTAssertNil(AudioSources.chosen(from: [(zoom, now.addingTimeInterval(-60))], now: now))
    }

    func testAnExcludedAppCannotOutrankARealOne() {
        let video = source(chrome, name: "Google Chrome", object: 1)
        let zoom = source("us.zoom.xos", name: "zoom.us", object: 2)
        // The call started more recently, and still loses.
        let chosen = AudioSources.chosen(from: [(video, now.addingTimeInterval(-30)),
                                                (zoom, now.addingTimeInterval(-5))], now: now)
        XCTAssertEqual(chosen?.bundleID, chrome)
    }

    // MARK: - Most recent wins

    func testTheMostRecentlyStartedSourceWins() {
        let spotify = source("com.spotify.client", name: "Spotify", object: 1)
        let video = source(chrome, name: "Google Chrome", object: 2)
        let chosen = AudioSources.chosen(from: [(spotify, now.addingTimeInterval(-120)),
                                                (video, now.addingTimeInterval(-10))], now: now)
        XCTAssertEqual(chosen?.name, "Google Chrome")
    }

    /// Pause the video and Spotify is still in the list, so the notch goes
    /// straight back to it -- with its full panel.
    func testTheOlderSourceTakesOverWhenTheNewerOneStops() {
        let spotify = source("com.spotify.client", name: "Spotify", object: 1)
        let chosen = AudioSources.chosen(from: [(spotify, now.addingTimeInterval(-120))], now: now)
        XCTAssertEqual(chosen?.name, "Spotify")
    }

    func testSilenceChoosesNothing() {
        XCTAssertNil(AudioSources.chosen(from: [], now: now))
    }

    /// A video that has only just started is not chosen *yet* -- and nothing
    /// else is chosen in its place.
    func testASourceStillServingItsDwellIsNotChosen() {
        let video = source(chrome)
        XCTAssertNil(AudioSources.chosen(from: [(video, now.addingTimeInterval(-1))], now: now))
    }

    // MARK: - Helper processes

    /// Browsers play their audio from a helper that is not an app and has no
    /// name or icon. Every process has a parent; launchd is nobody's owner.
    func testTheParentWalkStopsAtLaunchd() {
        XCTAssertNil(AudioSources.parentPID(of: 1), "launchd owns nothing")
        XCTAssertNotNil(AudioSources.parentPID(of: ProcessInfo.processInfo.processIdentifier))
    }

    func testThisProcessResolvesToAnAppOrHonestlyToNothing() {
        // The test runner is not a bundled app, so this must answer nil
        // rather than inventing an owner.
        let mine = ProcessInfo.processInfo.processIdentifier
        let owner = MainActor.assumeIsolated { AudioSources.owningApp(mine) }
        if let owner { XCTAssertFalse(owner.bundle.isEmpty) }
    }
}

/// A source that holds an audio stream open without playing anything. Caught
/// on the first live run -- Claude Desktop reports "producing output" with an
/// idle audio context, and would have taken the notch after three seconds and
/// sat there with flat bars.
extension SourceTests {
    func testASilentSourceIsPassedOverForSomethingRealButComesBackLater() {
        let idle = source("com.anthropic.claudefordesktop", name: "Claude", object: 7)
        let started = now.addingTimeInterval(-10)
        let until = now.addingTimeInterval(AudioSources.quietRetry)

        XCTAssertNil(AudioSources.chosen(from: [(idle, started)], now: now,
                                         quiet: [idle.object: until]))
        // And it is reconsidered once the skip expires: an idle stream and a
        // video that opens on a quiet passage look identical for two seconds.
        XCTAssertEqual(AudioSources.chosen(from: [(idle, started)],
                                           now: until.addingTimeInterval(1),
                                           quiet: [idle.object: until])?.object, idle.object)
    }

    func testASilentSourceLosesToARealOneImmediately() {
        let idle = source("com.anthropic.claudefordesktop", name: "Claude", object: 7)
        let video = source(chrome, name: "Google Chrome", object: 8)
        // The idle one started more recently and still loses.
        let chosen = AudioSources.chosen(
            from: [(video, now.addingTimeInterval(-30)), (idle, now.addingTimeInterval(-5))],
            now: now, quiet: [idle.object: now.addingTimeInterval(10)])
        XCTAssertEqual(chosen?.bundleID, chrome)
    }

    /// Spotify is never passed over: we know what it is playing without
    /// listening to it. This is also what keeps the app working when audio
    /// recording is refused, where every source looks silent.
    func testSpotifyIsNeverPassedOverForBeingQuiet() {
        let spotify = source("com.spotify.client", name: "Spotify", object: 9)
        let chosen = AudioSources.chosen(from: [(spotify, now.addingTimeInterval(-30))],
                                         now: now,
                                         quiet: [spotify.object: now.addingTimeInterval(10)])
        XCTAssertEqual(chosen?.name, "Spotify")
    }
}

/// The bug the user hit: a video kept the notch for a minute after they
/// started their music.
///
/// `IsRunningOutput` means "has an audio stream open", not "is making sound"
/// -- measured, with Spotify reporting output continuously through a
/// four-second pause. So a stream's age is not evidence that it is playing.
extension SourceTests {
    func testAPausedSpotifyDoesNotOutrankAVideoThatStartedLater() {
        let spotify = source("com.spotify.client", name: "Spotify", object: 1)
        let video = source(chrome, name: "Google Chrome", object: 2)
        // Spotify's stream is older, the video started after it, and Spotify
        // is paused: the video must win.
        let chosen = AudioSources.chosen(
            from: [(spotify, now.addingTimeInterval(-600)), (video, now.addingTimeInterval(-20))],
            now: now, spotifyPlaying: false)
        XCTAssertEqual(chosen?.name, "Google Chrome")
    }

    /// And the case the user actually reported, which is the same rule from
    /// the other side: the video's stream is newer, but it is Spotify that is
    /// playing.
    func testAStaleVideoStreamDoesNotKeepTheNotchFromPlayingMusic() {
        let spotify = source("com.spotify.client", name: "Spotify", object: 1)
        let video = source(chrome, name: "Google Chrome", object: 2)
        // The video is paused, so the tap has stood it down -- that is what
        // `quiet` records. Spotify is playing.
        let chosen = AudioSources.chosen(
            from: [(spotify, now.addingTimeInterval(-600)), (video, now.addingTimeInterval(-20))],
            now: now, quiet: [video.object: now.addingTimeInterval(10)], spotifyPlaying: true)
        XCTAssertEqual(chosen?.name, "Spotify")
    }

    func testAPausedSpotifyIsNotChosenEvenAsTheOnlySource() {
        let spotify = source("com.spotify.client", name: "Spotify", object: 1)
        XCTAssertNil(AudioSources.chosen(from: [(spotify, now.addingTimeInterval(-60))],
                                         now: now, spotifyPlaying: false))
    }

    /// Standing a source down has to be slower than the waveform's fallback,
    /// or a quiet passage in a song changes which app the notch follows
    /// rather than just the height of the bars.
    func testStandingASourceDownIsSlowerThanFallingBackToSyntheticBars() {
        XCTAssertGreaterThan(AudioSources.followSilence, AudioTap.deadline)
    }
}
