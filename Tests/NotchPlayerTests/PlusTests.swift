import XCTest
@testable import NotchPlayerCore

/// The panel's +: which of Spotify's buttons it presses, when it presses
/// rather than opening the song, and where its target is.
final class PlusTests: XCTestCase {
    /// The order Spotify's window gave on 22 Sep 2026, names changed: the
    /// library, the now-playing bar, then an artist page whose own rows carry
    /// the same two labels. Only the bar's is the playing song's.
    private let spotify = [
        "Collapse Your Library", "Search in Playlists", "Play Some Playlist",
        "Now playing view", "Add to playlist", "Enable Smart Shuffle for Some Playlist",
        "Previous", "Play", "Next", "Mute",
        "Play Some Song by Someone", "Add to Liked Songs", "Add to playlist",
    ]

    func testItPicksTheNowPlayingPlusAndNotARowOnThePage() {
        XCTAssertEqual(SpotifyPlus.target(in: spotify), 4)
    }

    /// Measured 23 Sep 2026: a lossless track puts a badge in front of it.
    func testABadgeBeforeThePlusDoesNotHideIt() {
        var labels = spotify
        labels.insert("Lossless", at: 4)
        XCTAssertEqual(SpotifyPlus.target(in: labels), 5)
    }

    /// Without the transport there is no telling where the bar ends, and the
    /// page's rows further down carry the same labels.
    func testNoTransportNoPress() {
        XCTAssertNil(SpotifyPlus.target(in: spotify.filter { $0 != "Previous" }))
    }

    func testAnUnsavedSongIsPressedToo() {
        var labels = spotify
        labels[4] = "Add to Liked Songs"
        XCTAssertEqual(SpotifyPlus.target(in: labels), 4)
    }

    /// After a redesign the bar could hold anything -- a shuffle, a skip --
    /// and pressing it blind would be worse than not. The page's own "Add to
    /// playlist" further down must not be taken instead.
    func testWithNoPlusInTheBarNothingIsPressed() {
        var labels = spotify
        labels.remove(at: 4)
        XCTAssertNil(SpotifyPlus.target(in: labels))
    }

    /// 24 Sep 2026: pressing Spotify's + on an unsaved song only liked it,
    /// with no picker. That button is never pressed; the title's menu opens.
    func testAnUnsavedSongOpensTheMenuAndIsNeverLiked() {
        XCTAssertEqual(SpotifyPlus.step(for: "Add to Liked Songs"), .openMenu)
        XCTAssertEqual(SpotifyPlus.step(for: "Add to playlist"), .pressPlus)
    }

    /// The bar as measured 24 Sep 2026, names changed: a page row's link
    /// before the bar, then the title and two artists, then the transport and
    /// another row's link.
    private let bar: [(role: String, label: String)] = [
        ("AXLink", "Some Other Song"), ("AXButton", "Play Some Other Song"),
        ("AXButton", "Now playing view"),
        ("AXLink", "The Song"), ("AXLink", "Someone"), ("AXLink", "Someone Else"),
        ("AXButton", "Lossless"), ("AXButton", "Add to Liked Songs"),
        ("AXButton", "Previous"), ("AXButton", "Play"), ("AXLink", "A Row Further Down"),
    ]

    func testTheMenuOpensOnTheSongTitleNotAnArtistOrARow() {
        XCTAssertEqual(SpotifyPlus.titleLink(in: bar), 3)
    }

    /// A song called "Previous" is a link, not the transport button.
    func testASongNamedLikeAButtonIsStillTheTitle() {
        var items = bar
        items[3] = ("AXLink", "Previous")
        XCTAssertEqual(SpotifyPlus.titleLink(in: items), 3)
    }

    func testNoTitleNoMenu() {
        XCTAssertNil(SpotifyPlus.titleLink(in: bar.filter { $0.role != "AXLink" }))
        XCTAssertNil(SpotifyPlus.titleLink(in: bar.filter { $0.label != "Now playing view" }))
        XCTAssertNil(SpotifyPlus.titleLink(in: bar.filter { $0.label != "Previous" }))
    }

    func testNoAnchorNoPress() {
        XCTAssertNil(SpotifyPlus.target(in: spotify.filter { $0 != "Now playing view" }))
        XCTAssertNil(SpotifyPlus.target(in: ["Now playing view"]))
        XCTAssertNil(SpotifyPlus.target(in: []))
    }

    func testItOnlyPressesWhenSwitchedOnAndAllowed() {
        for repaired in [false, true] {
            XCTAssertEqual(SpotifyPlus.route(enabled: true, trusted: true, repaired: repaired), .press)
            XCTAssertEqual(SpotifyPlus.route(enabled: false, trusted: true, repaired: repaired), .openSong)
            XCTAssertEqual(SpotifyPlus.route(enabled: false, trusted: false, repaired: repaired), .openSong)
        }
    }

    /// After an update the grant no longer matches (TRAPS #51). The first
    /// click repairs it; after that the + just opens the song, so a declined
    /// prompt does not come back on every click.
    func testSwitchedOnButRefusedRepairsOnceThenOpensTheSong() {
        XCTAssertEqual(SpotifyPlus.route(enabled: true, trusted: false, repaired: false), .repair)
        XCTAssertEqual(SpotifyPlus.route(enabled: true, trusted: false, repaired: true), .openSong)
    }

    /// Switched off never repairs anything: the permission is none of its
    /// business then.
    func testTheRowSaysWhereItStands() {
        XCTAssertEqual(SpotifyPlus.grant(enabled: false, trusted: false), .off)
        XCTAssertEqual(SpotifyPlus.grant(enabled: false, trusted: true), .off)
        XCTAssertEqual(SpotifyPlus.grant(enabled: true, trusted: true), .on)
        XCTAssertEqual(SpotifyPlus.grant(enabled: true, trusted: false), .needsApproval)
    }

    private func track(_ id: String) -> Track {
        Track(id: id, name: "n", artist: "a", album: "b", duration: 1, hasArtwork: false)
    }

    func testOnlyARealTrackGetsAPlus() {
        XCTAssertTrue(PanelView.showsPlus(track("spotify:track:4sIFi8LpJWPvI5xviWFyA6")))
        XCTAssertFalse(PanelView.showsPlus(track("spotify:local:Artist:Album:Song:180")))
        XCTAssertFalse(PanelView.showsPlus(track("spotify:episode:5Xt5DXGzch68nYYamXrNxZ")))
        XCTAssertFalse(PanelView.showsPlus(track("spotify:ad:000000012c603a6600000020316a17a1")))
        XCTAssertFalse(PanelView.showsPlus(track("")))
    }

    // MARK: - The target

    private let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                                         notchWidth: 208, notchHeight: 37, hasNotch: true)

    func testThePlusTargetIsFullSizeInsideThePanelAndBelowTheCamera() {
        let r = PanelView.plusRect(geometry)
        XCTAssertEqual(r.size, CGSize(width: NotchGeometry.minimumHitHeight,
                                      height: NotchGeometry.minimumHitHeight))
        let panel = CGRect(x: geometry.screenFrame.midX - geometry.collapsedWidth / 2, y: 0,
                           width: geometry.collapsedWidth, height: NotchGeometry.panelHeight)
        XCTAssertTrue(panel.contains(r), "\(r) outside \(panel)")
        XCTAssertGreaterThanOrEqual(r.minY, geometry.notchExclusionTop)
    }

    func testThePlusTargetTouchesNeitherTheScrubBandNorTheTransportRow() {
        let r = PanelView.plusRect(geometry)
        XCTAssertFalse(r.intersects(PanelView.progressRect(geometry)))
        for (name, t) in PanelView.transportRects(geometry) {
            XCTAssertFalse(r.intersects(t), name)
        }
    }

    /// The title is a button too, and the + target reaches past its glyph.
    /// The gap between them in the row has to be wider than that reach.
    func testTheTitleStopsShortOfThePlusTarget() {
        XCTAssertGreaterThan(PanelView.plusGap, PanelView.plusOverhang)
    }
}
