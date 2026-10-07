import AppKit
import XCTest
@testable import NotchPlayerCore

/// What differs between Spotify and Apple Music, and nothing else: both run
/// through the same bridge and service, so the shared paths are covered by the
/// tests that already exist.
final class SourceTests: XCTestCase {
    // MARK: - Commands

    /// The words Music's dictionary has for the same four things. Read from
    /// `sdef /System/Applications/Music.app`; not yet run against a playing Music.
    func testMusicSpeaksItsOwnDictionary() {
        let music = Source.appleMusic
        XCTAssertEqual(Command.playpause.script(for: music), #"tell application "Music" to playpause"#)
        XCTAssertEqual(Command.previous.script(for: music), #"tell application "Music" to previous track"#)
        XCTAssertEqual(Command.next.script(for: music), #"tell application "Music" to next track"#)
        XCTAssertEqual(Command.seek(42.5).script(for: music),
                       #"tell application "Music" to set player position to 42.500"#)
        XCTAssertEqual(Command.shuffle(true).script(for: music),
                       #"tell application "Music" to set shuffle enabled to true"#)
        XCTAssertEqual(Command.repeating(true).script(for: music),
                       #"tell application "Music" to set song repeat to all"#)
        XCTAssertEqual(Command.repeating(false).script(for: music),
                       #"tell application "Music" to set song repeat to off"#)
    }

    func testNoCommandActivatesEitherApp() {
        for source in Source.allCases {
            for command in Command.simple + [.seek(1), .shuffle(false), .repeating(true)] {
                XCTAssertFalse(command.script(for: source).contains("activate"),
                               "\(command) activates \(source.name)")
            }
        }
    }

    // MARK: - Reading

    /// Music has no artwork URL and counts its duration in seconds; its read
    /// script fills the nine fields so the one parser still applies.
    func testAMusicReadParsesThroughTheSharedParser() {
        let fields = ["Song", "Artist", "Album", "Album Artist", "215000.0", "",
                      "A1B2C3D4E5F60718", "12.5", "playing"]
        guard case .ok(let track, let state, let position) = Reading.from(appleScript: fields) else {
            return XCTFail("did not parse")
        }
        XCTAssertEqual(track.id, "A1B2C3D4E5F60718")
        XCTAssertEqual(track.duration, 215, accuracy: 0.001)
        XCTAssertNil(track.artworkURL)
        XCTAssertFalse(track.hasArtwork)
        XCTAssertEqual(state, .playing)
        XCTAssertEqual(position, 12.5, accuracy: 0.001)
    }

    func testEachSourceReadsNineFields() {
        for source in Source.allCases {
            // Between `return {` and the closing `}`, items are separated by
            // commas that sit outside parentheses.
            let line = source.readScript.components(separatedBy: "return {")[1]
                .components(separatedBy: "}")[0].replacingOccurrences(of: "\\\n", with: "")
            var depth = 0, count = 1
            for c in line {
                if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
                else if c == ",", depth == 0 { count += 1 }
            }
            XCTAssertEqual(count, Reading.fieldCount, "\(source.name)'s read script")
        }
    }

    func testMusicModesReadThroughTheSharedParser() {
        XCTAssertEqual(Modes.from(["true", "false", "true"]),
                       Modes(shuffle: true, repeating: false, allowed: true))
        XCTAssertTrue(Source.appleMusic.modesScript.contains("song repeat"))
    }

    // MARK: - Identity

    func testEachSourceHasItsOwnApp() {
        XCTAssertEqual(Source.spotify.bundleID, "com.spotify.client")
        XCTAssertEqual(Source.appleMusic.bundleID, "com.apple.Music")
        XCTAssertTrue(Source.spotify.notificationCarriesTrack)
        XCTAssertFalse(Source.appleMusic.notificationCarriesTrack)
        XCTAssertTrue(Source.appleMusic.notifications.contains("com.apple.Music.playerInfo"))
    }

    // MARK: - Which one the notch shows

    func testWhoeverIsPlayingIsShown() {
        XCTAssertEqual(Players.pick(last: .spotify, playing: .appleMusic, draws: [.spotify, .appleMusic]),
                       .appleMusic)
        XCTAssertEqual(Players.pick(last: .appleMusic, playing: .spotify, draws: [.spotify, .appleMusic]),
                       .spotify)
    }

    func testBothPlayingIsSpotify() {
        XCTAssertEqual(Players.playing(spotify: true, music: true), .spotify)
        XCTAssertEqual(Players.playing(spotify: false, music: true), .appleMusic)
        XCTAssertNil(Players.playing(spotify: false, music: false))
    }

    func testBothPausedKeepsTheLastOne() {
        for last in Source.allCases {
            XCTAssertEqual(Players.pick(last: last, playing: nil, draws: [.spotify, .appleMusic]), last)
        }
    }

    /// The last one quit; showing nothing while the other holds a paused song
    /// would hide a song the user can see in its own window.
    func testALastOneWithNothingToDrawGivesWayToTheOther() {
        XCTAssertEqual(Players.pick(last: .appleMusic, playing: nil, draws: [.spotify]), .spotify)
        XCTAssertEqual(Players.pick(last: .spotify, playing: nil, draws: [.appleMusic]), .appleMusic)
        XCTAssertEqual(Players.pick(last: .appleMusic, playing: nil, draws: []), .appleMusic)
    }

    // MARK: - The menu line

    func testTheMenuNamesTheAppItIsAbout() {
        XCTAssertEqual(MenuBarItem.summary(now: .notRunning, permission: .unknown, hidden: false,
                                           source: .appleMusic), "Apple Music is not running")
        XCTAssertEqual(MenuBarItem.summary(now: .unknown("x"), permission: .denied, hidden: false,
                                           source: .appleMusic), "Cannot read Apple Music")
    }

    // MARK: - Cover

    /// A Music cover is an `.img` file the service wrote; a file that is not an
    /// image is nothing, not a blank square.
    func testAMusicCoverFileIsReadBackAndValidated() async throws {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let png = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation!)?
            .representation(using: .png, properties: [:]))
        let good = ArtworkCache.coverFile("TEST-GOOD-\(UUID().uuidString)")
        let bad = ArtworkCache.coverFile("TEST-BAD-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: good.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: good)
        try Data("not an image".utf8).write(to: bad)
        defer { try? FileManager.default.removeItem(at: good); try? FileManager.default.removeItem(at: bad) }

        let cache = ArtworkCache()
        let read = await cache.data(for: good)
        XCTAssertEqual(read, png)
        let refused = await cache.data(for: bad)
        XCTAssertNil(refused)
    }
}
