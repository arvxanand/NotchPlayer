import XCTest
@testable import NotchPlayerCore

/// Picking the right cover out of a real (trimmed) iTunes Search reply.
final class StoreCoverTests: XCTestCase {
    private var reply: Data {
        let url = Bundle.module.url(forResource: "Fixtures/itunes-search", withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    private func track(_ name: String, _ artist: String, _ album: String) -> Track {
        Track(id: "1A2B", name: name, artist: artist, album: album, duration: 263,
              hasArtwork: false, source: .appleMusic)
    }

    func testTheSameSongOnTheSameAlbumWins() {
        XCTAssertEqual(StoreCover.best(in: reply, for: track("Adventure of a Lifetime", "Coldplay", "A Head Full of Dreams")),
                       URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/c8/0a/6d/c80a6df9-e55a-fb83-0311-f4776984ac67/mzm.lasidxkv.jpg/300x300bb.jpg"))
    }

    /// The live version is its own record, with its own cover.
    func testALiveAlbumGetsItsOwnCover() {
        let url = StoreCover.best(in: reply, for: track("Adventure of a Lifetime (Live In Buenos Aires)",
                                                       "coldplay", "Live In Buenos Aires"))
        XCTAssertEqual(url?.absoluteString.contains("190295530983"), true)
    }

    /// Same title, album unknown to the store: the title by the artist.
    func testTheTitleByTheArtistIsTheFallback() {
        XCTAssertNotNil(StoreCover.best(in: reply, for: track("Adventure of a Lifetime", "Coldplay", "Some Playlist Mix")))
    }

    /// A cover from someone else's record is worse than the Music mark.
    func testAnotherArtistsCoverIsNeverUsed() {
        XCTAssertNil(StoreCover.best(in: reply, for: track("Adventure of a Lifetime", "Someone Else", "A Head Full of Dreams")))
        XCTAssertNil(StoreCover.best(in: reply, for: track("A Different Song", "Coldplay", "Another Album")))
        XCTAssertNil(StoreCover.best(in: Data("nope".utf8), for: track("x", "y", "z")))
    }
}
