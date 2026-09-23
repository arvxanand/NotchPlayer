import XCTest
@testable import SpotifyNotchCore

final class ArtworkChangeTests: XCTestCase {
    private let a = URL(string: "https://i.scdn.co/image/a")!
    private let b = URL(string: "https://i.scdn.co/image/b")!

    func testANewCoverDissolvesOverTheOldOne() {
        XCTAssertEqual(ArtworkView.change(showing: a, url: b, ready: true, appearing: false), .dissolve)
    }

    /// While the next cover downloads, the old one stays rather than a black slot.
    func testTheOldCoverStaysWhileTheNewOneDownloads() {
        XCTAssertEqual(ArtworkView.change(showing: a, url: b, ready: false, appearing: false), .keep)
    }

    /// Same album, next song: the cover is already right.
    func testTheSameCoverDoesNotDissolveIntoItself() {
        XCTAssertEqual(ArtworkView.change(showing: a, url: a, ready: true, appearing: false), .keep)
    }

    /// A panel that appears shows its cover; it does not fade one in.
    func testTheFirstDrawDoesNotAnimate() {
        XCTAssertEqual(ArtworkView.change(showing: nil, url: a, ready: true, appearing: true), .show)
    }

    func testNoArtworkClearsTheSlotForTheMark() {
        XCTAssertEqual(ArtworkView.change(showing: a, url: nil, ready: false, appearing: false), .clear)
    }
}
