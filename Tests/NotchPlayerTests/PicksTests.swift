import XCTest
@testable import NotchPlayerCore

final class PicksTests: XCTestCase {
    // MARK: - Links

    func testShareLinksAndURIsGiveTheURI() {
        let cases = [
            "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc123": "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M",
            "https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy": "spotify:album:4aawyAB9vmqN3uQ7FjRGTy",
            "https://open.spotify.com/intl-de/album/4aawyAB9vmqN3uQ7FjRGTy?si=x": "spotify:album:4aawyAB9vmqN3uQ7FjRGTy",
            "  spotify:playlist:37i9dQZF1DXcBWIGoYBM5M\n": "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M",
            "spotify:collection:tracks": "spotify:collection:tracks",
        ]
        for (link, uri) in cases { XCTAssertEqual(Picks.uri(fromLink: link), uri, link) }
    }

    func testAnythingElseIsNotALink() {
        for text in [
            "", "   ", "hello",
            "https://open.spotify.com/track/4sIFi8LpJWPvI5xviWFyA6",
            "https://open.spotify.com/artist/0OdUWJ0sBjDrqHygGUXeCF",
            "https://open.spotify.com/episode/abc",
            "https://example.com/playlist/37i9dQZF1DXcBWIGoYBM5M",
            "https://open.spotify.com/playlist/",
            "spotify:playlist:",
            "spotify:track:4sIFi8LpJWPvI5xviWFyA6",
            // The one that matters: it would close the quoted string.
            #"spotify:playlist:abc" & do shell script "say hi"#,
            "spotify:playlist:abc def",
        ] {
            XCTAssertNil(Picks.uri(fromLink: text), text)
        }
    }

    // MARK: - Preview

    func testThePreviewGivesTheTitleAndCover() {
        let body = Data(#"{"type":"rich","title":"Today’s Top Hits","thumbnail_url":"https://i.scdn.co/image/ab67706f0000000271992d3b45eb1297df9c6bf7","provider_name":"Spotify"}"#.utf8)
        let parsed = Picks.parse(body)
        XCTAssertEqual(parsed?.name, "Today’s Top Hits")
        XCTAssertEqual(parsed?.cover, URL(string: "https://i.scdn.co/image/ab67706f0000000271992d3b45eb1297df9c6bf7"))
    }

    func testAPreviewWithoutATitleIsNothing() {
        XCTAssertNil(Picks.parse(Data(#"{"thumbnail_url":"https://i.scdn.co/x"}"#.utf8)))
        XCTAssertNil(Picks.parse(Data(#"{"title":""}"#.utf8)))
        XCTAssertNil(Picks.parse(Data("not json".utf8)))
        XCTAssertEqual(Picks.fallbackName("spotify:album:X"), "Album")
        XCTAssertEqual(Picks.fallbackName("spotify:playlist:X"), "Playlist")
    }

    // MARK: - Store

    private func defaults() -> UserDefaults {
        let name = "PicksTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @MainActor func testStartsWithDJAndLikedSongs() {
        XCTAssertEqual(Picks(defaults: defaults()).all, [.dj, .liked])
    }

    @MainActor func testKeptAcrossLaunches() async {
        let d = defaults()
        let picks = Picks(defaults: d)
        picks.remove(Pick.dj.uri)
        XCTAssertEqual(Picks(defaults: d).all, [.liked])
    }

    @MainActor func testTheSameLinkTwiceAddsOnce() async {
        let picks = Picks(defaults: defaults())
        let added = await picks.add(link: "spotify:collection:tracks")
        XCTAssertEqual(added, .already)
        let junk = await picks.add(link: "not a link")
        XCTAssertEqual(junk, .notALink)
        let nothing = await picks.add(link: nil)
        XCTAssertEqual(nothing, .notALink)
        XCTAssertEqual(picks.all, [.dj, .liked])
    }

    /// Removing a built-in is just removing; its link brings it back, with its
    /// own name and icon, without asking the preview (which has nothing for it).
    @MainActor func testPastingDJsLinkBringsItBack() async {
        let picks = Picks(defaults: defaults())
        picks.remove(Pick.dj.uri)
        let added = await picks.add(link: "https://open.spotify.com/playlist/37i9dQZF1EYkqdzj48dyYq?si=1")
        XCTAssertEqual(added, .added)
        XCTAssertEqual(picks.all, [.liked, .dj])
        XCTAssertEqual(picks.all.last?.symbol, "headphones")
    }

    // MARK: - Playing

    func testPlayIsSpotifysPlayTrack() {
        XCTAssertEqual(Command.play("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M").script(for: .spotify),
                       #"tell application "Spotify" to play track "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M""#)
        XCTAssertEqual(Command.play("spotify:collection:tracks").script(for: .spotify),
                       #"tell application "Spotify" to play track "spotify:collection:tracks""#)
        XCTAssertFalse(Command.play("spotify:collection:tracks").cacheable)
    }

    /// Whatever reaches the command, a bad URI never becomes a `play track`.
    func testABadURIPlaysNothing() {
        for uri in [#"spotify:playlist:a" & do shell script "x"#, "", "spotify:track:abc"] {
            XCTAssertFalse(Command.play(uri).script(for: .spotify).contains("play track"), uri)
        }
        XCTAssertFalse(Command.play("spotify:collection:tracks").script(for: .appleMusic).contains("play track"))
    }
}
