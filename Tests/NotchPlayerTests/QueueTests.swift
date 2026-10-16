import XCTest
@testable import NotchPlayerCore

/// Spotify's restore file, rebuilt from invented protobuf pieces in the shape
/// measured on 15 Oct 2026 (TRAPS #78). Never a copy of a real one: it holds
/// the account's id and what it played.
final class QueueTests: XCTestCase {
    // MARK: - Building a file

    private func varint(_ value: Int) -> [UInt8] {
        var value = UInt64(value), out: [UInt8] = []
        repeat {
            out.append(UInt8(value & 0x7f) | (value > 0x7f ? 0x80 : 0))
            value >>= 7
        } while value > 0
        return out
    }

    private func field(_ number: Int, _ bytes: [UInt8]) -> [UInt8] {
        varint(number << 3 | 2) + varint(bytes.count) + bytes
    }

    private func field(_ number: Int, _ text: String) -> [UInt8] { field(number, Array(text.utf8)) }

    /// A 16-byte id whose base62 is easy to predict: `n` in the last byte.
    private func song(_ n: UInt8) -> [UInt8] { Array(repeating: 0, count: 15) + [n] }
    private func id(_ n: UInt8) -> String { SpotifyQueue.base62(song(n)[...])! }

    private func node(_ name: String, _ state: [UInt8]) -> [UInt8] {
        field(1, field(1, "spotify.player.proto." + name) + field(2, state))
    }

    /// Rows 1...6 of a playlist, played in `order`, with row `playing` on now
    /// and `queued` songs added by hand.
    /// Nil `playing` is a queued song on, when Spotify saves no row but its
    /// `place` in the order, already on the next one; 0 is left out, as
    /// protobuf does.
    private func file(queued: [UInt8] = [], order: [UInt8] = [1, 2, 3, 4, 5, 6], playing: UInt8? = 1,
                      place: Int = 0) -> [UInt8] {
        let rows = (1...6).map { n in field(4, field(1, []) + field(2, "row\(n)") + field(3, song(n))) }
        let row = playing.map { field(2, field(1, field(2, "row\($0)") + field(3, song($0)))) } ?? []
        let context = row
            + field(6, field(1, field(1, "spotify:playlist:abc") + field(5, rows.flatMap { $0 }))
                       + field(2, field(3, order.flatMap { field(2, field(2, "row\($0)")) }))
                       + (place == 0 ? [] : varint(5 << 3) + varint(place)))
        let queue = queued.enumerated().flatMap { index, n in
            field(1, field(1, []) + field(2, "q\(index)") + field(3, song(100 + n)))
        }
        // The nested autoplay context has no rows; it must not be taken.
        let nodes = node("ContextNode", field(2, [])) + node("ContextNode", context) + node("PlayQueueNode", queue)
        let message = field(3, field(3, field(1, field(18, field(16, field(1, "player") + field(2, field(12, nodes)))))))
        return Array("1792115328087#".utf8) + message
    }

    // MARK: - The tests

    func testTheSongsComeAfterThePlayingRowInPlayOrder() {
        let state = SpotifyQueue.parse(file(order: [4, 2, 6, 1, 5, 3], playing: 6))
        XCTAssertEqual(state?.upcoming, [id(1), id(5), id(3)], "shuffled: the saved order, not the playlist's")
        XCTAssertEqual(state?.context, "spotify:playlist:abc")
        XCTAssertEqual(state?.queued, [])
    }

    /// Songs queued by hand play first, then the playlist; the page shows five.
    func testQueuedSongsComeFirstAndTheListStopsAtFive() {
        let state = SpotifyQueue.parse(file(queued: [7, 8], playing: 2))
        XCTAssertEqual(state?.queued, [id(107), id(108)])
        XCTAssertEqual(state?.next(5), [id(107), id(108), id(3), id(4), id(5)])
    }

    /// A row id, not a song: the same song twice in a playlist must not send
    /// the list back to its first copy.
    func testThePlaceIsTheRowNotTheSong() {
        XCTAssertEqual(SpotifyQueue.parse(file(playing: 4))?.upcoming, [id(5), id(6)])
        XCTAssertEqual(SpotifyQueue.parse(file(playing: 6))?.upcoming, [], "end of the playlist")
        XCTAssertEqual(SpotifyQueue.parse(file(order: [1, 2], playing: 6))?.upcoming, [],
                       "playing a row the order doesn't have: nothing guessed")
    }

    /// While a queued song plays there is no playing row; Spotify's place
    /// then already points at the next one (checked 15 Oct 2026).
    func testWithAQueuedSongOnThePlaceSaysWhatsNext() {
        let state = SpotifyQueue.parse(file(queued: [7], order: [4, 2, 6, 1, 5, 3], playing: nil, place: 3))
        XCTAssertEqual(state?.next(5), [id(107), id(1), id(5), id(3)])
        XCTAssertEqual(SpotifyQueue.parse(file(playing: nil))?.upcoming.first, id(1), "no place saved: the start")
    }

    func testAnythingElseIsUnreadable() {
        XCTAssertNil(SpotifyQueue.parse([]))
        XCTAssertNil(SpotifyQueue.parse(Array("no hash here".utf8)))
        XCTAssertNil(SpotifyQueue.parse(Array("1#".utf8) + [0xFF, 0xFF, 0xFF]), "not protobuf")
        XCTAssertNil(SpotifyQueue.parse(Array("1#".utf8) + field(3, "x")), "no player nodes")
    }

    func testIDsAreSpotifysBase62() {
        let one: [UInt8] = [0x14, 0xd4, 0x76, 0x33, 0x13, 0xdf, 0x47, 0xa1,
                            0xb5, 0x87, 0x8c, 0x51, 0x3b, 0x47, 0xc9, 0xf5]
        XCTAssertEqual(SpotifyQueue.base62(one[...]), "0DiWol3AO6WpXZgp0goxAV")
        XCTAssertEqual(SpotifyQueue.base62(song(1)[...]), "0000000000000000000001")
        XCTAssertEqual(SpotifyQueue.base62(Array(repeating: 0xFF, count: 16)[...]), "7N42dgm5tFLK9N8MT7fHC7")
        XCTAssertNil(SpotifyQueue.base62([1, 2, 3][...]), "not an id")
    }

    func testTheFileIsFoundUnderAnyAccount() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertNil(SpotifyQueue.read(home: home.path), "no Spotify")
        let account = home.appendingPathComponent("Library/Application Support/Spotify/PersistentCache/Users/x-user")
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        try Data(file(playing: 5)).write(to: account.appendingPathComponent("context_player_state_restore"))
        XCTAssertEqual(SpotifyQueue.read(home: home.path)?.upcoming, [id(6)])
    }

    func testThePreviewGivesTheNameAndCover() {
        let body = Data(#"{"title":"Make Believe","thumbnail_url":"https://image-cdn-ak.spotifycdn.com/image/ab67"}"#.utf8)
        XCTAssertEqual(SpotifyPreview.parse(body),
                       SpotifyPreview.Song(name: "Make Believe",
                                           cover: URL(string: "https://image-cdn-ak.spotifycdn.com/image/ab67")))
        XCTAssertNil(SpotifyPreview.parse(Data(#"{"title":""}"#.utf8)))
        XCTAssertNotNil(SpotifyPreview.url(for: "7IoTUnyyvbMEY2UuE2Tmsx"))
        XCTAssertNil(SpotifyPreview.url(for: "7IoTUnyy/../x&y=zzzzzzz"), "only an id goes in the link")
    }
}
