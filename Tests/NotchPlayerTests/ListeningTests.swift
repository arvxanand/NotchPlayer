import XCTest
@testable import NotchPlayerCore

final class ListeningTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func track(_ id: String, artist: String = "Panchiko") -> Track {
        Track(id: id, name: "Song \(id)", artist: artist, album: "", duration: 200, hasArtwork: false)
    }

    // MARK: - Counting

    /// Playing time counts; paused time does not; a new song is a new play.
    @MainActor func testOnlyPlayingTimeCounts() {
        let listening = Listening(file: nil)
        listening.saw(.track(track("a"), state: .playing, position: 0), from: .spotify, at: t0)
        listening.count(at: t0.addingTimeInterval(10))
        listening.saw(.track(track("a"), state: .paused, position: 10), from: .spotify, at: t0.addingTimeInterval(12))
        listening.count(at: t0.addingTimeInterval(100)) // paused: nothing
        listening.saw(.track(track("a"), state: .playing, position: 12), from: .spotify, at: t0.addingTimeInterval(100))
        listening.saw(.track(track("b"), state: .playing, position: 0), from: .spotify, at: t0.addingTimeInterval(105))
        XCTAssertEqual(listening.plays.map(\.id), ["a", "b"])
        XCTAssertEqual(listening.plays[0].seconds, 17, accuracy: 0.001)
        XCTAssertEqual(listening.plays[1].seconds, 0)
    }

    /// A Mac asleep mid-song: the first count after waking adds the cap, not the night.
    @MainActor func testASleepDoesNotCount() {
        let listening = Listening(file: nil)
        listening.saw(.track(track("a"), state: .playing, position: 0), from: .spotify, at: t0)
        listening.count(at: t0.addingTimeInterval(8 * 3600))
        XCTAssertEqual(listening.plays[0].seconds, Listening.cap)
    }

    @MainActor func testAdsAndStoppingEndThePlay() {
        let listening = Listening(file: nil)
        listening.saw(.track(track("spotify:ad:123"), state: .playing, position: 0), from: .spotify, at: t0)
        XCTAssertTrue(listening.plays.isEmpty)
        listening.saw(.track(track("a"), state: .playing, position: 0), from: .spotify, at: t0)
        listening.saw(.notRunning, from: .spotify, at: t0.addingTimeInterval(5))
        listening.count(at: t0.addingTimeInterval(9))
        XCTAssertEqual(listening.plays[0].seconds, 5, accuracy: 0.001)
    }

    /// Both apps count, each on its own song.
    @MainActor func testBothAppsCount() {
        let listening = Listening(file: nil)
        listening.saw(.track(track("s"), state: .playing, position: 0), from: .spotify, at: t0)
        listening.saw(.track(track("m"), state: .playing, position: 0), from: .appleMusic, at: t0)
        listening.count(at: t0.addingTimeInterval(10))
        XCTAssertEqual(listening.plays.map(\.seconds), [10, 10])
    }

    @MainActor func testKeptAcrossLaunches() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("listening-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let listening = Listening(file: file)
        listening.saw(.track(track("a"), state: .playing, position: 0), from: .spotify, at: t0)
        listening.count(at: t0.addingTimeInterval(10))
        XCTAssertEqual(Listening(file: file).plays, listening.plays)
    }

    // MARK: - Summing up

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    private func play(_ id: String, _ artist: String, minutes: Double, daysAgo: Double) -> Play {
        Play(id: id, name: "Song \(id)", artist: artist,
             started: t0.addingTimeInterval(-daysAgo * 86400), seconds: minutes * 60)
    }

    func testRangesAndTheThirtySecondRule() {
        // t0 is a Monday 01:33 UTC.
        let plays = [
            play("a", "Drake", minutes: 3, daysAgo: 0),
            play("a", "Drake", minutes: 3, daysAgo: 0.01),
            play("b", "Coldplay", minutes: 0.25, daysAgo: 0), // a skip
            play("c", "Coldplay", minutes: 10, daysAgo: 2),   // last week
            play("d", "Radiohead", minutes: 60, daysAgo: 40), // months ago
        ]
        let today = Stats.summary(plays, .today, now: t0, calendar: calendar)
        XCTAssertEqual(today.seconds, 6.25 * 60, accuracy: 0.001)
        XCTAssertEqual(today.songs, 2, "the skip is time, not a play")
        XCTAssertEqual(today.artists.map(\.name), ["Drake", "Coldplay"])
        XCTAssertEqual(today.tracks.first?.plays, 2)
        XCTAssertEqual(Stats.summary(plays, .week, now: t0, calendar: calendar).songs, 2)
        XCTAssertEqual(Stats.summary(plays, .month, now: t0, calendar: calendar).songs, 3)
        let all = Stats.summary(plays, .all, now: t0, calendar: calendar)
        XCTAssertEqual(all.songs, 4)
        XCTAssertEqual(all.artists.first?.name, "Radiohead", "artists rank by time")
        XCTAssertEqual(all.tracks.first?.name, "Song a", "songs rank by plays")
    }

    func testTopThreeOnly() {
        let plays = (0..<6).map { play("\($0)", "Artist \($0)", minutes: Double($0 + 1), daysAgo: 0) }
        let summary = Stats.summary(plays, .today, now: t0, calendar: calendar)
        XCTAssertEqual(summary.artists.map(\.name), ["Artist 5", "Artist 4", "Artist 3"])
        XCTAssertEqual(summary.tracks.count, 3)
    }

    func testDurations() {
        XCTAssertEqual(Stats.duration(0), "0m")
        XCTAssertEqual(Stats.duration(59), "0m")
        XCTAssertEqual(Stats.duration(14 * 60), "14m")
        XCTAssertEqual(Stats.duration(134.2 * 60), "2h 14m")
    }

    // MARK: - The page

    private let geometries = [
        NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                      notchWidth: 208, notchHeight: 37, hasNotch: true),
        NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                      notchWidth: 185, notchHeight: 32, hasNotch: true),
        NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                      notchWidth: 0, notchHeight: 24, hasNotch: false),
    ]

    func testThePageFitsBelowTheBandAndAboveTheDots() {
        for g in geometries {
            XCTAssertLessThanOrEqual(StatsView.contentHeight(),
                                     g.openHeight - g.notchExclusionTop - PanelView.bottomGap)
        }
    }

    func testTheStatsButtonIsATargetOfItsOwn() {
        for g in geometries {
            let r = PanelView.statsRect(g)
            let repeatRect = PanelView.transportRects(g).first { $0.name == "repeat" }!.rect
            XCTAssertEqual(r.width, NotchGeometry.minimumHitHeight)
            XCTAssertGreaterThanOrEqual(r.minY, g.notchExclusionTop)
            XCTAssertLessThanOrEqual(r.maxX, g.screenFrame.midX + g.openWidth / 2)
            XCTAssertGreaterThan(r.minX, repeatRect.maxX, "touches repeat")
        }
    }

    func testOnlyASidewaysTrackpadSwipeFlipsThePage() {
        XCTAssertEqual(Expansion.swipe(dx: -60, dy: 5, precise: true), .stats)
        XCTAssertEqual(Expansion.swipe(dx: 60, dy: -5, precise: true), .player)
        XCTAssertNil(Expansion.swipe(dx: -60, dy: 40, precise: true), "mostly scrolling")
        XCTAssertNil(Expansion.swipe(dx: -30, dy: 0, precise: true), "too short")
        XCTAssertNil(Expansion.swipe(dx: -200, dy: 0, precise: false), "a mouse wheel")
    }

    @MainActor func testAClosedPanelHasNoPageToShow() {
        let expansion = Expansion()
        expansion.show(.stats)
        XCTAssertEqual(expansion.page, .player)
    }
}
