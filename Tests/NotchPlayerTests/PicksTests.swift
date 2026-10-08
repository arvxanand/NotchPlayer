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

    /// A favourite dragged to the front goes ahead of the built-ins, and stays.
    @MainActor func testReorderingIsKept() async {
        let d = defaults()
        let picks = Picks(defaults: d)
        _ = await picks.add(link: "spotify:collection:tracks")
        picks.move(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(picks.all, [.liked, .dj])
        XCTAssertEqual(Picks(defaults: d).all, [.liked, .dj])
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

/// The picks page and the way to it.
final class PicksPageTests: XCTestCase {
    private let geometries = [
        NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                      notchWidth: 208, notchHeight: 37, hasNotch: true),
        // A narrower notch, where four 72pt covers do not fit.
        NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                      notchWidth: 185, notchHeight: 32, hasNotch: true),
        NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                      notchWidth: 0, notchHeight: 24, hasNotch: false),
    ]

    func testFourCoversFillTheRowAndStayTappable() {
        for g in geometries {
            let side = PicksView.side(g), gap = PicksView.gap(g)
            XCTAssertEqual(side * 4 + gap * 3, g.openWidth - PanelView.inset * 2, accuracy: 0.01)
            XCTAssertLessThanOrEqual(side, PanelView.artSide)
            XCTAssertGreaterThanOrEqual(side, NotchGeometry.minimumHitHeight)
            XCTAssertGreaterThanOrEqual(gap, PicksView.minimumGap)
        }
        XCTAssertEqual(PicksView.side(geometries[0]), 72, "the player's size where it fits")
    }

    /// Exactly one row shows, whole, clear of the camera band and the dots.
    func testOneRowFitsWhole() {
        for g in geometries {
            let page = g.openHeight - g.notchExclusionTop - PanelView.bottomGap
            XCTAssertLessThanOrEqual(PicksView.rowHeight(g), page)
        }
    }

    func testCellsGoInRowsOfFour() {
        XCTAssertEqual(PicksView.rows(3), [0..<3])
        XCTAssertEqual(PicksView.rows(4), [0..<4])
        XCTAssertEqual(PicksView.rows(9), [0..<4, 4..<8, 8..<9])
        XCTAssertEqual(PicksView.rows(0), [])
    }

    func testThePicksButtonIsATargetOfItsOwn() {
        for g in geometries {
            let r = PanelView.picksRect(g)
            let repeatRect = PanelView.transportRects(g).first { $0.name == "repeat" }!.rect
            XCTAssertEqual(r.width, NotchGeometry.minimumHitHeight)
            XCTAssertEqual(r.height, NotchGeometry.minimumHitHeight)
            XCTAssertGreaterThanOrEqual(r.minY, g.notchExclusionTop)
            XCTAssertLessThanOrEqual(r.maxX, g.screenFrame.midX + g.openWidth / 2)
            XCTAssertLessThanOrEqual(r.maxY, g.openHeight)
            XCTAssertGreaterThan(r.minX, repeatRect.maxX, "touches repeat")
        }
    }

    func testOnlyASidewaysTrackpadSwipeFlipsThePage() {
        XCTAssertEqual(Expansion.swipe(dx: -60, dy: 5, precise: true), .picks)
        XCTAssertEqual(Expansion.swipe(dx: 60, dy: -5, precise: true), .player)
        XCTAssertNil(Expansion.swipe(dx: -60, dy: 40, precise: true), "mostly scrolling")
        XCTAssertNil(Expansion.swipe(dx: -30, dy: 0, precise: true), "too short")
        XCTAssertNil(Expansion.swipe(dx: -200, dy: 0, precise: false), "a mouse wheel")
    }

    @MainActor func testAClosedPanelHasNoPageToShow() {
        let expansion = Expansion()
        expansion.hasPicks = { true }
        expansion.show(.picks)
        XCTAssertEqual(expansion.page, .player)
    }
}
