import XCTest
@testable import NotchPlayerCore

/// The words here are invented: real lyrics are someone's work, and a test
/// only needs the shape LRCLIB sends.
final class LyricsTests: XCTestCase {
    func testItReadsTwoAndThreeDigitFractions() {
        let lines = Lyrics.parse(lrc: "[00:09.19] first\n[01:02.500]second\n[02:03] third")
        XCTAssertEqual(lines.map(\.text), ["first", "second", "third"])
        XCTAssertEqual(lines[0].time, 9.19, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 62.5, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 123, accuracy: 0.001)
    }

    /// A repeated chorus is often written once with every time it is sung.
    func testALineWithSeveralTimesAppearsAtEach() {
        let lines = Lyrics.parse(lrc: "[00:10.00][00:40.00]chorus\n[00:20.00]verse")
        XCTAssertEqual(lines.map(\.text), ["chorus", "verse", "chorus"])
        XCTAssertEqual(lines.map(\.time), [10, 20, 40])
    }

    func testTagsAndUntimedLinesAreDroppedAndGapsKept() {
        let lrc = "[ar:Somebody]\n[ti:A Song]\n[length: 03:00]\nno time here\n[00:05.00]\n[00:06.00] words "
        let lines = Lyrics.parse(lrc: lrc)
        XCTAssertEqual(lines, [Lyrics.Line(time: 5, text: ""), Lyrics.Line(time: 6, text: "words")])
    }

    func testOutOfOrderLinesAreSortedAndTiesKeepTheirOrder() {
        let lines = Lyrics.parse(lrc: "[00:30.00]c\n[00:10.00]a\n[00:10.00]b")
        XCTAssertEqual(lines.map(\.text), ["a", "b", "c"])
    }

    func testJunkIsNotATime() {
        for junk in ["[aa:bb]x", "[00:61.00]x", "[-1:00.00]x", "[00:1e1]x", "[00:nan]x", "[:]x", "[00:]x"] {
            XCTAssertEqual(Lyrics.parse(lrc: junk), [], junk)
        }
        XCTAssertEqual(Lyrics.parse(lrc: ""), [])
    }

    func testAHugeReplyIsCut() {
        let lrc = (0..<2000).map { "[\(String(format: "%02d", $0 / 60)):\(String(format: "%02d", $0 % 60)).00]x" }
            .joined(separator: "\n")
        XCTAssertEqual(Lyrics.parse(lrc: lrc).count, Lyrics.maxLines)
    }

    func testTheCurrentLineLightsUpJustBeforeItIsSung() {
        let lines = [Lyrics.Line(time: 10, text: "a"), Lyrics.Line(time: 20, text: "b")]
        XCTAssertNil(Lyrics.index(of: lines, at: 0), "the intro, before any words")
        XCTAssertNil(Lyrics.index(of: lines, at: 9.7))
        XCTAssertEqual(Lyrics.index(of: lines, at: 10 - Lyrics.lead), 0, "the lead")
        XCTAssertEqual(Lyrics.index(of: lines, at: 19), 0)
        XCTAssertEqual(Lyrics.index(of: lines, at: 20), 1)
        XCTAssertEqual(Lyrics.index(of: lines, at: 500), 1, "the last line stays lit")
        XCTAssertNil(Lyrics.index(of: [], at: 5))
    }

    /// The page redraws only when a line starts: the schedule is exactly the
    /// lines still to come, and nothing at all while paused.
    func testThePageWakesOnlyWhenALineStarts() {
        let lines = [Lyrics.Line(time: 10, text: "a"), Lyrics.Line(time: 20, text: "b"),
                     Lyrics.Line(time: 30, text: "c")]
        let now = Date(timeIntervalSinceReferenceDate: 0), clock = SuspendingClock.Instant.now
        let playing = Interpolator(position: 15, stamped: clock, advancing: true)
        let dates = LyricsLines.changes(lines, progress: playing, duration: 200, now: now, clock: clock)
        XCTAssertEqual(dates.map(\.timeIntervalSinceReferenceDate), [5 - Lyrics.lead, 15 - Lyrics.lead])
        let paused = Interpolator(position: 15, stamped: clock, advancing: false)
        XCTAssertEqual(LyricsLines.changes(lines, progress: paused, duration: 200, now: now, clock: clock), [])
        XCTAssertEqual(LyricsLines.changes(lines, progress: nil, duration: 200, now: now, clock: clock), [])
    }

    // MARK: - LRCLIB replies

    func testAnExactMatchIsDecoded() throws {
        let body = Data(#"""
        {"id":1,"trackName":"A Song","artistName":"Somebody","albumName":"A Record","duration":201.0,
         "instrumental":false,"plainLyrics":"one\ntwo","syncedLyrics":"[00:01.00] one\n[00:02.00] two"}
        """#.utf8)
        let record = try JSONDecoder().decode(Lyrics.Record.self, from: body)
        XCTAssertEqual(Lyrics.lyrics(from: record),
                       .synced([Lyrics.Line(time: 1, text: "one"), Lyrics.Line(time: 2, text: "two")]))
    }

    func testWithoutTimingsThePlainWordsAreUsed() throws {
        let body = Data(#"{"duration":200,"instrumental":false,"plainLyrics":"one\n\ntwo","syncedLyrics":null}"#.utf8)
        let record = try JSONDecoder().decode(Lyrics.Record.self, from: body)
        XCTAssertEqual(Lyrics.lyrics(from: record), .plain(["one", "", "two"]))
    }

    func testInstrumentalAndEmptyAreToldApart() throws {
        let instrumental = Data(#"{"duration":200,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#.utf8)
        let empty = Data(#"{"duration":200,"instrumental":false,"plainLyrics":"  ","syncedLyrics":""}"#.utf8)
        XCTAssertEqual(Lyrics.lyrics(from: try JSONDecoder().decode(Lyrics.Record.self, from: instrumental)),
                       .instrumental)
        XCTAssertEqual(Lyrics.lyrics(from: try JSONDecoder().decode(Lyrics.Record.self, from: empty)), .none)
    }

    private func record(_ duration: Double?, synced: String? = nil, plain: String? = nil,
                        instrumental: Bool = false) -> Lyrics.Record {
        Lyrics.Record(duration: duration, instrumental: instrumental, plainLyrics: plain, syncedLyrics: synced)
    }

    /// LRCLIB keeps a copy of a song per album it appeared on, a second or
    /// two apart. Timed words win over closeness, closeness over the rest.
    func testASearchPicksTimedWordsFromTheClosestLength() {
        let records = [
            record(200, plain: "plain"),
            record(203, synced: "[00:01.00]further"),
            record(201, synced: "[00:01.00]closer"),
            record(230, synced: "[00:01.00]the extended mix"),
        ]
        XCTAssertEqual(Lyrics.best(in: records, duration: 200), .synced([Lyrics.Line(time: 1, text: "closer")]))
    }

    func testASearchFallsBackToPlainThenInstrumentalThenNothing() {
        XCTAssertEqual(Lyrics.best(in: [record(200, instrumental: true), record(201, plain: "words")], duration: 200),
                       .plain(["words"]))
        XCTAssertEqual(Lyrics.best(in: [record(200, instrumental: true)], duration: 200), .instrumental)
        XCTAssertEqual(Lyrics.best(in: [record(260, synced: "[00:01.00]too long")], duration: 200), .none,
                       "a different cut is timed for something else")
        XCTAssertEqual(Lyrics.best(in: [record(nil, synced: "[00:01.00]no length")], duration: 200), .none)
        XCTAssertEqual(Lyrics.best(in: [], duration: 200), .none)
    }

    func testASearchReplyDecodes() throws {
        let body = Data(#"""
        [{"id":1,"name":"A Song","trackName":"A Song","artistName":"Somebody","albumName":"Singles",
          "duration":199.0,"instrumental":false,"plainLyrics":"x","syncedLyrics":"[00:03.00]x","hasWordSync":false}]
        """#.utf8)
        let records = try JSONDecoder().decode([Lyrics.Record].self, from: body)
        XCTAssertEqual(Lyrics.best(in: records, duration: 200), .synced([Lyrics.Line(time: 3, text: "x")]))
    }

    /// What is kept on disk reads back as it was written.
    func testSavedLyricsRoundTrip() throws {
        for lyrics: Lyrics in [.synced([Lyrics.Line(time: 1.5, text: "a")]), .plain(["a", ""]), .instrumental] {
            let bytes = try JSONEncoder().encode(lyrics)
            XCTAssertEqual(try JSONDecoder().decode(Lyrics.self, from: bytes), lyrics)
        }
    }

    func testTheCacheFileIsASafeName() {
        let local = Track(id: "spotify:local:Some+One:An+Album:A%2FSong:200", name: "A/Song", artist: "Some One",
                          album: "An Album", duration: 200, hasArtwork: false)
        let name = Lyrics.cacheFile(for: local).lastPathComponent
        XCTAssertFalse(name.contains("/") || name.contains(":"), name)
        XCTAssertTrue(name.hasSuffix(".json"))
    }
}
