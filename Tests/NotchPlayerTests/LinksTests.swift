import XCTest
@testable import NotchPlayerCore

final class LinksTests: XCTestCase {
    /// The real page's tags, not a hand-written guess at them.
    private var realPage: String {
        let url = Bundle.module.url(forResource: "Fixtures/open-spotify-track", withExtension: "html")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    func testTheRealPageGivesTheAlbumAndTheArtist() {
        let page = SpotifyLinks.Page.parse(realPage)
        XCTAssertEqual(page.album, URL(string: "spotify:album:2MASm01cgG0a0CgioQpe6Q"))
        XCTAssertEqual(page.artist, URL(string: "spotify:artist:4KEHIUSoWCcqrk8AddTE1O"))
    }

    /// A collaboration lists every artist; the first is the one on the credit.
    func testTheFirstOfSeveralArtistsWins() {
        let html = """
        <meta name="music:musician" content="https://open.spotify.com/artist/AAA111"/>
        <meta name="music:musician" content="https://open.spotify.com/artist/BBB222"/>
        """
        XCTAssertEqual(SpotifyLinks.Page.parse(html).artist, URL(string: "spotify:artist:AAA111"))
    }

    func testAttributeOrderDoesNotMatter() {
        let html = #"<meta content="https://open.spotify.com/album/XYZ9" name="music:album">"#
        XCTAssertEqual(SpotifyLinks.Page.parse(html).album, URL(string: "spotify:album:XYZ9"))
    }

    /// A page that changed shape must fall back to search, not open nonsense.
    func testAPageWithoutTheTagsGivesNothing() {
        XCTAssertEqual(SpotifyLinks.Page.parse("<html><head><title>x</title></head></html>"),
                       SpotifyLinks.Page(album: nil, artist: nil))
    }

    func testALinkOfTheWrongKindOrHostIsRefused() {
        XCTAssertNil(SpotifyLinks.Page.uri("https://open.spotify.com/artist/X1", kind: "album"))
        XCTAssertNil(SpotifyLinks.Page.uri("https://evil.example/album/X1", kind: "album"))
        XCTAssertNil(SpotifyLinks.Page.uri("https://open.spotify.com/album/a%3Ab", kind: "album"))
    }

    func testOnlyATrackHasAPage() {
        XCTAssertEqual(SpotifyLinks.pageURL(for: "spotify:track:4sIFi8LpJWPvI5xviWFyA6"),
                       URL(string: "https://open.spotify.com/track/4sIFi8LpJWPvI5xviWFyA6"))
        XCTAssertNil(SpotifyLinks.pageURL(for: "spotify:episode:3aBcDeFgHiJkLmNoPqRsTu"))
        XCTAssertNil(SpotifyLinks.pageURL(for: "spotify:local:Artist:Album:Song:215"))
        XCTAssertNil(SpotifyLinks.pageURL(for: "spotify:track:"))
        XCTAssertNil(SpotifyLinks.pageURL(for: "spotify:track:../../x"))
    }

    /// Spaces and ampersands in a name must not end the URI early.
    func testSearchEncodesTheName() {
        XCTAssertEqual(SpotifyLinks.search("Simon & Garfunkel")?.absoluteString,
                       "spotify:search:Simon%20%26%20Garfunkel")
        XCTAssertNil(SpotifyLinks.search("   "))
    }
}

final class LinkTargetTests: XCTestCase {
    private let page = SpotifyLinks.Page(album: URL(string: "spotify:album:ALB1"),
                                         artist: URL(string: "spotify:artist:ART1"))
    private let id = "spotify:track:TRK1"

    /// Never the bare track URI: opening that starts playback.
    func testTheTitleOpensItsAlbumWithTheSongHighlighted() {
        XCTAssertEqual(page.link(.track, track: id),
                       URL(string: "spotify:album:ALB1:highlight:spotify:track:TRK1"))
    }

    func testTheCoverAndTheArtistOpenTheirPages() {
        XCTAssertEqual(page.link(.album, track: id), URL(string: "spotify:album:ALB1"))
        XCTAssertEqual(page.link(.artist, track: id), URL(string: "spotify:artist:ART1"))
    }

    func testEachFallbackSearchesForTheRightThing() {
        let track = Track(id: id, name: "Song", artist: "Singer", album: "Record",
                          duration: 1, hasArtwork: false)
        XCTAssertEqual(SpotifyLinks.fallbackTerm(.track, track), "Song Singer")
        XCTAssertEqual(SpotifyLinks.fallbackTerm(.album, track), "Record Singer")
        XCTAssertEqual(SpotifyLinks.fallbackTerm(.artist, track), "Singer")
    }
}
