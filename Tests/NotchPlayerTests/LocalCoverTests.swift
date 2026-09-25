import XCTest
@testable import NotchPlayerCore

/// Laid out like Spotify 1.3.0's `local-files.bnk` as measured on 25 Sep 2026
/// (a type byte, a length byte, the UTF-8), with made-up songs.
final class LocalCoverTests: XCTestCase {
    private func field(_ text: String) -> [UInt8] { [0x09, UInt8(text.utf8.count)] + Array(text.utf8) }

    private func entry(_ title: String, _ artist: String, _ album: String, _ path: String) -> [UInt8] {
        var bytes: [UInt8] = [0x04]
        bytes += field(title)
        bytes += field(artist)
        bytes += field(album)
        bytes += [0x12, UInt8(path.utf8.count)]
        bytes += Array(path.utf8)
        bytes += [0x08, 0x01]
        return bytes
    }

    private func index(_ entries: [UInt8]...) -> Data { Data([0x53, 0x50, 0x43, 0x4F] + entries.joined()) }

    func testFindsThePathForTitleAndArtist() {
        let data = index(entry("Other Song", "Someone", "N/A", "/Users/me/Music/other.mp3"),
                         entry("The Song", "The Artist", "The Album", "/Users/me/Music/Local/the song.mp3"))
        XCTAssertEqual(LocalCover.paths(in: data, title: "The Song", artist: "The Artist"),
                       ["/Users/me/Music/Local/the song.mp3"])
    }

    /// The real title had a curly apostrophe, which `strings` split in two.
    func testAMultiByteTitleMatches() {
        let data = index(entry("Won\u{2019}t Stop", "Band (Feat. Guest)", "", "/Users/me/Music/wont.mp3"))
        XCTAssertEqual(LocalCover.paths(in: data, title: "Won\u{2019}t Stop", artist: "Band (Feat. Guest)"),
                       ["/Users/me/Music/wont.mp3"])
    }

    func testNoMatchNoPath() {
        let data = index(entry("The Song", "The Artist", "", "/Users/me/Music/a.mp3"))
        XCTAssertEqual(LocalCover.paths(in: data, title: "The Song", artist: "Someone Else"), [])
        XCTAssertEqual(LocalCover.paths(in: data, title: "Another", artist: "The Artist"), [])
        XCTAssertEqual(LocalCover.paths(in: Data(), title: "The Song", artist: "The Artist"), [])
    }

    /// "Song" appears inside "The Song", but not as a whole field.
    func testATitleInsideAnotherTitleDoesNotMatch() {
        let data = index(entry("The Song", "The Artist", "", "/Users/me/Music/a.mp3"))
        XCTAssertEqual(LocalCover.paths(in: data, title: "Song", artist: "The Artist"), [])
    }

    /// The index keeps deleted copies, so every candidate comes back in order.
    func testTwoCopiesGiveBoth() {
        let data = index(entry("The Song", "The Artist", "", "/Users/me/Music/old.mp3"),
                         entry("The Song", "The Artist", "", "/Users/me/Music/new.mp3"))
        XCTAssertEqual(LocalCover.paths(in: data, title: "The Song", artist: "The Artist"),
                       ["/Users/me/Music/old.mp3", "/Users/me/Music/new.mp3"])
    }

    func testTheFoldersMacOSGuardsAreSkipped() {
        let home = "/Users/me"
        XCTAssertTrue(LocalCover.readable("/Users/me/Music/Spotify Local Files/a.mp3", home: home))
        XCTAssertTrue(LocalCover.readable("/Users/me/Downloadsish/a.mp3", home: home))
        for guarded in ["/Users/me/Downloads/a.mp3", "/Users/me/Documents/x/a.mp3", "/Users/me/Desktop/a.mp3",
                        "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/a.mp3", "/Volumes/USB/a.mp3"] {
            XCTAssertFalse(LocalCover.readable(guarded, home: home), guarded)
        }
    }

    func testOnlyLocalIdsAreLocal() {
        XCTAssertTrue(LocalCover.isLocal("spotify:local:Artist:Album:Title:197"))
        XCTAssertFalse(LocalCover.isLocal("spotify:track:23khOJxVCE4SEDYCf4mZb8"))
    }

    /// A file with no cover in it gives nothing, and the view keeps its mark.
    func testAFileWithNoCoverGivesNothing() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("no-cover-\(UUID()).mp3")
        try Data("not audio".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = await ArtworkCache.shared.data(for: file)
        XCTAssertNil(bytes)
    }
}
