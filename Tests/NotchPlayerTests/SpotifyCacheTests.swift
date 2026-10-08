import XCTest
@testable import NotchPlayerCore

/// The private-playlist fallback reads Spotify's LevelDB. Each layer is fed
/// hand-built bytes in the real format, so a change in any one fails here
/// rather than as a silent "Playlist" in the notch.
final class SpotifyCacheTests: XCTestCase {
    func testSnappyLiteralsAndCopies() {
        // "abc", then copy 3 bytes from 3 back.
        XCTAssertEqual(SpotifyCache.Snappy.decompress([6, 0x08, 97, 98, 99, 0x0A, 3, 0]),
                       Array("abcabc".utf8))
        XCTAssertNil(SpotifyCache.Snappy.decompress([6, 0x08, 97, 98, 99]), "shorter than it says")
        XCTAssertNil(SpotifyCache.Snappy.decompress([4, 0x0A, 9, 0]), "copies from before the start")
    }

    func testBlockEntriesShareTheirPrefix() {
        // "abc"="x", then "abd"="y" sharing two bytes; one restart at 0.
        let block: [UInt8] = [0, 3, 1] + Array("abcx".utf8) + [2, 1, 1] + Array("dy".utf8) + [0, 0, 0, 0, 1, 0, 0, 0]
        let entries = SpotifyCache.Block.entries(block)
        XCTAssertEqual(entries.map { Array($0.key) }, [Array("abc".utf8), Array("abd".utf8)])
        XCTAssertEqual(entries.map { Array($0.value) }, [Array("x".utf8), Array("y".utf8)])
    }

    private func record(name: String, picture: [UInt8]?) -> [UInt8] {
        var attributes: [UInt8] = [0x0A, UInt8(name.utf8.count)] + Array(name.utf8)
        if let picture { attributes += [0x1A, UInt8(picture.count)] + picture }
        attributes += [0x30, 0] // field 6, varint, as the real one has
        return [0x0A, 2, 0xAA, 0xBB] + [0x1A, UInt8(attributes.count)] + attributes + [0x2A, 1, 0]
    }

    func testTheRecordGivesTheNameAndPicture() {
        let id: [UInt8] = [0xab, 0x67, 0x70, 0x6c, 0x00, 0x00, 0xda, 0x84] + Array(repeating: 0x11, count: 12)
        let found = SpotifyCache.parse(record(name: "Road to 135", picture: id))
        XCTAssertEqual(found?.name, "Road to 135")
        XCTAssertEqual(found?.cover, URL(string: "https://i.scdn.co/image/ab67706c0000da84111111111111111111111111"))
        XCTAssertNil(SpotifyCache.parse(record(name: "No picture", picture: nil))?.cover)
        XCTAssertNil(SpotifyCache.parse(record(name: "Odd id", picture: [1, 2, 3]))?.cover)
        XCTAssertNil(SpotifyCache.parse(record(name: "", picture: nil)), "no name, no record")
        XCTAssertNil(SpotifyCache.parse([0xFF, 0xFF]), "not protobuf")
    }

    /// The log holds what Spotify has not compacted yet: a put, then a later
    /// delete of the same key, both found with their sequence numbers.
    func testTheLogFindsPutsAndDeletes() {
        let key = Array("!pl#slc#k#".utf8)
        func batch(seq: UInt64, put: [UInt8]?) -> [UInt8] {
            var b = (0..<8).map { UInt8(truncatingIfNeeded: seq >> (8 * UInt64($0))) } + [1, 0, 0, 0]
            b += [put == nil ? 0 : 1, UInt8(key.count)] + key
            if let put { b += [UInt8(put.count)] + put }
            return [0, 0, 0, 0, UInt8(b.count), 0, 1] + b
        }
        let log = batch(seq: 7, put: Array("v".utf8)) + batch(seq: 9, put: nil)
        let hits = SpotifyCache.Log.entries(log, key: key)
        XCTAssertEqual(hits.map(\.seq), [7, 9])
        XCTAssertEqual(hits.first?.value, Array("v".utf8))
        XCTAssertNil(hits.last?.value)
    }

    func testNoSpotifyFolderIsNothing() {
        XCTAssertNil(SpotifyCache.playlist("spotify:playlist:abc", home: NSTemporaryDirectory()))
        XCTAssertNil(SpotifyCache.playlist("spotify:album:abc"), "albums are public; not asked")
    }
}
